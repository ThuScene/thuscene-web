# Database Design 007 — Stage 6.7.1 — Role and Privilege Inventory

**Status:** Evidence-based inventory recorded; privilege changes and migration SQL are not authorised by this document  
**Date recorded:** 2026-10-26  
**Scope:** Observed live Supabase/PostgreSQL role, table, schema, function and default-privilege state; agreed security direction; importer access trace; unresolved deployment questions  
**Depends on:** ThuScene Database Specification v1 (frozen); Stage 6.6 same-event invariant protocol design

## 1. Purpose and evidence standard

This stage records the live permission state and separates it from design decisions and items still requiring verification. It is an inventory, not a grant script, migration, or claim that the current permission set is the final least-privilege design.

The live catalogue was inspected using read-only SQL against ThuScene's Supabase project on 2026-10-26. The repository, package scripts, migration files and relevant documentation were also inspected. The BOV/Spektrix importer code supplied for review was traced operation by operation.

No database writes, GRANT/REVOKE changes, migration execution, or application-code changes were performed as part of this inventory.

Evidence is a snapshot of the inspected project at the date above. Re-run the relevant catalogue queries before any future permission migration because grants, policies, functions, and deployment tooling may have changed.

## 2. Observed live state

### 2.1 Application tables and row-level security

The live database contains 16 ThuScene application tables in `public`. RLS is enabled on all 16. The three private provenance/mapping tables are `sources`, `event_sources`, and `taxonomy_aliases`.

### 2.2 Table privileges observed

The following summarises the effective table privileges reported by the read-only catalogue inspection. “CRUD” means SELECT, INSERT, UPDATE and DELETE; it does not imply that every operation is allowed by RLS or that it is appropriate for the role.

| Role | Observed table privileges |
|---|---|
| `anon` | SELECT only on 13 public-facing tables listed below; no table grants on `sources`, `event_sources`, or `taxonomy_aliases`. |
| `authenticated` | Same SELECT-only table set as `anon`; no table grants on the three private tables. |
| `service_role` | Broad CRUD on `categories`, `event_categories`, `event_forms`, `event_occurrences`, `event_sources`, `event_tags`, `events`, `sources`, `tags`, `taxonomy_aliases`, `ticket_offers`, and `venues`. On `artists`, `event_artists`, `event_organisers`, and `organisers`, the inspected grants were REFERENCES, TRIGGER and TRUNCATE only; no CRUD or SELECT grant was present. |
| `postgres` | Standard table privileges on all 16 application tables. |

The SELECT-only table set for `anon` and `authenticated` is: `artists`, `categories`, `event_artists`, `event_categories`, `event_forms`, `event_occurrences`, `event_organisers`, `event_tags`, `events`, `organisers`, `tags`, `ticket_offers`, and `venues`.

These are table-level grants, not a complete statement of effective access. RLS policies, ownership, function execution, views, schema permissions and Supabase API configuration also affect what a caller can do. In particular, a table SELECT grant does not mean every row is visible.

### 2.3 Schema privileges and role attributes

- Schema `public`: `anon`, `authenticated`, `service_role`, and `authenticator` have USAGE; the inspected result showed no CREATE grant for those roles.
- `postgres` has USAGE and CREATE on `public`.
- `service_role` has `rolbypassrls = true` and does not have LOGIN.
- `anon` and `authenticated` do not have RLS bypass.
- `postgres` has LOGIN and RLS bypass.
- `supabase_admin` is a superuser and has RLS bypass.

RLS being enabled is an important baseline, but it does not make a privileged secret safe to expose. A role with BYPASSRLS can bypass row policies where it also has the necessary object privileges.

### 2.4 Policies

The inspected policies for `anon` and `authenticated` are SELECT-only. Published-state filtering applies to `events` and related public event/occurrence/ticket-offer and relationship data as defined by the existing policies. The private tables `sources`, `event_sources`, and `taxonomy_aliases` have RLS enabled and no public read policies in the inspected state.

