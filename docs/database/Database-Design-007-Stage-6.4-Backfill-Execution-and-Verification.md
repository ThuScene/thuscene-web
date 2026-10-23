# ThuScene Database Design 007 — S6.4 Backfill Execution and Verification

**Status:** Consolidated design agreed; migration implementation not authorised  
**Date:** 2026-10-23  
**Related frozen records:**
- `Database-Design-007-Stage-4-FROZEN DESIGN.md`
- `Database-Design-007-Stage-5-FROZEN-DESIGN.md`
- `ThuScene-Pricing-and-Ticketing-Model-v1-FROZEN.md`

## 1. Purpose and boundary

This document consolidates the adopted decisions from S6.4.1–S6.4.4 for the initial migration of the existing Bristol Old Vic (BOV) Theatre Tours test fixture from `ticket_offers` into the normalized attendance model.

It specifies preconditions, fixture matching, intended normalized records, failure handling, verification and preservation of legacy data.

This is a design record only. It does not contain migration SQL, assert that the live database currently passes its preconditions, or authorise writing or applying migration 007.

Governing principles:

- Fail closed whenever a precondition or mapping assumption is not satisfied.
- Do not invent source identity, eligibility, or missing information.
- Do not silently drop, merge, overwrite, or reuse unexplained records.
- Keep all existing legacy `ticket_offers` rows and values unchanged.
- Verify actual database state; do not rely on a migration success message alone.
- Keep fixture-specific matching and interpretations out of universal database constraints.
- Use the repository's migration history as the authoritative schema-change history.
- Obtain explicit user approval before writing or applying migration 007.

## 2. Known source fixture and target

The previously inspected fixture comprised 28 legacy `ticket_offers` observations: seven offer names repeated once for each of four occurrences.

**Target event**
- Title: `THEATRE TOURS 2026`
- Event ID: `18777239-29c7-447f-a175-2ae709ac78ce`

**Expected occurrences**

| Date | Occurrence ID |
|---|---|
| 4 September 2026 | `ff892a89-2fdb-447c-ab36-41d752379d7c` |
| 11 September 2026 | `11849183-4901-4414-9480-8aaa5c2bb920` |
| 12 September 2026 | `0266b228-5342-46e7-82f3-88df8c499c1b` |
| 26 September 2026 | `7dac085e-919f-4d5e-a015-7cf293576220` |

The prior inspection found the same Bristol Old Vic ticket URL (`https://tickets.bristololdvic.org.uk/`), GBP currency, fixed prices, `limited` availability, `booking_required=true`, provider name `Bristol Old Vic`, and null `description` and `source_reference` across the fixture. These are historical inspection findings, not a substitute for rechecking the live fixture immediately before execution.

## 3. Mandatory preconditions

### 3.1 Event and occurrences

1. Confirm exactly one event exists with the expected ID and title.
2. Confirm all four expected occurrences exist, belong to that event, and match the IDs and dates above.
3. Stop if anything is missing, duplicated, unexpected, or associated with another event.

### 3.2 Legacy fixture integrity

1. Confirm exactly 28 relevant legacy rows, seven per expected occurrence.
2. Confirm all agreed field values and null assumptions still hold.
3. Build the exact fixture-specific composite signatures described in section 4.
4. Require exactly seven distinct signatures, each observed exactly once for each of the four occurrences (complete 4-of-4 coverage).
5. Require prices and currencies to agree across the four observations for each signature.
6. Stop for any missing or null freshness timestamp, missing/duplicate match, changed fixture assumption, or price/currency disagreement. Do not silently select a row or use the latest observation to override a conflict.

### 3.3 Target state and schema readiness

- Inspect the normalized attendance tables for records relating to the target event. The expected starting state is clean.
- If any relevant normalized records exist, stop and inspect their provenance and relationships. Do not automatically reuse, merge, overwrite, or delete them.
- Verify that the required tables, columns, constraints, foreign keys, and migration history match the approved design.
- Before implementation, verify the actual Supabase migration execution mechanism, transaction boundaries, and treatment of failed or interrupted migrations. Do not assume transactional rollback without evidence.

## 4. Offer matching and timestamp consolidation

The fixture-specific composite signature consists of:

- exact offer name;
- ticket URL;
- minimum and maximum price;
- currency;
- legacy price type;
- availability status;
- `booking_required`;
- provider name;
- description; and
- `source_reference`.

Do not match on offer name alone.

Exclude occurrence ID, legacy row ID, timestamps, capacity and available quantity from the signature. They represent observation context, freshness, or inventory information rather than normalized offer identity.

For each of the seven signatures:
- match exactly one observation from each of the four expected occurrences;
- confirm the four observations agree on price and currency;
- set the normalized offer's `last_checked_at` to the maximum timestamp across its four observations.

Set the route's `last_checked_at` to the maximum timestamp across all 28 observations. Missing timestamps are a stop/review condition.

These signatures and rules are one-off migration logic, not permanent uniqueness constraints.

## 5. Intended normalized result

Expected totals:

| Table | Expected rows | Meaning |
|---|---:|---|
| `attendance_routes` | 1 | One shared route for the event |
| `attendance_route_occurrences` | 4 | One link to each expected occurrence |
| `attendance_offers` | 7 | One per distinct offer signature |
| `monetary_components` | 7 | One component per offer |

