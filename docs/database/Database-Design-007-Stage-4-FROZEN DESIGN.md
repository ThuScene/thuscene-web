# Database Design 007 --- Stage 4 --- FROZEN DESIGN

**Status:** Frozen design baseline for Stage 5
**Scope:** Conceptual/relational design only. This document does **not** authorise or apply migration SQL.

## 1. Purpose and boundary

ThuScene is a **discovery service, not a booking platform**.

The attendance model must store only enough information to communicate, truthfully and conservatively:

- whether an event/occurrence appears attendable;
- what the user needs to do to attend;
- whether a route or offer applies to the user;
- the monetary commitment associated with attendance; and
- sufficient provenance and freshness information to keep those conclusions reliable.

ThuScene does not attempt to reproduce the operational workflow of a booking provider.

## 2. Four-table relational model

### `attendance_routes`

Represents a materially distinct way in which someone can qualify for and exercise attendance at one or more occurrences of an event.

- Belongs to exactly one `event`.
- May cover one or more `event_occurrences`.
- May have zero or more `attendance_offers`.
- May exist without an offer, for example a positively established free turn-up route.

### `attendance_route_occurrences`

Junction between `attendance_routes` and `event_occurrences`.

- Each row links exactly one route to exactly one occurrence.
- A route may cover multiple occurrences.
- An occurrence may be covered by multiple routes.
- Every occurrence covered by a route must belong to the same event as that route.

### `attendance_offers`

Represents a source-supported offer, product, registration or equivalent mechanism through which an attendance route may be obtained or exercised.

- Belongs to exactly one `attendance_route`.
- Is optional: a route may have no offers.
- May have zero or more `monetary_components`.
- Holds source identity, onward URL, pricing mechanism, offer availability, applicability and freshness where known.

### `monetary_components`

Represents a semantically distinct monetary commitment or contribution associated with an attendance offer.

Examples include admission charge, mandatory fee, mandatory contribution, minimum spend, refundable deposit and optional contribution.

- Belongs to exactly one `attendance_offer`.
- An offer may have zero monetary components.
- Monetary components belong to offers, not directly to routes.

## 3. Final field allocation

### `attendance_routes`

```text
id
event_id
name

attendance_action
availability_status
waitlist_available

applicability_scope
applicability_description
minimum_party_size
maximum_party_size

last_checked_at

created_at
updated_at
```

`name` is optional and must not be invented merely to populate the field.

`minimum_party_size` and `maximum_party_size` are **applicability conditions**: they describe the party size required for the route to apply.

### `attendance_route_occurrences`

```text
attendance_route_id
event_occurrence_id
```

The junction remains deliberately minimal.

### `attendance_offers`

```text
id
attendance_route_id

source_id
source_reference

name
offer_url

pricing_mechanism
availability_status

applicability_scope
applicability_description
minimum_party_size
maximum_party_size

coverage_description

last_checked_at

created_at
updated_at
```

`minimum_party_size` and `maximum_party_size` describe eligibility for the offer, for example a group rate available only to parties of 10 or more.

`coverage_description` is separate. It preserves what a package admits, for example "Family of four" or "2 adults and up to 3 children", without creating a detailed party-composition model.

### `monetary_components`

```text
id
attendance_offer_id

component_type
amount_structure

minimum_amount
maximum_amount
currency

charge_basis
description

created_at
updated_at
```

`description` is optional and may preserve a material qualifier such as "Refundable on return of equipment" or "Redeemable against food and drink".

## 4. Final controlled vocabularies

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

`join_waitlist` is deliberately **not** an attendance action.

### Availability

```text
available
limited
sold_out
closed
unavailable
unknown
```

`cancelled` remains an event/occurrence lifecycle concept rather than a route/offer availability value.

### Pricing mechanism

```text
none
conventional
flexible
donation_based
other
unknown
```

`none` means the absence of monetary commitment has been positively established. It is different from `unknown`.

### Applicability scope

```text
general
restricted
unknown
```

Source names alone must not determine applicability. For example, a ticket called "Concession" remains `unknown` unless its eligibility is established.

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

There is no `none` monetary component: known absence of money is represented at the offer/route level, not by manufacturing a monetary row.

### Charge basis

```text
per_person
per_package
per_transaction
other
unknown
```

## 5. Waitlist rule

A waitlist is supplementary discovery information, not another attendance route and not another attendance action.

For example:

```text
attendance_action = buy
availability_status = sold_out
waitlist_available = true
```

may be presented as:

> **Sold out · Waitlist available**

Joining a waitlist must not imply that attendance itself is available.

Absence of waitlist evidence must not automatically be interpreted as "no waitlist". Stage 5 must choose a representation that preserves **yes / no / unknown** semantics rather than defaulting unknown evidence to false.

## 6. Free and unknown rules

Zero monetary components **does not by itself mean Free**.

`pricing_mechanism = none` represents a positively established absence of monetary commitment.

Therefore:

