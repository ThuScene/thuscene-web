# Database Design 007 — Stage 6.7.2A
## Default Privilege Hardening — Application and Verification Record

- **Status:** Applied and verified
- **Application date:** 4 November 2026
- **Supabase project:** ThuScene production project
- **Migration:** `20261104210219_s6_7_2a_default_privileges.sql`
- **Supabase CLI:** v2.122.0

---

## 1. Purpose

This record documents the production application and verification of the
Stage 6.7.2A default-privilege hardening migration.

The design rationale and investigation findings are recorded separately in:

`Database-Design-007-Stage-6.7.2A-Default-Privilege-Investigation.md`

The PostgreSQL 17 behavioural test is recorded separately in:

`tests/s6-7-2a-postgres17/README.md`

Those documents remain separate records and are not replaced by this report.

## 2. Approved migration

The migration was created as a new, separately reviewed file:

`supabase/migrations/20261104210219_s6_7_2a_default_privileges.sql`

Its two statements:

1. Revoke default `MAINTAIN`, `REFERENCES`, `TRIGGER` and `TRUNCATE`
   privileges from `anon`, `authenticated` and `service_role` for future
   tables created by `postgres` in the `public` schema.
2. Revoke PostgreSQL's default global `PUBLIC EXECUTE` privilege for
   future functions and procedures created by `postgres`.

The migration does not alter existing object privileges, sequence defaults,
or `supabase_admin` defaults.

## 3. Pre-application checks and approval

The migration was inspected against the agreed design and the investigation
findings.

A linked CLI dry-run was completed using:

`npx supabase db push --linked --dry-run --skip-vault`

The CLI identified exactly one pending migration:

`20261104210219_s6_7_2a_default_privileges.sql`

The dry-run completed successfully without applying the migration.

Explicit user approval was then given to apply this one migration using:

`npx supabase db push --linked --skip-vault`

The CLI prompted for confirmation, displayed only the migration above, and
reported:

- Applying migration `20261104210219_s6_7_2a_default_privileges.sql`
- Finished supabase db push.

No other migration was applied as part of this operation.

## 4. Migration-history verification

After application, the following command was run:

`npx supabase migration list --linked`

The Local and Remote migration histories matched:

| Version | Local | Remote |
| --- | --- | --- |
| `20260919161304` | Present | Present |
| `20260919163108` | Present | Present |
| `20261104210219` | Present | Present |

The new migration was recorded remotely with timestamp
`2026-11-04 21:02:19 UTC`.

## 5. Default-privilege verification

A read-only query against `pg_default_acl`, `aclexplode` and the relevant
catalogues inspected explicit default privileges for objects created by
`postgres`.

Observed results:

### Public schema — tables

The explicit default table privileges for `postgres` in `public` contained
only privileges granted to `postgres` itself:

- DELETE
- INSERT
- MAINTAIN
- REFERENCES
- SELECT
- TRIGGER
- TRUNCATE
- UPDATE

No entries remained for `anon`, `authenticated` or `service_role`.

### Global function defaults

The global function default ACL contained `EXECUTE` for `postgres` only.
There was no `PUBLIC` entry.

### Public schema — functions and sequences

The explicit public-schema function default ACL contained `EXECUTE` for
`postgres` only.

The public-schema sequence defaults remained unchanged, with SELECT,
UPDATE and USAGE granted to `postgres` only.

### Storage schema

The query also displayed existing default-privilege entries in the
`storage` schema, including grants to application roles. These were
outside the scope of this migration and were not changed.

## 6. Verification conclusion

The linked migration history confirms that the migration was applied and
recorded remotely.

The post-application catalogue inspection confirms that the intended
default-privilege entries for future objects created by `postgres` are
present in the expected state.

The results are consistent with the disposable PostgreSQL 17 test documented
in `tests/s6-7-2a-postgres17/README.md`.

This verification inspected default ACL catalogues. It did not create
additional production objects to test their resulting privileges.

Existing object privileges were not changed by this migration.

**Stage 6.7.2A: production application and catalogue verification complete.**
