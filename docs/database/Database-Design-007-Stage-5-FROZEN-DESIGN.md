# Database Design 007 --- Stage 5 --- FROZEN DESIGN

**Status:** Frozen PostgreSQL constraint, key, index and lifecycle design baseline  
**Date frozen:** 2026-10-07  
**Depends on:** `Database-Design-007-Stage-4-FROZEN DESIGN.md`  
**Scope:** PostgreSQL structural integrity design for the Stage-4 attendance model. This document does **not** authorise or apply migration 007 SQL.

## 1. Purpose and boundary

Stage 4 froze the conceptual and relational attendance model:

- `attendance_routes`
- `attendance_route_occurrences`
- `attendance_offers`
- `monetary_components`

Stage 5 determines which structural rules PostgreSQL must enforce for that model, including:

- row identity and primary keys;
- foreign keys and physical-delete behaviour;
- the same-event route/occurrence invariant;
- nullability, defaults and unknown semantics;
- controlled-vocabulary enforcement;
- party-size, source-identity and monetary consistency;
- uniqueness and duplicate prevention;
- baseline indexes; and
- lifecycle/mutation invariants.

Stage 5 preserves the Stage-4 principle that PostgreSQL should enforce genuine database invariants while source interpretation, editorial judgement, discovery inference and provider-specific reconciliation remain outside the database where they are not universal relational truths.

This freeze does **not**:

- write migration 007 SQL;
- apply any database change;
- define RLS policies or grants;
- define the public query/view boundary;
- define migration/backfill from the existing `ticket_offers` table; or
- supersede the frozen Stage-4 conceptual model.

## 2. S5.1 --- Row identity

### Entity tables

The following tables use UUID surrogate primary keys, consistent with existing ThuScene entity identity:

- `attendance_routes.id`
- `attendance_offers.id`
- `monetary_components.id`

### Junction table

`attendance_route_occurrences` has no surrogate `id`.

Its primary key is the relationship itself:

```text
(attendance_route_id, event_occurrence_id)
```

This guarantees that a route/occurrence pair can appear at most once and preserves the deliberately minimal Stage-4 junction.

## 3. S5.2 --- Foreign-key lifecycle

The following ownership/dependency relationships use cascading physical deletion:

```text
events
  -> attendance_routes
       -> attendance_offers
            -> monetary_components
```

Specifically:

- `attendance_routes.event_id -> events.id`: cascade;
- `attendance_offers.attendance_route_id -> attendance_routes.id`: cascade;
- `monetary_components.attendance_offer_id -> attendance_offers.id`: cascade;
- `attendance_route_occurrences.attendance_route_id -> attendance_routes.id`: cascade;
- `attendance_route_occurrences.event_occurrence_id -> event_occurrences.id`: cascade.

The provenance relationship is different:

- `attendance_offers.source_id -> sources.id`: restrict physical deletion while referenced.

A source is an independent provenance entity, not an owned child of an attendance offer. Referenced sources must not disappear underneath attendance data.

These delete actions describe the structural consequence **if physical deletion occurs**. They do not define when an event, occurrence, route, offer, component or source should be physically deleted.

## 4. S5.3 --- Same-event route/occurrence invariant

Every occurrence covered by an attendance route must belong to the same event as that route.

The frozen junction remains:

```text
attendance_route_occurrences
- attendance_route_id
- event_occurrence_id
```

No redundant `event_id` is added to the junction.

Because ordinary foreign keys and ordinary `CHECK` constraints cannot enforce this cross-table relationship while retaining the minimal junction, PostgreSQL must enforce the invariant using narrowly scoped constraint-trigger logic.

Enforcement must protect against invalidity introduced by:

- insertion or change of a route/occurrence relationship;
- reassignment of `attendance_routes.event_id`; and
- reassignment of `event_occurrences.event_id`.

No committed database state may contain a route/occurrence relationship whose two parents belong to different events.

The exact SQL implementation, including whether checking is immediate or deferrable until transaction end, remains deliberately deferred to migration design.

## 5. S5.4 --- Nullability, defaults and unknown semantics

### General rule

Required structural relationships and row identity are non-null.

Controlled semantic properties that inherently apply to a row are non-null and, where Stage 4 defines `unknown`, default conservatively to `unknown`.

Optional descriptive, evidential, source-identity, party-bound, monetary-bound and freshness fields remain nullable rather than requiring invented values.

### `attendance_routes`

