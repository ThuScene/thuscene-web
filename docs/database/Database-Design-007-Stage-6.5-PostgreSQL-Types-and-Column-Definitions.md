# Database Design 007 — Stage 6.5 — PostgreSQL Types and Column Definitions

**Status:** Agreed type and column-definition design; migration SQL not authorised  
**Date agreed:** 2026-10-23  
**Depends on:** Stage 4 frozen conceptual design; Stage 5 frozen structural design; Stage 6.4 backfill execution and verification decisions  
**Scope:** Exact PostgreSQL scalar types, column nullability/defaults, and proposed explicit constraint names for the four attendance tables. This record does **not** write or authorise migration 007 SQL.

## 1. Decision summary

S6.5 adopts the column definitions below. Monetary columns use `numeric(14,4)`.

The design follows the existing ThuScene schema conventions where appropriate:
- UUID identifiers and foreign keys;
- `text` for descriptive, URL, reference and controlled-vocabulary fields;
- `timestamptz` for timestamps representing instants;
- `now()` defaults for `created_at` and initial `updated_at`;
- a maintained `updated_at` mechanism consistent with the existing `public.set_updated_at()` trigger pattern;
- no default for evidence freshness (`last_checked_at`);
- no arbitrary `varchar(n)` limits, PostgreSQL enum types, custom domains, or `money` columns.

The design preserves all Stage 5 nullability, defaults, vocabulary, monetary, identity, foreign-key and lifecycle rules. Exact SQL syntax, trigger implementation and execution mechanics remain for later stages.

## 2. Scalar type decisions

| Data | PostgreSQL type | Rationale |
|---|---|---|
| Entity primary keys and foreign keys | `uuid` | Consistent with existing ThuScene entity tables. |
| Names, descriptions, URLs, source references and controlled vocabulary | `text` | No arbitrary text-length limits; vocabulary membership is enforced separately by CHECK constraints. |
| Creation, update and evidence-check timestamps | `timestamptz` | Consistent with existing schema; represents an unambiguous instant. |
| Waitlist evidence | `boolean` | Preserves TRUE, FALSE and NULL/unknown. |
| Party-size bounds | `integer` | Whole-number counts; positive when present. |
| Monetary bounds | `numeric(14,4)` | Exact decimal storage, four fractional digits and up to ten digits before the decimal point. |
| Currency | `text` | Validated as an uppercase three-letter code without embedding an external currency catalogue. |

### Monetary precision

Both `minimum_amount` and `maximum_amount` use `numeric(14,4)`.

PostgreSQL may round input values with more than four fractional digits when assigning them to this type. Source adapters/import logic must therefore validate incoming monetary values and must not rely on database coercion as the validation policy. Currency-specific minor-unit handling is not encoded as a universal two-decimal rule.

## 3. Column definitions

**NN** means NOT NULL. Unless shown otherwise, nullable columns have no default.

### 3.1 `attendance_routes`

| Column | Type | Nullability/default |
|---|---|---|
| `id` | `uuid` | NN; `DEFAULT gen_random_uuid()` |
| `event_id` | `uuid` | NN |
| `name` | `text` | NULL |
| `attendance_action` | `text` | NN; `DEFAULT 'unknown'` |
| `availability_status` | `text` | NN; `DEFAULT 'unknown'` |
| `waitlist_available` | `boolean` | NULL; no default |
| `applicability_scope` | `text` | NN; `DEFAULT 'unknown'` |
| `applicability_description` | `text` | NULL |
| `minimum_party_size` | `integer` | NULL |
| `maximum_party_size` | `integer` | NULL |
| `last_checked_at` | `timestamptz` | NULL; no default |
| `created_at` | `timestamptz` | NN; `DEFAULT now()` |
| `updated_at` | `timestamptz` | NN; `DEFAULT now()` |

### 3.2 `attendance_route_occurrences`

| Column | Type | Nullability/default |
|---|---|---|
| `attendance_route_id` | `uuid` | NN |
| `event_occurrence_id` | `uuid` | NN |

The composite primary key is `(attendance_route_id, event_occurrence_id)`. There is no surrogate identifier, timestamp or column default.