This inventory does not reproduce every policy expression. Before changing policies, retrieve and review their exact definitions from the live catalogue and compare them with the frozen database specification.

### 2.5 Functions and default function privileges

The inspected public-schema functions were:

- `public.rls_auto_enable()`: SECURITY DEFINER, owned by `postgres`, attached to the enabled `ensure_rls` event trigger.
- `public.set_updated_at()`: SECURITY INVOKER, owned by `postgres`, used by update triggers on the application tables.

The effective ACL inspection showed no EXECUTE grant to `PUBLIC`, `anon`, `authenticated`, or `service_role` for either of these existing functions.

A separate default-privilege inspection found a `supabase_admin` default-privilege entry for future functions in `public` that grants EXECUTE to `anon`, `authenticated`, and `service_role`. Default privileges are creator-role-specific and affect future functions, not retroactively every existing function. Therefore, any future controlled function must explicitly review its effective ACL, ownership, SECURITY DEFINER/INVOKER behaviour, search path, and grants rather than assume safe defaults.

### 2.6 Migration history and repository evidence

Supabase migration history records these applied versions:

| Version | Migration |
|---|---|
| `20260919161304` | `005_taxonomy_v1` |
| `20260919163108` | `006_security_harden_database_functions` |

The repository contains the corresponding source files under `docs/database/migrations/`. The package scripts inspected contain only `dev`, `build`, `start`, and `lint`. A tracked-file search found the two migration SQL files but no checked-in Supabase CLI configuration, migration runner, or database deployment script.

The method originally used to apply migrations 005 and 006 could not be recalled and is not established by the repository evidence. Record it as **unverified**; do not infer that the Supabase Dashboard SQL Editor or Supabase CLI was used. The recorded migration history confirms version entries, not the exact operator, execution command, credentials, or deployment process.

## 3. BOV/Spektrix importer access trace

The supplied test importer uses `dotenv`, reads `NEXT_PUBLIC_SUPABASE_URL` and `SUPABASE_SECRET_KEY`, creates a Supabase client, and writes directly to tables. It does not call a PostgreSQL controlled function or use Supabase RPC for these writes. The name of the environment variable alone does not establish the actual key type; verify what value is stored in it before relying on role assumptions.

| Table | Operations used by the inspected importer |
|---|---|
| `sources` | SELECT; INSERT when absent |
| `venues` | SELECT; INSERT when absent |
| `categories` | SELECT |
| `events` | SELECT; INSERT or UPDATE |
| `event_categories` | UPSERT (INSERT/UPDATE conflict path) |
| `event_sources` | SELECT; INSERT or UPDATE |
| `event_occurrences` | SELECT; INSERT or UPDATE |
| `ticket_offers` | DELETE offers for one occurrence, then INSERT replacement offers |

The importer does not directly operate on `artists`, `event_artists`, `organisers`, `event_organisers`, `event_forms`, `tags`, `event_tags`, or `taxonomy_aliases` in the inspected flow. Upsert/conflict behaviour and returned-row requirements can affect the exact privileges needed; validate those details against the deployed PostgREST/PostgreSQL behaviour before narrowing grants.

The current importer is a test workflow, not a finished least-privilege design. It has no transaction spanning the import, and it deletes an occurrence's existing ticket offers before inserting replacements. A later failure can therefore leave partial data or an incomplete offer set. These are operational correctness risks, separate from the privilege inventory.

If `SUPABASE_SECRET_KEY` contains a service-role or equivalent bypass-capable secret, it must remain server-side, be excluded from version control, and never be exposed to browser code. The public `NEXT_PUBLIC_` URL is not itself the secret; secret-key values must not use a `NEXT_PUBLIC_` variable.

## 4. Agreed security decisions

These decisions are agreed design direction; they do not mean live permissions have already been changed.