| Column | Stage-5 rule |
| --- | --- |
| `id` | non-null UUID identity |
| `event_id` | non-null |
| `name` | nullable |
| `attendance_action` | non-null; default `unknown` |
| `availability_status` | non-null; default `unknown` |
| `waitlist_available` | nullable boolean; no false default |
| `applicability_scope` | non-null; default `unknown` |
| `applicability_description` | nullable |
| `minimum_party_size` | nullable |
| `maximum_party_size` | nullable |
| `last_checked_at` | nullable; no automatic freshness default |
| `created_at` | non-null; ordinary creation timestamp default |
| `updated_at` | non-null; ordinary update timestamp mechanism |

### Three-state waitlist representation

```text
TRUE  = waitlist positively established
FALSE = absence of waitlist positively established
NULL  = unknown / insufficient evidence
```

Missing waitlist evidence must never default to `FALSE`.

### `attendance_route_occurrences`

Both columns are non-null and form the composite primary key:

- `attendance_route_id`
- `event_occurrence_id`

There are no defaults.

### `attendance_offers`

| Column | Stage-5 rule |
| --- | --- |
| `id` | non-null UUID identity |
| `attendance_route_id` | non-null |
| `source_id` | nullable |
| `source_reference` | nullable |
| `name` | nullable |
| `offer_url` | nullable |
| `pricing_mechanism` | non-null; default `unknown` |
| `availability_status` | non-null; default `unknown` |
| `applicability_scope` | non-null; default `unknown` |
| `applicability_description` | nullable |
| `minimum_party_size` | nullable |
| `maximum_party_size` | nullable |
| `coverage_description` | nullable |
| `last_checked_at` | nullable; no automatic freshness default |
| `created_at` | non-null; ordinary creation timestamp default |
| `updated_at` | non-null; ordinary update timestamp mechanism |

A populated `source_reference` requires a populated `source_id`.

### `monetary_components`

| Column | Stage-5 rule |
| --- | --- |
| `id` | non-null UUID identity |
| `attendance_offer_id` | non-null |
| `component_type` | non-null; default `unknown` |
| `amount_structure` | non-null; default `unknown` |
| `minimum_amount` | nullable |
| `maximum_amount` | nullable |
| `currency` | nullable; no GBP default |
| `charge_basis` | non-null; default `unknown` |
| `description` | nullable |
| `created_at` | non-null; ordinary creation timestamp default |
| `updated_at` | non-null; ordinary update timestamp mechanism |

A null amount means that no numeric amount is established in that field. Zero is a real known numeric value and must not be substituted for missing or unknown information.

## 6. S5.5 --- Controlled-vocabulary enforcement

The seven Stage-4 controlled vocabularies are stored as ordinary PostgreSQL text values and enforced using explicitly named `CHECK` constraints.

PostgreSQL enum types, custom domain types and lookup tables are not introduced for these structural vocabularies.

### Attendance action

```text
turn_up
buy
book
register
apply
other
unknown
```

### Availability

```text
available
limited
sold_out
closed
unavailable
unknown
```

Used independently on routes and offers.

### Pricing mechanism

```text
none
conventional
flexible
donation_based
other
unknown
```

### Applicability scope

```text
general
restricted
unknown
```

### Monetary component type

```text
admission
mandatory_additional_fee
mandatory_contribution
mandatory_minimum_spend
refundable_deposit
redeemable_payment
optional_contribution
other
unknown
```

### Amount structure

```text
fixed
from
range
variable
unknown
```

### Charge basis

```text
per_person
per_package
per_transaction
other
unknown
```

Identical vocabularies used by multiple columns remain separately constrained rather than being coupled through a shared PostgreSQL enum.

These constraints enforce vocabulary membership. Cross-field consistency is specified separately below.

## 7. S5.6A --- Party-size and source-identity consistency

### Party size

For both routes and offers:

- populated `minimum_party_size` must be an integer >= 1;
- populated `maximum_party_size` must be an integer >= 1;
- either bound may independently be null;
- no party-size default is introduced;
- where both bounds are populated, `minimum_party_size <= maximum_party_size`.

A value such as:

```text
minimum_party_size = 10
maximum_party_size = NULL
```

means an applicability condition of 10 or more.

A value such as:

```text
minimum_party_size = NULL
maximum_party_size = 6
```

means an applicability condition of up to 6.

Route-level and offer-level party restrictions are not required by PostgreSQL to match or nest within one another. More complex applicability consistency remains outside the database unless a later design establishes a genuinely universal invariant.

