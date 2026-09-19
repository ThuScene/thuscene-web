# ThuScene Database Specification v1 — PostgreSQL Verification Report

**Result: PASS**  
**Verification date:** 19 September 2026  
**Database writes:** none

## Scope

The 598-line Review Draft was reread and reconciled against fresh, read-only PostgreSQL catalogue queries. Particular attention was given to the lengthy table definitions, full constraint and index inventories, RLS/policies, grants, functions/triggers, and the boundary between database invariants and design/application rules.

## Findings

### Structural verification

PASS. The draft's 16-table structure matches live PostgreSQL. Column names, ordering, PostgreSQL types, nullability and defaults were rechecked. The longer definitions — `events`, `event_occurrences`, `venues`, `organisers`, `artists`, `ticket_offers` and `taxonomy_aliases` — were specifically re-queried rather than inferred from the migration.

### Constraint coverage

PASS. The complete live constraint-name inventory was checked table by table. No constraint present in PostgreSQL was found to contradict or be omitted from the substantive specification. This includes ticket price/quantity checks, occurrence end-time/status checks, review-state checks, taxonomy status/display-order checks, all junction uniqueness/FKs, and both taxonomy-alias semantic checks.

### Index coverage

PASS. The complete live index-name inventory was checked for all 16 tables. The specification correctly covers the additional lookup indexes, the three partial one-primary indexes, and the NULLS NOT DISTINCT active taxonomy-alias unique index. PK/UNIQUE backing indexes are correctly treated separately from additional indexes.

### FK/delete behaviour

PASS. CASCADE, RESTRICT and SET NULL behaviour in the relationship table matches live `pg_constraint` definitions.

### RLS and grants

PASS. RLS is enabled on all 16 tables and is not forced. `anon` and `authenticated` have SELECT only on the 13 public-facing tables and no table privileges on `sources`, `event_sources` or `taxonomy_aliases`. Policy descriptions in the draft match the live predicates.

The non-uniform `service_role` grants were also rechecked. The draft correctly records full standard table privileges on the importer/taxonomy tables and only REFERENCES/TRIGGER/TRUNCATE on artists, event_artists, organisers and event_organisers.

### Functions and triggers

PASS. Both functions use `search_path=pg_catalog`; `rls_auto_enable()` remains SECURITY DEFINER and `set_updated_at()` remains SECURITY INVOKER. PUBLIC, anon, authenticated and service_role have no effective direct EXECUTE on either function; postgres retains it. `ensure_rls` remains enabled. All 16 row-level updated_at triggers remain enabled.

### Canonical data and current state

PASS. The eight Category rows and 24 active Event Forms remain consistent with the draft. Direct SQL counts still show 1 event, 4 occurrences, 1 venue, 8 categories, 1 event-category link, 1 source, 1 event-source link, 28 ticket offers, 24 forms and zero tags/event-tags/aliases/artists/event-artists/organisers/event-organisers.

The existing event still has NULL event_form_id, three `unreviewed` review statuses and three NULL review timestamps.

## Wording audit: database invariant vs design intent

No major category error was found. The draft already separates PostgreSQL-enforced rules from application/editorial rules well.

Two passages were tightened in the verified draft:

1. Inactive taxonomy readability is now explicitly labelled a **database fact**, while using active values for normal assignment/discovery is explicitly labelled an **application/editorial rule**.
2. The existing test event's NULL/unreviewed state is explicitly labelled **verified live state**, while the reason it was not auto-classified is labelled **migration/design history**.

These are documentation clarifications only; no database change is indicated.

## Conclusion

**PASS.** The verified Review Draft accurately represents the live ThuScene PostgreSQL database after migrations 005 and 006. No schema correction or security change is required as a result of this verification.

The document is suitable to be proposed for Frozen status after explicit project approval.