### 3.3 `attendance_offers`

| Column | Type | Nullability/default |
|---|---|---|
| `id` | `uuid` | NN; `DEFAULT gen_random_uuid()` |
| `attendance_route_id` | `uuid` | NN |
| `source_id` | `uuid` | NULL |
| `source_reference` | `text` | NULL |
| `name` | `text` | NULL |
| `offer_url` | `text` | NULL |
| `pricing_mechanism` | `text` | NN; `DEFAULT 'unknown'` |
| `availability_status` | `text` | NN; `DEFAULT 'unknown'` |
| `applicability_scope` | `text` | NN; `DEFAULT 'unknown'` |
| `applicability_description` | `text` | NULL |
| `minimum_party_size` | `integer` | NULL |
| `maximum_party_size` | `integer` | NULL |
| `coverage_description` | `text` | NULL |
| `last_checked_at` | `timestamptz` | NULL; no default |
| `created_at` | `timestamptz` | NN; `DEFAULT now()` |
| `updated_at` | `timestamptz` | NN; `DEFAULT now()` |

### 3.4 `monetary_components`

| Column | Type | Nullability/default |
|---|---|---|
| `id` | `uuid` | NN; `DEFAULT gen_random_uuid()` |
| `attendance_offer_id` | `uuid` | NN |
| `component_type` | `text` | NN; `DEFAULT 'unknown'` |
| `amount_structure` | `text` | NN; `DEFAULT 'unknown'` |
| `minimum_amount` | `numeric(14,4)` | NULL |
| `maximum_amount` | `numeric(14,4)` | NULL |
| `currency` | `text` | NULL; no default |
| `charge_basis` | `text` | NN; `DEFAULT 'unknown'` |
| `description` | `text` | NULL |
| `created_at` | `timestamptz` | NN; `DEFAULT now()` |
| `updated_at` | `timestamptz` | NN; `DEFAULT now()` |

## 4. Constraint naming convention

Use explicit, stable, table-qualified names. The names below are the agreed naming plan; their SQL definitions and exact implementation remain subject to the complete migration review.

### 4.1 Primary keys

- `pk_attendance_routes`
- `pk_attendance_route_occurrences`
- `pk_attendance_offers`
- `pk_monetary_components`

### 4.2 Foreign keys and deletion behaviour

| Constraint | Relationship | Delete behaviour |
|---|---|---|
| `fk_attendance_routes_event` | `attendance_routes.event_id → events.id` | CASCADE |
| `fk_attendance_route_occurrences_route` | `attendance_route_occurrences.attendance_route_id → attendance_routes.id` | CASCADE |
| `fk_attendance_route_occurrences_occurrence` | `attendance_route_occurrences.event_occurrence_id → event_occurrences.id` | CASCADE |
| `fk_attendance_offers_route` | `attendance_offers.attendance_route_id → attendance_routes.id` | CASCADE |
| `fk_attendance_offers_source` | `attendance_offers.source_id → sources.id` | RESTRICT |
| `fk_monetary_components_offer` | `monetary_components.attendance_offer_id → attendance_offers.id` | CASCADE |

The cross-table same-event invariant is not represented as an ordinary foreign key or CHECK constraint. S6.6 must settle its narrowly scoped trigger implementation.

### 4.3 Controlled vocabulary checks

| Constraint | Column |
|---|---|
| `ck_attendance_routes_action` | `attendance_routes.attendance_action` |
| `ck_attendance_routes_availability` | `attendance_routes.availability_status` |
| `ck_attendance_routes_applicability_scope` | `attendance_routes.applicability_scope` |
| `ck_attendance_offers_pricing_mechanism` | `attendance_offers.pricing_mechanism` |
| `ck_attendance_offers_availability` | `attendance_offers.availability_status` |
| `ck_attendance_offers_applicability_scope` | `attendance_offers.applicability_scope` |
| `ck_monetary_components_type` | `monetary_components.component_type` |
| `ck_monetary_components_amount_structure` | `monetary_components.amount_structure` |
| `ck_monetary_components_charge_basis` | `monetary_components.charge_basis` |