Party size remains distinct from package coverage.

### Source identity

`source_id` and `source_reference` are nullable, but:

- a non-null `source_reference` requires a non-null `source_id`;
- a populated `source_reference` must contain meaningful non-whitespace content;
- PostgreSQL should reject an empty/whitespace-only reference rather than silently normalising it.

No requirement is imposed that an offer must have a source reference, source-level name or URL merely to exist.

### Source-reference opacity

`source_reference` is opaque provider-specific identity/evidence.

The generic attendance schema does not infer whether a source reference identifies a provider offer, price type, product, performance, package or another provider object. That interpretation belongs to the source adapter.

## 8. S5.6B --- Monetary consistency

### General monetary rules

- Numeric monetary amounts must be non-negative when present.
- Zero is a genuine known amount, not a substitute for null/unknown.
- Negative components are outside the migration-007 model.
- Any populated numeric amount requires a populated currency.
- Currency may be known even when no numeric amount is stored.
- Currency has no default.
- Currency is represented as a normalized uppercase three-letter code.
- PostgreSQL does not embed a complete external currency catalogue as a `CHECK` vocabulary.

Exact numeric precision/scale remains for migration datatype design.

### Amount-structure matrix

| `amount_structure` | `minimum_amount` | `maximum_amount` | Meaning |
| --- | --- | --- | --- |
| `fixed` | required | required and equal to minimum | exactly X |
| `from` | required | null | X or more; no upper bound represented |
| `range` | required | required and greater than minimum | X to Y |
| `variable` | null | null | variable amount; normalized numeric bounds not represented |
| `unknown` | null | null | amount structure unknown |

For `range`, equality is not permitted: equal known bounds are represented as `fixed`.

### Variable amount clarification

`amount_structure = variable` means that numeric bounds are not represented by the normalized monetary component.

It does **not** assert that the underlying provider operational system has no minimum, maximum or other pricing rule.

### Charge basis independence

`charge_basis` remains independent of `amount_structure`.

For example, fixed, from or variable amounts may potentially be per person, per package, per transaction, other or unknown where the source evidence supports that combination.

### Pricing-mechanism independence

Offer-level `pricing_mechanism` remains independent of component-level `amount_structure`.

No database rule mechanically maps:

- `flexible` to `variable`;
- `conventional` to `fixed`; or
- any other pricing mechanism to an amount structure.

A fixed zero monetary component is permitted but does not, by itself, establish that an offer or route is Free.

## 9. S5.6C --- Offer-level monetary integrity

`pricing_mechanism = none` means that ThuScene has positively established the absence of a required monetary commitment. It does not mean merely that no price has been found.

However, `pricing_mechanism = none` does not require an offer to have zero monetary components.

In particular:

- optional monetary components such as `optional_contribution` are compatible with `none`;
- genuine source-supported zero-valued components may coexist with `none`;
- zero remains a known amount rather than being converted into absence.

Import/adaptation logic must not assign `pricing_mechanism = none` where normalized evidence establishes a positive mandatory monetary commitment.

PostgreSQL does not introduce a cross-table trigger attempting to enforce all combinations of offer pricing mechanism and child monetary components. That would embed pricing/business inference into the database rather than protect a universally true relational invariant.

`other` or `unknown` component semantics must not silently be treated as evidence of absence of monetary commitment.

The existence, absence or amount structure of monetary components does not mechanically determine `pricing_mechanism`, and `pricing_mechanism` does not mechanically determine component types or amount structures.

Derived public discovery logic must remain conservative: contradictory or insufficient monetary evidence must not result in an unqualified **Free** presentation.

A required refundable deposit or other required monetary commitment remains material even where the non-refundable cost may be zero.

## 10. S5.7 --- Uniqueness and duplicate prevention

Database uniqueness is imposed only where duplicate rows would necessarily represent the same structural fact.

### Route-occurrence relationship

The composite primary key:

```text
(attendance_route_id, event_occurrence_id)
```

prevents duplicate route-occurrence relationships.

### Entity tables

`attendance_routes`, `attendance_offers` and `monetary_components` rely on their UUID primary keys as their only universally valid row identities.

No content-based uniqueness is imposed on:

- route names;
- route semantic attributes;
- offer names;
- offer URLs;
- applicability descriptions;
- coverage descriptions;
- monetary-component scalar values or descriptions.

### Source references

No universal uniqueness constraint is imposed on:

```text
(source_id, source_reference)
```

including within a single attendance route.

