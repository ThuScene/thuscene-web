# ThuScene Database Design 007 — Stage 6.7.2A
## Default-Privilege Investigation and Proposed Policy

**Status:** Investigation and disposable PostgreSQL 17 policy test complete; proposed policy for review. Not implemented in production.  
**Evidence date:** 2026-11-04  
**Environment:** Live ThuScene Supabase project, inspected read-only through the SQL Editor  
**Scope:** PostgreSQL default privileges for objects created in the `public` schema, with particular attention to objects created by `postgres` and `supabase_admin`.

---

## 1. Purpose

Stage 6.7.2A investigates the default privileges that PostgreSQL applies to newly created objects in the `public` schema. The objective is to establish a least-privilege policy for future ThuScene application objects without unintentionally changing privileges on existing objects or interfering with Supabase-managed platform objects.

This is an investigation and policy proposal only. No live grants, default privileges, roles, policies, or database objects were changed during this stage.

## 2. Evidence collected

The following read-only catalog inspections were performed against the live database on 2026-11-04:

- Default ACL entries in `pg_default_acl`, covering tables, sequences, and functions, for both global and `public` schema scopes.
- Role attributes, including superuser, login, and row-level-security bypass attributes.
- Role memberships and membership options.
- Ownership of objects in the `public` schema.
- The current SQL Editor session identity and its ability to assume the relevant roles.
- Existing application-role table grants and the previously inventoried function privileges.

The results below are a record of the observed state at the time of inspection. They are not a guarantee that Supabase platform defaults will remain unchanged.

## 3. Default privileges observed

### 3.1 Objects created by `postgres`

The explicit `public`-schema default ACLs include:

| Object type | Grantees | Default privileges observed |
|---|---|---|
| Tables | `anon`, `authenticated`, `service_role` | `MAINTAIN`, `REFERENCES`, `TRIGGER`, `TRUNCATE` |
| Tables | `postgres` | Owner privileges |
| Sequences | `postgres` | `SELECT`, `UPDATE`, `USAGE` |
| Functions | `postgres` | `EXECUTE` |

No explicit `public`-schema default grants to application roles were observed for sequences or functions in the `postgres` entries.

### 3.2 Objects created by `supabase_admin`

The explicit `public`-schema default ACLs observed for `supabase_admin` include:

| Object type | Grantees | Default privileges observed |
|---|---|---|
| Tables | `anon`, `authenticated`, `postgres`, `service_role` | `DELETE`, `INSERT`, `MAINTAIN`, `REFERENCES`, `SELECT`, `TRIGGER`, `TRUNCATE`, `UPDATE` |
| Sequences | `anon`, `authenticated`, `postgres`, `service_role` | `SELECT`, `UPDATE`, `USAGE` |
| Functions | `anon`, `authenticated`, `postgres`, `service_role` | `EXECUTE` |

No explicit default-ACL entries for types or schemas were observed in the inspected scopes.

These are Supabase-managed defaults associated with the `supabase_admin` creator role. They are recorded for awareness, not as a proposal to change them.

### 3.3 Global defaults and PostgreSQL built-in defaults

The catalog query covering global entries (`defaclnamespace = 0`) and `public`-schema entries returned only `public`-schema rows. There were no explicit global `pg_default_acl` entries for the inspected creator roles.

This does **not** mean that PostgreSQL has no global or built-in defaults. In particular, PostgreSQL's built-in default is to grant `EXECUTE` on newly created functions and procedures to `PUBLIC`.

PostgreSQL applies global defaults first, then adds per-schema defaults. A per-schema `REVOKE` cannot remove a privilege granted by a global or built-in default. Therefore, removing the built-in `PUBLIC EXECUTE` default requires a global default-privilege change for the relevant creator role, not merely a schema-scoped revoke.

This distinction is important: the observed `postgres` `public`-schema function ACL entry, which lists `postgres` as grantee, does not by itself prove that the built-in `PUBLIC EXECUTE` default has been revoked.