### 5.1 Route

- One route for the target event; `name=NULL`.
- `attendance_action=book`, interpreted from the fixture's `booking_required=true`.
- `availability_status=limited`.
- `waitlist_available=NULL`.
- `pricing_mechanism=conventional`, as the agreed fixture-specific interpretation of ordinary fixed-price tickets.
- No invented source identity; `source_id=NULL` where applicable.
- Route freshness consolidated as specified in section 4.

### 5.2 Occurrence links

Create exactly one link from the route to each of the four expected occurrences. No additional occurrence links are part of this backfill.

### 5.3 Offers

Create seven distinct offers, shared across the route's four occurrence links.

| Offer name | Minimum | Maximum | Currency |
|---|---:|---:|---|
| Essential Companion | 12 | 12 | GBP |
| Open Concession | 12 | 12 | GBP |
| Pay It Forward | 20 | 20 | GBP |
| Standard | 15 | 15 | GBP |
| Wheelchair User Concession | 12 | 12 | GBP |
| Wheelchair User Pay it Forward | 20 | 20 | GBP |
| Wheelchair User Standard | 15 | 15 | GBP |

For each offer:
- `availability_status=limited`;
- `applicability_scope=unknown`;
- `applicability_description=NULL`;
- party bounds and `coverage_description=NULL`;
- `source_id=NULL` and `source_reference=NULL`;
- preserve the agreed ticket URL;
- consolidate `last_checked_at` from the four matching observations.

Do not infer eligibility from offer names.

### 5.4 Monetary components

Create exactly one component per offer:
- `component_type=admission`;
- `amount_structure=fixed`;
- minimum and maximum equal the agreed offer price;
- `currency=GBP`;
- `charge_basis=unknown`.

The admission classification is a contextual interpretation for this BOV test fixture, not a universal legacy mapping rule.

A missing component or missing price does not establish Free attendance. The frozen pricing model requires positive evidence that there is no mandatory monetary commitment before representing `pricing_mechanism=none`.

## 6. Deliberately excluded legacy fields

Do not migrate or reuse:
- legacy row IDs;
- legacy `created_at` or `updated_at` values;
- `available_quantity` or `capacity`;
- legacy descriptions (null in the inspected fixture);
- inferred source identity or inferred eligibility.

Generate new UUIDs for normalized entities and retain explicit mappings between the route, links, offers, components and their source observations during execution and verification.

Keep the legacy table unchanged. Do not impose a universal uniqueness constraint based on the fixture signature.

## 7. Idempotency, reruns and recovery

The objective is safe diagnosis and recovery, not automatic merging.

- **Clean first run:** proceed only when all preconditions pass and the target state is clean.
- **Existing normalized records:** stop and inspect. If they may come from a completed run, verify actual data and migration history. If partial or inconsistent, diagnose and agree recovery before changing anything.
- **Failure during execution:** use all-or-nothing transactional execution where the verified mechanism supports it. If verification fails before commit, prevent commit where possible.
- **Connection lost / uncertain outcome:** inspect both migration history and actual database state before deciding what to do.
- **Migration reports success but later verification fails:** inspect committed records; do not assume rollback.
- **Constraint rejection:** roll back where supported, then diagnose.
- **Fixture has changed:** stop and reassess the mapping.

Migration history should block normal repeat execution. A preflight guard should reject unexpected target state. Verification must establish what actually happened. Never automatically delete or merge rows merely to force expected counts.

## 8. Final verification and acceptance

Accept the backfill only if all checks pass:

1. Exactly one route, four links, seven offers and seven components exist for the fixture.
2. Every expected occurrence is linked exactly once, and all linked records belong to the target event.
3. Each offer has exactly one correctly valued component.
4. All prices, currencies, availability values, action, pricing mechanism, applicability, nulls and unknowns match the agreed design.
5. Each offer's freshness timestamp equals the maximum of its four source observations.
6. The route freshness timestamp equals the maximum across all 28 source observations.
7. All 28 legacy observations were matched exactly once.
8. All original 28 legacy rows remain present and every original column value is unchanged.
9. No unexpected duplicates, orphans, cross-event links, unsupported source identities or inferred eligibility rules exist.
10. Migration history and actual database state agree with the execution outcome.

Counts alone are insufficient. Verification must cover relationships, values, freshness, source-observation coverage and legacy preservation.

Where the verified execution mechanism permits, run assertions before commit and independently inspect the committed state afterward.

## 9. Legacy preservation and retirement

The existing `ticket_offers` table is not modified by this backfill. Keep its 28 rows, IDs, individual timestamps, and every other column value intact.

Retirement, compatibility changes or deletion of the legacy table are out of scope. They require a separate decision after normalized data is verified and the application transition is assessed.

## 10. Implementation boundary

This specification records the agreed S6.4.1–S6.4.4 backfill design. It does not claim the live preconditions currently pass or that a migration has been executed.

The remaining Stage 6 design register must be reviewed before migration implementation, including exact PostgreSQL types/constraints, cross-event trigger mechanics, RLS/grants and the public query boundary, public pricing/display derivation, and verified migration execution/transaction mechanics.

**No SQL is authorised by this document. Writing or applying migration 007 requires explicit user approval.**
