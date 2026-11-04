# S6.7.2A — PostgreSQL 17 Default-Privilege Test

**Status:** Local disposable-database test passed  
**Test date:** 2026-11-04  
**PostgreSQL:** 17.11  
**Container image:** `postgres:17-alpine`  
**Test database:** Local Docker container only; no connection to the linked Supabase project  
**Related investigation:** [Stage 6.7.2A Default-Privilege Investigation](../../Database-Design-007-Stage-6.7.2A-Default-Privilege-Investigation.md)

---

## 1. Purpose

This test verifies the proposed Stage 6.7.2A default-privilege policy using PostgreSQL 17. It demonstrates:

1. PostgreSQL's built-in default `PUBLIC EXECUTE` grant on a newly created function.
2. Removal of the observed extra table defaults for `anon`, `authenticated`, and `service_role`.
3. Removal of the built-in `PUBLIC EXECUTE` default globally for functions and procedures created by the migration role.
4. Preservation of owner privileges.
5. No retroactive change to an object created before the default-privilege changes.
6. Continued ability to grant narrowly scoped privileges to a role on a specific object.
7. The resulting global default ACL catalog entry.

This is a PostgreSQL behaviour test, not a production migration and not a full simulation of Supabase's managed database environment.

## 2. Test environment

The disposable container was started on the user's local machine with:

```bash
docker run --name thuscene-s672a-pg17 \
  --detach \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -p 127.0.0.1:55432:5432 \
  postgres:17-alpine
```

Version check:

```bash
docker exec thuscene-s672a-pg17 \
  psql -U postgres -d postgres \
  -c "SELECT version();"
```

Observed version:

```text
PostgreSQL 17.11 on x86_64-pc-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit
```

The test roles were:

- `anon`
- `authenticated`
- `service_role`
- `thuscene_migrator` — a disposable role representing the role that creates ThuScene application objects.

The test granted `USAGE, CREATE` on schema `public` to `thuscene_migrator`. The test role was not a superuser.

## 3. Reproduction

The complete runnable test is:

[`run-s6-7-2a-postgres17.sh`](run-s6-7-2a-postgres17.sh)

From the repository root, with the disposable container running:

```bash
bash docs/database/tests/s6-7-2a-postgres17/run-s6-7-2a-postgres17.sh
```

An alternate container name can be supplied with `CONTAINER_NAME`.

The script creates roles and test objects. It is intended for a **fresh disposable database** and is not re-runnable in the same database without first recreating the container/database. It stops on SQL errors and includes final assertions.

## 4. SQL tested

The test first created `baseline_probe()` as `thuscene_migrator`, before changing defaults. Its effective ACL was inspected using `aclexplode` and `acldefault`.

The baseline result was:

```text
      grantee      | privilege_type | is_grantable
-------------------+----------------+--------------
 PUBLIC            | EXECUTE        | f
 thuscene_migrator | EXECUTE        | f
(2 rows)
```

The test then reproduced the table defaults observed for the live `postgres` creator role and removed them:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE thuscene_migrator
IN SCHEMA public
GRANT MAINTAIN, REFERENCES, TRIGGER, TRUNCATE
ON TABLES TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE thuscene_migrator
IN SCHEMA public
REVOKE MAINTAIN, REFERENCES, TRIGGER, TRUNCATE
ON TABLES FROM anon, authenticated, service_role;
```

It removed the built-in function/procedure default globally:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE thuscene_migrator
REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
```

After those changes, the test created a table, a sequence, a function, and a procedure while operating as `thuscene_migrator`. Their effective ACLs were inspected. The test then granted `SELECT` on the table to `anon`, and `EXECUTE` on the test function to `service_role`, and verified those grants.

The full SQL, including the inspection queries and final assertions, is preserved in the runnable script. No production migration file was created or applied.

## 5. Observed results

### 5.1 New table

The newly created table had the normal owner privileges for `thuscene_migrator`:

```text
      grantee      | privilege_type
-------------------+----------------
 thuscene_migrator | DELETE
 thuscene_migrator | INSERT
 thuscene_migrator | MAINTAIN
 thuscene_migrator | REFERENCES
 thuscene_migrator | SELECT
 thuscene_migrator | TRIGGER
 thuscene_migrator | TRUNCATE
 thuscene_migrator | UPDATE
(8 rows)
```