1. **Public-facing roles:** Keep `anon` and `authenticated` read-only, with no editorial privileges. Public visibility remains controlled by RLS and the intended published-state policies.
2. **Importer:** Retain `service_role` for v1 importer use, subject to reviewing the exact grants required. Keep its secret server-side.
3. **Attendance invariant writes:** For S6.6 invariant-sensitive operations, deny direct application-role DML on protected tables and permit writes only through approved controlled functions. Function ownership, SECURITY DEFINER safety, authorisation, and EXECUTE grants remain to be designed and verified for production.
4. **Migration execution:** Verify the actual execution/deployment mechanism before finalising deployment permissions. The historical execution mechanism for migrations 005 and 006 remains unverified.

The S6.6 attendance-route protocol is design-only at this stage. The attendance-route tables are not part of the currently inspected 16-table live schema, and no production S6.6 migration is authorised by this document.

## 5. Unresolved questions and required evidence

The following items remain open. They should be resolved before a production privilege-changing migration is drafted or applied.

### 5.1 Migration and deployment mechanism

- Choose and document the supported future migration workflow (for example, a controlled Supabase CLI workflow or a documented Dashboard-based process) based on the project's actual needs and operator capabilities.
- Establish how migrations are authenticated and executed, which database role applies them, how the migration history is updated, and how failures/rollbacks are handled.
- Define preflight, approval, execution, postflight catalogue/data verification, evidence capture, and repository commit requirements.
- Do not represent the chosen future workflow as the historical method for 005/006.

### 5.2 Exact importer key and runtime boundary

- Verify whether `SUPABASE_SECRET_KEY` contains a service-role key or another key type, without printing or committing the value.
- Confirm the importer only runs in a trusted server-side/local operator environment and that secret-bearing environment files are ignored by Git.
- Decide whether the v1 importer remains a trusted privileged script or should move to a narrower database role/API. If it remains service-role-backed, document that the privilege boundary is the trusted execution environment, not RLS.

### 5.3 Least-privilege importer grants

- Derive the required grants from the importer operation matrix and any future importer changes.
- Check exact UPSERT and RETURNING requirements for `event_categories` and other writes.
- Decide whether the unusual observed `REFERENCES`, `TRIGGER`, and `TRUNCATE` privileges on four tables are necessary; do not remove them without an impact analysis.
- Review whether broad `service_role` grants are an acceptable v1 operational trade-off or whether a dedicated importer role is warranted.

### 5.4 Controlled-function security

Before implementing S6.6 controlled functions, specify and test:
- function owner and underlying table ownership/privileges;
- fixed `search_path` and schema-qualified object references for SECURITY DEFINER code;
- explicit EXECUTE grants and revocation from PUBLIC and unrelated roles;
- input validation and operation-level authorisation;
- interaction with RLS and intentional privilege elevation;
- supported isolation levels, transaction semantics, failure behaviour and rollback;
- how the global advisory-lock protocol is enforced for every invariant-affecting write path.

### 5.5 Default privileges and public API exposure

- Decide whether the observed default EXECUTE grants for future public-schema functions should be changed, considering which role creates functions and Supabase-managed defaults.
- Ensure every future function is reviewed explicitly; do not rely on default privileges alone as a security boundary.
- Review any future views and API-exposed objects for their security-invoker/definer behaviour and effective access.

## 6. Completion assessment

S6.7.1 is complete as an **evidence-based inventory and decision record** once this document is committed and fetched back from the repository. It does not certify that the current grants are final, that every grant is necessary, or that a future migration workflow has been selected.

No live grants, policies, functions, tables, or migration history were changed in producing this document. No production migration SQL was written or applied.

## 7. Evidence references

- `docs/database/ThuScene-Database-Specification-v1-FROZEN.md` — frozen description of the 16-table post-migration baseline and recorded migration versions.
- `docs/database/Database-Design-007-Stage-6.6-Same-Event-Invariant-and-PostgreSQL-17-Verification.md` — S6.6 invariant protocol, prototype limitations, and production privilege requirements.
- Live read-only catalogue inspection performed 2026-10-26 — table/schema privileges, role attributes, RLS policies, function ACLs, default privileges, and migration history.
- BOV/Spektrix test importer code reviewed in the conversation — direct database operation trace and operational caveats.