Relevant PostgreSQL 17 documentation:
- [ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html)
- [Privileges](https://www.postgresql.org/docs/current/ddl-priv.html)

## 4. Role and ownership context

The following role attributes were observed:

| Role | Superuser | Can log in | Bypasses RLS |
|---|---:|---:|---:|
| `anon` | No | No | No |
| `authenticated` | No | No | No |
| `postgres` | No | Yes | Yes |
| `service_role` | No | No | Yes |
| `supabase_admin` | Yes | Yes | Yes |

Additional findings:

- The `public` schema owner is `pg_database_owner`.
- The SQL Editor session reported both `session_user` and `current_user` as `postgres`.
- That session could act as a member of `postgres`, but could neither act as a member of nor `SET ROLE` to `supabase_admin`.
- `postgres` is not a member of `supabase_admin`.
- The inspected `public` schema contained no existing tables, views, sequences, functions, or procedures owned by `supabase_admin`.
- The `postgres` role has broad role memberships, including membership in `service_role`; this is relevant when assessing effective privileges and must not be confused with object-level grants.

The available SQL Editor authority does not provide a safe basis for modifying the Supabase-managed `supabase_admin` defaults. No attempt was made to do so.

## 5. Existing-object privileges are a separate matter

The existing application-role grants inventoried previously remain distinct from default privileges:

- `anon` and `authenticated` have SELECT-only table grants on the 13 intended public-read tables.
- They have no table grants on `sources`, `event_sources`, or `taxonomy_aliases`.
- All 16 current public tables have RLS enabled.
- Existing RLS policies constrain public reads, including published-event visibility as applicable.
- The existing functions `rls_auto_enable()` and `set_updated_at()` were previously inspected and had no EXECUTE grants to `PUBLIC`, `anon`, `authenticated`, or `service_role`.

Changing default privileges affects future objects created by the relevant role. It does not retroactively change privileges on existing objects. This proposed remediation therefore does not include revoking or granting privileges on existing tables, sequences, or functions.

## 6. Proposed policy for ThuScene-created objects

The following is the proposed target policy for objects created by `postgres`. It remains subject to local PostgreSQL 17 testing and explicit approval before any production migration.

### 6.1 Tables

Remove automatic table privileges granted to `anon`, `authenticated`, and `service_role` for tables created by `postgres`, specifically:

- `MAINTAIN`
- `REFERENCES`
- `TRIGGER`
- `TRUNCATE`

Do not remove owner privileges from `postgres`.

Future application access should be granted explicitly on the particular object and only to the role that needs it. RLS remains an additional control; it is not a substitute for appropriate SQL privileges.

### 6.2 Sequences

No additional application-role sequence grants were observed in the `postgres` defaults. No sequence-default change is proposed at this point. Local testing should nevertheless confirm the effective privileges on newly created sequences and ensure that any required application access is granted deliberately.

### 6.3 Functions and procedures

Revoke the built-in default `EXECUTE` privilege from `PUBLIC` globally for functions and procedures created by `postgres`.

Grant function execution explicitly to the intended roles, on a function-by-function basis. Do not assume that every function should be callable by `anon`, `authenticated`, or `service_role`.

The local test must verify the effective privileges of a newly created function, including the absence of inherited `PUBLIC EXECUTE`.

### 6.4 Supabase-managed creator role

Leave the observed `supabase_admin` defaults untouched. They appear to be part of Supabase's platform-managed object-creation environment. Do not attempt to alter them through a migration executed as `postgres`.

Avoid placing application-owned objects in schemas or ownership contexts intended for platform-managed objects. If an extension or platform feature requires objects in `public`, assess that separately.

### 6.5 Importer and service role

The current importer uses the Supabase service-role credential for direct database operations. This investigation does not change the importer, its credential, or existing grants.

The proposed policy removes automatic broad privileges for future `postgres`-created objects. Required importer access must be granted explicitly to the relevant objects after its actual operations and privilege requirements have been checked.

## 7. Implementation boundaries and safety requirements

Before a production migration is considered:

1. ~~Test the proposed statements against a disposable PostgreSQL 17 database.~~ **Completed 2026-11-04.**
2. ~~Verify global and schema-specific default ACL behaviour.~~ **Completed in the disposable PostgreSQL 17 test.**
3. ~~Create representative tables, sequences, functions, and procedures under the intended creator role and inspect effective privileges.~~ **Completed in the disposable PostgreSQL 17 test.**
4. ~~Confirm that owner privileges remain intact.~~ **Completed in the disposable PostgreSQL 17 test.**
5. ~~Confirm that `PUBLIC`, `anon`, `authenticated`, and `service_role` receive only the intended privileges.~~ **Completed in the disposable PostgreSQL 17 test, including explicit per-object grants.**
6. Check whether any Supabase-managed workflow or existing importer operation depends on the defaults being removed.
7. Review the exact migration SQL and its execution identity before approval. The available evidence strongly supports `postgres` as the execution role, but the migration runner's identity has not yet been directly observed from within a migration.
8. Apply no production change without a separate, explicit approval and a documented recovery plan.

Do not use `db reset --linked` or any other reset operation against the linked production project. Do not rewrite migrations that have already been applied. Do not modify `supabase_admin` defaults as part of this work.

## 8. Outcome and next stage

**Finding:** The current `postgres` table defaults grant unnecessary automatic privileges to application roles, and the absence of a global default ACL entry means PostgreSQL's built-in `PUBLIC EXECUTE` default for new functions/procedures has not been shown to be revoked.

**Proposed resolution:** Tighten defaults for future `postgres`-created objects as described in Section 6, while leaving `supabase_admin` defaults and all existing object grants unchanged.

**Current status:** Investigation documented and local PostgreSQL 17 policy test passed. The proposed policy has not been implemented or approved for production.

**Next step:** Complete the production migration design review, including the remaining migration-runner identity qualification and deployment/recovery checks. Only then decide whether to create a production migration.

---

## 9. Relationship to earlier work

This investigation builds on:

- [Stage 6.7.1 — Role and Privilege Inventory](Database-Design-007-Stage-6.7.1-Role-and-Privilege-Inventory.md)
- [Stage 6.6 — Same-Event Invariant and PostgreSQL 17 Verification](Database-Design-007-Stage-6.6-Same-Event-Invariant-and-PostgreSQL-17-Verification.md)

It does not supersede the frozen database specification or authorise a production schema or privilege change.


## 10. Local PostgreSQL 17 policy test and execution-identity investigation

### 10.1 Disposable PostgreSQL 17 test

A disposable PostgreSQL 17.11 container was used to test the proposed default-privilege policy. The test created representative tables, a sequence, a function, and a procedure under a dedicated object-creator role, then inspected effective privileges.

Results:

- Newly created tables retained owner privileges; the application roles did not receive the unwanted default table privileges.
- Newly created sequences remained accessible to the owner only.
- Newly created functions and procedures did not inherit PUBLIC EXECUTE after the global default-privilege revoke.
- An explicit table SELECT grant and an explicit function EXECUTE grant worked for the selected roles.
- All test assertions passed.

The test was performed in a disposable local database only. It did not alter the live Supabase project and does not simulate every aspect of Supabase's migration infrastructure or API layer. The runnable test and report are recorded under:

- docs/database/tests/s6-7-2a-postgres17/README.md
- docs/database/tests/s6-7-2a-postgres17/run-s6-7-2a-postgres17.sh

### 10.2 Supabase CLI login-role membership and local role-switching test

Read-only inspection of the live Supabase role membership found that the temporary CLI login role cli_login_postgres is a member of postgres, with INHERIT FALSE, SET TRUE, and no admin option.

A disposable PostgreSQL test role, cli_login_sim, was configured with the corresponding membership options. The test established:

- With session_user = cli_login_sim and current_user = cli_login_sim, ALTER DEFAULT PRIVILEGES FOR ROLE postgres failed with permission denied.
- After SET ROLE postgres, the session reported session_user = cli_login_sim and current_user = postgres; the same default-privilege change succeeded.

This confirms that role switching is a viable way for a CLI login role with the observed membership options to perform the proposed change. It is a local PostgreSQL simulation, not direct evidence of the Supabase migration runner's internal execution sequence.

### 10.3 Linked Supabase CLI query identity

Using the installed Supabase CLI v2.122.0, the read-only linked query:

SELECT session_user, current_user, current_setting('role') AS active_role;

returned:

| Setting | Result |
|---|---|
| session_user | postgres |
| current_user | postgres |
| active_role | none |

This establishes the identity reported by the CLI's linked SQL-query facility. It does not conclusively establish the identity used by the separate supabase db push migration execution path. The migration runner's identity remains to be directly verified or otherwise established from authoritative CLI behaviour before relying on it for production deployment.

### 10.4 Importer privilege review

The inspected BOV importer script, scripts/import-bov-four-test.ts, creates a Supabase client using SUPABASE_SECRET_KEY in server-side code. It performs these operations:

| Table | Operations observed |
|---|---|
| sources | SELECT, INSERT, and read returned ID |
| venues | SELECT, INSERT |
| categories | SELECT |
| events | SELECT, INSERT, UPDATE, and read returned IDs |
| event_categories | UPSERT using conflict target event_id,category_id |
| event_sources | SELECT, INSERT, UPDATE |
| event_occurrences | SELECT, INSERT, UPDATE, and read returned IDs |
| ticket_offers | DELETE, INSERT |

A live privilege check confirmed that service_role currently has all eight standard table privileges on these eight tables. This describes current grants only; it does not create grants on future objects. The importer review does not justify broad automatic privileges for future tables. Any future importer access to a new object should be granted explicitly according to the operations required.

The client code and current grants are consistent with the service-role access model. The client snippet alone does not independently prove the PostgreSQL role used for every API request.

### 10.5 Historical migration reconciliation

The remote Supabase migration history contained two applied versions:

| Remote version | Timestamp (UTC) | Existing tracked SQL file |
|---|---|---|
| 20260919161304 | 2026-09-19 16:13:04 | docs/database/migrations/005_taxonomy_v1.sql |
| 20260919163108 | 2026-09-19 16:31:08 | docs/database/migrations/006_security_harden_database_functions.sql |

Byte-for-byte copies were placed in the standard Supabase CLI migration directory using the exact remote version identifiers:

- supabase/migrations/20260919161304_taxonomy_v1.sql
- supabase/migrations/20260919163108_security_harden_database_functions.sql

SHA-256 verification confirmed that each copy matches its original:

| File pair | SHA-256 |
|---|---|
| 005 original and CLI copy | 091b01eaee2de3db4990cf64012c7ba05ce5b47fbd8c21c14364659bb6e50e3b |
| 006 original and CLI copy | 241d54eb812812ca4ffd8700785354bf4941c193f0a81928c928da33b9bd9535 |

A subsequent npx supabase migration list --linked showed both versions matched in Local and Remote columns, with no pending migrations. No migration repair, db push, reset, or production SQL change was performed during reconciliation.

### 10.6 Execution-identity conclusion and outstanding limitation

The combined evidence supports the expectation that Supabase CLI migration operations can execute with effective role postgres: the live temporary CLI login role has SET membership for postgres; the local simulation demonstrates that switching to postgres permits the required default-privilege change; and the linked CLI SQL-query facility reports current_user = postgres.

However, the linked SQL-query facility and migration runner are distinct execution paths. The identity has not yet been directly observed from within a migration executed by db push. Therefore, the production migration must not rely on an unverified assumption about this behaviour. The exact deployment method and effective execution identity must be confirmed before production application.

**Production status:** No S6.7.2A production migration has been created or applied. No production default privileges have been changed.