Migration 007 has not established that every provider supplies a stable offer-level identifier with source-wide or route-wide uniqueness semantics.

Source references remain provenance and reconciliation evidence rather than universal database keys.

Source-specific import adapters are responsible for idempotent matching and semantic duplicate detection where their source provides sufficient identity information.

Future source-identity/reconciliation infrastructure remains an explicit extension point and should be introduced only if real importer requirements justify it.

## 11. S5.8 --- Index strategy

Migration 007 uses a deliberately minimal baseline index set based on structural relationships, foreign-key lifecycle operations and established access paths.

Primary keys provide their normal indexes automatically.

The baseline secondary indexes are:

```text
attendance_routes(event_id)

attendance_route_occurrences(event_occurrence_id, attendance_route_id)

attendance_offers(attendance_route_id)
attendance_offers(source_id)

monetary_components(attendance_offer_id)
```

The reverse junction index complements the composite primary key ordered by:

```text
(attendance_route_id, event_occurrence_id)
```

so both route-to-occurrence and occurrence-to-route traversal are supported.

No baseline standalone indexes are introduced merely because columns are constrained or frequently descriptive. In particular, Stage 5 does not require standalone indexes on:

- controlled-vocabulary/status fields;
- `waitlist_available`;
- party-size bounds;
- monetary amounts;
- currency;
- `created_at`; or
- `updated_at`.

The following are deliberately deferred operational-index candidates:

- `(source_id, source_reference)` for proven importer reconciliation access paths;
- freshness indexes involving `last_checked_at`, potentially combined with source;
- availability/applicability compound or partial indexes for the eventual public discovery query;
- monetary/discovery-price indexes if later query design demonstrates a need.

Indexes are performance structures, not semantic constraints. Their omission does not weaken Stage-5 integrity rules.

## 12. S5.9 --- Lifecycle invariants and mutation rules

### Structural parentage

PostgreSQL enforces that:

- a route has an existing event;
- an offer has an existing route;
- a monetary component has an existing offer;
- a route-occurrence relationship has both referenced parents; and
- the route and occurrence in every junction relationship belong to the same event.

### Physical deletion versus status change

Physical deletion follows S5.2.

Status/lifecycle transitions are distinct from physical deletion.

Changing an event or occurrence to a lifecycle state such as cancelled, postponed or archived does not automatically:

- delete attendance data;
- delete route-occurrence links; or
- propagate new route/offer availability values.

### Parent reassignment

Route and occurrence event reassignment is not universally prohibited.

Any committed result must, however, satisfy the S5.3 same-event invariant for all remaining route-occurrence relationships.

The exact transaction/check timing remains for migration SQL design.

### Child-count rules

PostgreSQL does not require:

- every route to have an occurrence relationship;
- every route to have an offer; or
- every offer to have a monetary component.

A route with zero offers and an offer with zero monetary components are explicitly supported by the frozen Stage-4 model.

A route with no current occurrence junction does not establish that the route is usable for an occurrence.

### Availability and waitlist mutation

PostgreSQL does not automatically propagate or derive:

- route availability from offer availability;
- offer availability from route availability; or
- waitlist state from availability state.

These are independently stored normalized facts and must be updated only where evidence supports the change.

### Freshness

`last_checked_at` records actual evidence freshness and is semantically distinct from ordinary row creation/update metadata.

Therefore:

- row creation does not automatically manufacture `last_checked_at`;
- ordinary updates do not automatically modify `last_checked_at`;
- `updated_at` does not imply that source evidence was rechecked;
- no monotonicity constraint is imposed on `last_checked_at`;
- no database rule requires `last_checked_at <= now()`.

Freshness determination belongs to source/import logic.

### Retirement and source reconciliation

Migration 007 introduces no new active/retired/archive lifecycle vocabulary for the attendance tables.

Absence from a source response must not automatically be interpreted as deletion, unavailability or retirement. Source adapters must interpret absence according to the semantics and completeness of the particular provider/API response.

## 13. S5.10 --- Consolidated audit and completion revisions

S5.1 through S5.9 were reviewed together against:

- frozen Database Design 007 Stage 4;
- the frozen ThuScene Pricing and Ticketing Model v1; and
- the frozen/verified ThuScene Database Specification v1 principles.

No contradiction, blocker or requirement to reopen Stage 4 was identified.

The audit adds the following completion clarifications.

### Updated timestamp lifecycle

The three new entity tables that carry `updated_at`:

- `attendance_routes`;
- `attendance_offers`; and
- `monetary_components`

must participate in ThuScene's existing hardened automatic `updated_at` mechanism.

`attendance_route_occurrences` remains deliberately minimal and has no timestamps; the relationship is represented by its existence/non-existence.

This timestamp mechanism must not alter `last_checked_at`.

### Source-reference opacity

As specified in S5.6A, `source_reference` is opaque provider-specific evidence. Generic database logic must not infer provider-object semantics from it.

### Variable amount semantics

As specified in S5.6B, `amount_structure = variable` means normalized numeric bounds are not represented. It does not assert that the provider has no underlying bounds or rules.

## 14. Database invariant versus importer/application responsibility

The Stage-5 boundary can be summarized as follows.

| Rule | PostgreSQL invariant? | Importer/application responsibility? |
| --- | --- | --- |
| Route requires event | Yes | |
| Offer requires route | Yes | |
| Component requires offer | Yes | |
| Junction requires route and occurrence | Yes | |
| Route and linked occurrence belong to same event | Yes | Transaction orchestration where needed |
| Physical parent deletion follows S5.2 | Yes | |
| Controlled vocabulary membership | Yes | |
| Party-size scalar consistency | Yes | |
| Source-reference/source relationship | Yes | Source-specific identity interpretation |
| Monetary row consistency | Yes | |
| Event/occurrence status automatically changes attendance | No | Yes |
| Route requires at least one offer | No | No; explicitly optional |
| Offer requires at least one component | No | No; explicitly optional |
| Route/offer availability propagation | No | Yes |
| Waitlist propagation | No | Yes |
| Pricing-mechanism/component inference | No | Yes, conservatively |
| General-public discovery-price derivation | No | Later public-query layer |
| Source refresh reconciliation | No | Yes |
| Freshness determination | No | Yes |
| `updated_at` means source rechecked | No | No |
| Attendance archive/retirement vocabulary | Not in 007 | Future design if needed |

## 15. Matters deliberately unresolved after Stage 5

The following remain explicitly unresolved and must not be inferred from this freeze:

1. exact PostgreSQL scalar data types and monetary precision/scale;
2. exact SQL constraint, trigger and index names;
3. exact immediate versus deferrable implementation of the S5.3 same-event constraint;
4. RLS policies;
5. grants and service-role access;
6. public query/view boundary;
7. derived discovery-price and Free-presentation logic;
8. migration/backfill from the existing `ticket_offers` table;
9. whether the existing `ticket_offers` table is transformed, retained temporarily, renamed or retired;
10. treatment of existing occurrence-level `capacity` / `available_quantity` during migration;
11. source-specific importer reconciliation mechanics;
12. deferred operational indexes once real access paths are specified;
13. migration ordering, preflight checks, transactional assertions, post-migration verification and rollback/safety strategy; and
14. migration 007 SQL itself.

RLS/grants and public access boundaries remain deliberately deferred even though the existing database has security-hardening mechanisms. Safety-net mechanisms do not substitute for explicit policy design for the new tables.

Existing occurrence-level capacity/quantity fields are not made authoritative inputs to the new attendance availability model merely by migration 007.

## 16. Frozen Stage-5 decisions

The adopted decisions are:

- **007-S5.1:** Row identity.
- **007-S5.2:** Foreign-key lifecycle.
- **007-S5.3:** Same-event route/occurrence invariant.
- **007-S5.4:** Nullability, defaults and unknown semantics.
- **007-S5.5:** Controlled-vocabulary enforcement.
- **007-S5.6A:** Party-size and source-identity consistency.
- **007-S5.6B:** Monetary consistency.
- **007-S5.6C:** Offer-level monetary integrity.
- **007-S5.7:** Uniqueness and duplicate prevention.
- **007-S5.8:** Index strategy.
- **007-S5.9:** Lifecycle invariants and mutation rules.
- **007-S5.10:** Consolidated audit and completion revisions.

---

## Frozen status

**Database Design 007 --- Stage 5 is frozen.**

This document is the authoritative Stage-5 PostgreSQL structural-integrity design baseline for subsequent Database Design 007 work.

It preserves the frozen Stage-4 conceptual model and records the agreed keys, foreign-key lifecycle, cross-table invariant, null/unknown semantics, vocabulary enforcement, scalar consistency, uniqueness policy, baseline indexing and lifecycle boundaries.

This freeze does **not** authorise migration 007 SQL and does not change the existing Supabase/PostgreSQL database.
