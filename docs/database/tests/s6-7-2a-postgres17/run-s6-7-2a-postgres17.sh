#!/usr/bin/env bash
set -euo pipefail

# ThuScene S6.7.2A PostgreSQL 17 default-privilege test.
#
# Run against a fresh, disposable PostgreSQL 17 container only.
# This script creates roles and objects and is intentionally not
# re-runnable in the same database without first recreating that database.
#
# Example:
#   docker run --name thuscene-s672a-pg17 --detach \
#     -e POSTGRES_HOST_AUTH_METHOD=trust \
#     -p 127.0.0.1:55432:5432 postgres:17-alpine
#   bash docs/database/tests/s6-7-2a-postgres17/run-s6-7-2a-postgres17.sh

CONTAINER_NAME="${CONTAINER_NAME:-thuscene-s672a-pg17}"

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "ERROR: Docker container '$CONTAINER_NAME' was not found." >&2
  exit 1
fi

if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]]; then
  echo "ERROR: Docker container '$CONTAINER_NAME' is not running." >&2
  exit 1
fi

docker exec -i "$CONTAINER_NAME" \
  psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
\echo '=== Environment ==='
SELECT version();

\echo '=== Create disposable test roles ==='
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE thuscene_migrator NOLOGIN;
GRANT USAGE, CREATE ON SCHEMA public TO thuscene_migrator;

\echo '=== Baseline: create a function as the test migration role ==='
SET ROLE thuscene_migrator;
CREATE FUNCTION public.baseline_probe()
RETURNS integer
LANGUAGE sql
AS 'SELECT 1';
RESET ROLE;

\echo '=== Baseline: effective function ACL (PUBLIC and owner expected) ==='
SELECT
  CASE WHEN a.grantee = 0 THEN 'PUBLIC'
       ELSE pg_get_userbyid(a.grantee)
  END AS grantee,
  a.privilege_type,
  a.is_grantable
FROM pg_proc AS p
CROSS JOIN LATERAL aclexplode(
  COALESCE(p.proacl, acldefault('f', p.proowner))
) AS a
WHERE p.oid = 'public.baseline_probe()'::regprocedure
ORDER BY grantee, privilege_type;

\echo '=== Reproduce observed postgres table defaults ==='
ALTER DEFAULT PRIVILEGES FOR ROLE thuscene_migrator
IN SCHEMA public
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE
ON TABLES TO anon, authenticated, service_role;

\echo '=== Remove automatic table privileges ==='
ALTER DEFAULT PRIVILEGES FOR ROLE thuscene_migrator
IN SCHEMA public
REVOKE MAINTAIN, REFERENCES, TRIGGER, TRUNCATE
ON TABLES FROM anon, authenticated, service_role;

\echo '=== Remove built-in PUBLIC EXECUTE for future functions/procedures ==='
ALTER DEFAULT PRIVILEGES FOR ROLE thuscene_migrator
REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

\echo '=== Create representative objects after changes ==='
SET ROLE thuscene_migrator;
CREATE TABLE public.policy_probe (
    id bigint PRIMARY KEY,
    description text
);
CREATE SEQUENCE public.policy_probe_seq;
CREATE FUNCTION public.policy_probe_function()
RETURNS integer
LANGUAGE sql
AS 'SELECT 42';
CREATE PROCEDURE public.policy_probe_procedure()
LANGUAGE sql
AS 'SELECT 1';
RESET ROLE;

\echo '=== Table ACL (migration owner only expected) ==='
SELECT
  CASE WHEN a.grantee = 0 THEN 'PUBLIC'
       ELSE pg_get_userbyid(a.grantee)
  END AS grantee,
  a.privilege_type
FROM pg_class AS c
CROSS JOIN LATERAL aclexplode(
  COALESCE(c.relacl, acldefault('r', c.relowner))
) AS a
WHERE c.oid = 'public.policy_probe'::regclass
ORDER BY grantee, privilege_type;

\echo '=== Sequence ACL (migration owner only expected) ==='
SELECT
  CASE WHEN a.grantee = 0 THEN 'PUBLIC'
       ELSE pg_get_userbyid(a.grantee)
  END AS grantee,
  a.privilege_type
FROM pg_class AS c
CROSS JOIN LATERAL aclexplode(
  COALESCE(c.relacl, acldefault('S', c.relowner))
) AS a
WHERE c.oid = 'public.policy_probe_seq'::regclass
ORDER BY grantee, privilege_type;