No automatic grants to `anon`, `authenticated`, or `service_role` appeared.

### 5.2 New sequence

```text
      grantee      | privilege_type
-------------------+----------------
 thuscene_migrator | USAGE
(1 row)
```

No application-role sequence grants appeared.

### 5.3 New function

```text
      grantee      | privilege_type
-------------------+----------------
 thuscene_migrator | EXECUTE
(1 row)
```

There was no `PUBLIC` entry.

### 5.4 New procedure

```text
      grantee      | privilege_type
-------------------+----------------
 thuscene_migrator | EXECUTE
(1 row)
```

There was no `PUBLIC` entry.

### 5.5 Existing function

The pre-change `baseline_probe()` retained its original privileges:

```text
      grantee      | privilege_type
-------------------+----------------
 PUBLIC            | EXECUTE
 thuscene_migrator | EXECUTE
(2 rows)
```

This demonstrates that changing default privileges did not retroactively alter the ACL of an existing function.

### 5.6 Explicit object-specific grants

After granting `SELECT` on the test table to `anon`:

```text
 anon_can_select | anon_can_insert
-----------------+-----------------
 t               | f
(1 row)
```

After granting `EXECUTE` on the test function to `service_role`:

```text
 service_role_can_execute | anon_can_execute
--------------------------+------------------
 t                        | f
(1 row)
```

These results demonstrate that the policy does not prevent deliberate, object-specific access grants.

### 5.7 Default ACL catalog

The final catalog query used a `LEFT JOIN` to `pg_namespace`, so that global entries (`defaclnamespace = 0`) were not excluded.

Observed result:

```text
 scope  | object_type |      grantee      | privilege_type
--------+-------------+-------------------+----------------
 GLOBAL | f           | thuscene_migrator | EXECUTE
(1 row)
```

Here, object type `f` represents functions (including procedures for default-privilege purposes). The global entry grants `EXECUTE` to the owner role; there is no `PUBLIC EXECUTE` entry. No table default ACL row remained for this test role because the schema-specific test grants were fully revoked.

## 6. Conclusion

**The proposed PostgreSQL default-privilege policy passed the disposable PostgreSQL 17.11 test.**

Verified outcomes:

| Requirement | Result |
|---|---|
| Remove automatic table grants to `anon`, `authenticated`, and `service_role` | Passed |
| Preserve normal table-owner privileges | Passed |
| Remove default `PUBLIC EXECUTE` for new functions | Passed |
| Remove default `PUBLIC EXECUTE` for new procedures | Passed |
| Preserve ACLs on objects created before the change | Passed |
| Permit explicit object-specific table grants | Passed |
| Permit explicit object-specific function grants | Passed |
| Confirm the resulting global default ACL in PostgreSQL catalogs | Passed |

## 7. Limitations and cautions

This test establishes PostgreSQL 17 behaviour only. It does not establish that the policy is ready for production deployment.

In particular:

- The test used a disposable role named `thuscene_migrator`, not the live Supabase `postgres` role.
- It did not reproduce Supabase's full role memberships, managed defaults, extensions, event triggers, migration runner, or deployment environment.
- It did not modify or test the `supabase_admin` defaults.
- It did not change privileges on any existing ThuScene object.
- It did not run the ThuScene importer or verify every operation it performs.
- It did not create, apply, or test a production migration against the live project.
- The table-default test deliberately recreated the observed extra grants before revoking them; this verified the revoke behaviour and resulting object ACL.
- The procedure check used PostgreSQL's shared function/procedure default-privilege mechanism.

The production migration must be reviewed separately for its exact execution identity, ordering, privilege effects, and recovery plan. Any production change requires explicit approval.

## 8. Cleanup

After the evidence has been captured, the disposable container can be removed:

```bash
docker rm --force thuscene-s672a-pg17
```

This removes only the local test container. It does not affect the linked Supabase project.

## 9. Relationship to the investigation

This test supports the proposed policy in [Stage 6.7.2A — Default-Privilege Investigation](../../Database-Design-007-Stage-6.7.2A-Default-Privilege-Investigation.md).

The investigation and this test record are evidence and design artefacts. Neither authorises a production migration.