- no monetary components + `pricing_mechanism = none` may support a Free conclusion;
- no monetary components + `pricing_mechanism = unknown` must remain monetarily unknown;
- a genuine source-supported £0 amount may be represented as a fixed monetary amount of zero;
- optional contributions are compatible with Free where there is no mandatory monetary commitment;
- mandatory contributions, fees, minimum spends, deposits or other mandatory commitments must not be hidden by a £0 admission charge.

## 7. Package and group distinction

These concepts must remain separate:

> **Party size determines eligibility. Charge basis determines how money is charged. Coverage describes what a package admits.**

Example --- group rate:

```text
minimum_party_size = 10
component amount = £15
charge_basis = per_person
```

means "£15 per person for groups of 10+".

Example --- family package:

```text
component amount = £40
charge_basis = per_package
coverage_description = "Family of four"
```

The £40 package total must not be divided into an invented per-person price.

Detailed party composition is deliberately not modelled structurally in Stage 4.

## 8. Deliberate exclusions

Migration 007 is not intended to model:

- live inventory quantities or seat counts in the new attendance structures;
- seats, seating plans or source price-band selection;
- basket/session/reservation-hold state;
- checkout or transaction workflow;
- payment methods;
- ticket fulfilment or delivery methods;
- waiting-list position, capacity or operational mechanics;
- detailed adult/child/carer party composition;
- promotional-code processing;
- refunds, exchanges, transfers or resale;
- provider customer/account workflow;
- a generic applicability/rules engine;
- a general membership/subscription product model;
- raw source price-band rows as a required normalized subsystem;
- derived discovery prices or presentation strings as authoritative source data.

Source adapters may inspect operational source detail, including band-level availability, where necessary to derive truthful normalized attendance facts.

## 9. Stage-4 invariants

Stage 5 must preserve the following semantic rules:

1. An event may have zero or more attendance routes; zero routes does not mean Free or unavailable.
2. An attendance route belongs to exactly one event.
3. A route may cover multiple occurrences, and an occurrence may have multiple routes.
4. Every occurrence covered by a route must belong to the same event as that route.
5. A route may have zero offers.
6. An offer belongs to exactly one route.
7. An offer may have zero monetary components.
8. A monetary component belongs to exactly one offer.
9. Monetary components do not belong directly to routes.
10. Applicability must be considered before price aggregation.
11. Availability must be considered before live discovery price aggregation.
12. Restricted or unknown applicability must not silently establish the general-public headline price.
13. Source display names are not stable identity and must not alone establish semantics.
14. Stable source identifiers should be retained where supplied.
15. Pricing mechanism and amount structure are independent concepts.
16. Monetary component type and charge basis must be preserved rather than collapsed into a single headline amount.
17. Package totals must not be divided into invented per-person prices.
18. Zero monetary components alone does not establish Free.
19. Unknown must remain unknown; missing data must not be converted into a positive fact.
20. Waitlist availability does not make a sold-out route available.
21. `apply` is contingent and must not be interpreted as guaranteed attendance.
22. Derived display strings such as "From £15" or "Sold out · Waitlist available" are presentation outputs, not authoritative stored source facts.
23. Source-specific interpretation belongs upstream in import/adaptation logic, not in the public UI.
24. Freshness matters: `last_checked_at` is distinct from ordinary row `updated_at`.
25. ThuScene must model only enough provider detail to support truthful discovery and informed onward action.

## 10. Explicitly unresolved implementation questions for Stage 5

Stage 4 deliberately does **not** decide:

- exact PostgreSQL data types;
- exact `NULL` / `NOT NULL` choices;
- defaults;
- whether controlled vocabularies use `CHECK` constraints, PostgreSQL enums or another mechanism;
- primary-key implementation for `attendance_route_occurrences`;
- exact foreign-key and `ON DELETE` behaviour;
- how the same-event route/occurrence invariant is enforced;
- exact uniqueness rules, including `(source_id, source_reference)`;
- exact consistency checks between amount structure and `minimum_amount` / `maximum_amount`;
- exact consistency checks for `minimum_party_size` / `maximum_party_size`;
- exact representation of three-state `waitlist_available`;
- whether and where availability values may be derived rather than persisted;
- currency type/default and monetary precision;
- indexes;
- RLS policies and grants;
- public query/view boundaries;
- migration and backfill strategy from existing `ticket_offers`;
- whether `ticket_offers` is transformed, retained temporarily, renamed or retired;
- treatment of existing occurrence-level quantity/capacity fields;
- exact source-reference uniqueness where a provider reuses identifiers;
- any migration SQL.

Those are Stage-5 implementation decisions and must not be inferred from this Stage-4 design.

---

## Frozen status

**Database Design 007 --- Stage 4 is frozen as the design baseline for Stage 5.**

This freeze records the agreed conceptual model, field ownership, controlled vocabularies, product boundary and semantic invariants. It does **not** authorise a PostgreSQL migration and does not change the existing ThuScene database.