Each CHECK must enforce the exact Stage 4/5 vocabulary for its column. Identical vocabularies in different columns remain independently constrained; no PostgreSQL enum or shared domain is introduced.

### 4.4 Party-size checks

- `ck_attendance_routes_minimum_party_size`: minimum is NULL or at least 1.
- `ck_attendance_routes_maximum_party_size`: maximum is NULL or at least 1.
- `ck_attendance_routes_party_size_order`: if both bounds are populated, minimum is not greater than maximum.
- `ck_attendance_offers_minimum_party_size`: minimum is NULL or at least 1.
- `ck_attendance_offers_maximum_party_size`: maximum is NULL or at least 1.
- `ck_attendance_offers_party_size_order`: if both bounds are populated, minimum is not greater than maximum.

No party-size default or cross-table requirement that route and offer bounds match is introduced.

### 4.5 Source-reference checks

- `ck_attendance_offers_source_reference_requires_source`: a non-NULL `source_reference` requires a non-NULL `source_id`.
- `ck_attendance_offers_source_reference_nonblank`: a populated `source_reference` must not be empty or whitespace-only.

No universal uniqueness is imposed on `(source_id, source_reference)`.

### 4.6 Monetary checks

- `ck_monetary_components_minimum_nonnegative`: `minimum_amount` is NULL or non-negative.
- `ck_monetary_components_maximum_nonnegative`: `maximum_amount` is NULL or non-negative.
- `ck_monetary_components_amount_requires_currency`: if either amount is populated, `currency` must be populated.
- `ck_monetary_components_currency_format`: a populated currency must match three uppercase ASCII letters.
- `ck_monetary_components_amount_structure_consistency`: enforce the Stage 5 matrix:

| `amount_structure` | Minimum | Maximum |
|---|---|---|
| `fixed` | Required | Required and equal to minimum |
| `from` | Required | NULL |
| `range` | Required | Required and greater than minimum |
| `variable` | NULL | NULL |
| `unknown` | NULL | NULL |

No GBP default is introduced. Currency may be known while both numeric bounds are NULL. A fixed zero amount remains valid data and does not, on its own, establish free attendance.

## 5. Timestamp behaviour

All four entity tables (`attendance_routes`, `attendance_offers`, `monetary_components`) use `created_at timestamptz NOT NULL DEFAULT now()` and `updated_at timestamptz NOT NULL DEFAULT now()`. The junction table has no timestamps.

The entity tables should use the existing ThuScene `public.set_updated_at()` mechanism on updates, subject to verification during migration design.

The update mechanism must **not** modify `last_checked_at`. There is no default or automatic update for `last_checked_at`, no requirement that it be recent, and no constraint that it be earlier than the current time.

## 6. Deliberate exclusions

This stage does not decide or implement:
- same-event constraint-trigger timing/deferrability (S6.6);
- RLS, grants, table access or public view/query boundary (S6.7);
- public pricing derivation and display rules (S6.8);
- backfill execution, transaction boundaries, assertions and recovery mechanics (S6.9);
- source-specific uniqueness or reconciliation;
- automatic availability propagation;
- legacy `ticket_offers` retirement;
- additional operational indexes beyond the Stage 5 baseline.

## 7. Verification checklist for the eventual migration

Before migration SQL is approved, verify that it:
1. Implements exactly these four tables and column definitions.
2. Preserves all Stage 5 nullability, defaults and vocabulary.
3. Uses `numeric(14,4)` for both monetary bounds and validates incoming precision in importer logic.
4. Applies the named foreign-key deletion behaviours.
5. Enforces party size, source reference, currency and amount-structure rules.
6. Keeps freshness timestamps independent from `updated_at`.
7. Uses the agreed existing `updated_at` mechanism without changing `last_checked_at`.
8. Adds no unintended uniqueness, default currency, child-count rule or inference.
9. Leaves all existing tables and the 28 legacy `ticket_offers` rows unchanged during the planned backfill.
10. Does not treat this design record as authorisation to write or apply SQL.

---

**END — Database Design 007 — Stage 6.5**