\echo '=== Function ACL (migration owner only expected) ==='
SELECT
  CASE WHEN a.grantee = 0 THEN 'PUBLIC'
       ELSE pg_get_userbyid(a.grantee)
  END AS grantee,
  a.privilege_type
FROM pg_proc AS p
CROSS JOIN LATERAL aclexplode(
  COALESCE(p.proacl, acldefault('f', p.proowner))
) AS a
WHERE p.oid = 'public.policy_probe_function()'::regprocedure
ORDER BY grantee, privilege_type;

\echo '=== Procedure ACL (migration owner only expected) ==='
SELECT
  CASE WHEN a.grantee = 0 THEN 'PUBLIC'
       ELSE pg_get_userbyid(a.grantee)
  END AS grantee,
  a.privilege_type
FROM pg_proc AS p
CROSS JOIN LATERAL aclexplode(
  COALESCE(p.proacl, acldefault('f', p.proowner))
) AS a
WHERE p.oid = 'public.policy_probe_procedure()'::regprocedure
ORDER BY grantee, privilege_type;

\echo '=== Existing baseline function remains unchanged ==='
SELECT
  CASE WHEN a.grantee = 0 THEN 'PUBLIC'
       ELSE pg_get_userbyid(a.grantee)
  END AS grantee,
  a.privilege_type
FROM pg_proc AS p
CROSS JOIN LATERAL aclexplode(
  COALESCE(p.proacl, acldefault('f', p.proowner))
) AS a
WHERE p.oid = 'public.baseline_probe()'::regprocedure
ORDER BY grantee, privilege_type;

\echo '=== Explicit object-specific grants ==='
GRANT SELECT ON public.policy_probe TO anon;
GRANT EXECUTE ON FUNCTION public.policy_probe_function() TO service_role;

\echo '=== Verify explicit table and function grants ==='
SELECT
  has_table_privilege('anon', 'public.policy_probe', 'SELECT')
    AS anon_can_select,
  has_table_privilege('anon', 'public.policy_probe', 'INSERT')
    AS anon_can_insert;

SELECT
  has_function_privilege(
    'service_role',
    'public.policy_probe_function()',
    'EXECUTE'
  ) AS service_role_can_execute,
  has_function_privilege(
    'anon',
    'public.policy_probe_function()',
    'EXECUTE'
  ) AS anon_can_execute;

\echo '=== Verify resulting default ACL catalog entries ==='
SELECT
  CASE
    WHEN d.defaclnamespace = 0 THEN 'GLOBAL'
    ELSE COALESCE(n.nspname, 'UNKNOWN')
  END AS scope,
  d.defaclobjtype AS object_type,
  CASE
    WHEN x.grantee = 0 THEN 'PUBLIC'
    ELSE pg_get_userbyid(x.grantee)
  END AS grantee,
  x.privilege_type
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n
  ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL aclexplode(d.defaclacl) AS x
WHERE d.defaclrole = 'thuscene_migrator'::regrole
ORDER BY scope, object_type, grantee, privilege_type;

\echo '=== Assertions ==='
DO $$
BEGIN
  IF has_table_privilege('anon', 'public.policy_probe', 'INSERT') THEN
    RAISE EXCEPTION 'FAIL: anon unexpectedly has INSERT on policy_probe';
  END IF;
  IF NOT has_table_privilege('anon', 'public.policy_probe', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL: explicit anon SELECT grant did not take effect';
  END IF;
  IF NOT has_function_privilege(
    'service_role', 'public.policy_probe_function()', 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'FAIL: explicit service_role EXECUTE grant did not take effect';
  END IF;
  IF has_function_privilege(
    'anon', 'public.policy_probe_function()', 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'FAIL: anon unexpectedly has EXECUTE on policy_probe_function';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM pg_default_acl AS d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) AS a
    WHERE d.defaclrole = 'thuscene_migrator'::regrole
      AND d.defaclnamespace = 0
      AND d.defaclobjtype = 'f'
      AND a.grantee = 'thuscene_migrator'::regrole
      AND a.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'FAIL: expected global owner EXECUTE default ACL entry missing';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_default_acl AS d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) AS a
    WHERE d.defaclnamespace = 0
      AND d.defaclrole = 'thuscene_migrator'::regrole
      AND d.defaclobjtype = 'f'
      AND a.grantee = 0
      AND a.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'FAIL: PUBLIC EXECUTE remains in global function defaults';
  END IF;
  RAISE NOTICE 'PASS: all S6.7.2A default-privilege assertions passed';
END
$$;
SQL
