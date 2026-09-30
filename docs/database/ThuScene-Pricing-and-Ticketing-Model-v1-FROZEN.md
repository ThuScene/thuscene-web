# ThuScene Pricing & Ticketing Model v1

**Status:** FROZEN --- ThuScene Pricing & Ticketing Model v1.0\
**Frozen:** 30 September 2026\
**Scope:** Conceptual pricing, attendance, ticketing and availability
model\
**Database status:** No database changes are authorised by this
document.

> **Authority statement:** This document is the authoritative conceptual
> specification for pricing, ticketing, attendance routes and
> availability in ThuScene v1. Changes require an explicit subsequent
> revision; this document must not be silently amended.
>
> This specification defines the conceptual model. It does not itself
> modify the Frozen Database Specification v1 or authorise a database
> migration.

## 1. Purpose

ThuScene needs to answer a practical discovery question:

> **What must an ordinary member of the intended public pay and do in
> order to attend this occurrence?**

A source's lowest numeric ticket price is insufficient to answer that
question reliably.

Real events may involve conventional admission, concessions, child
pricing, accessibility and companion tickets, price bands, family and
group packages, advance and door prices, memberships and existing
entitlements, flexible pricing such as Pay What You Can or Pay What You
Choose, free admission, optional donations, mandatory fees, refundable
deposits, minimum spends, ballots, waitlists, multi-day passes,
multi-session courses, or incomplete pricing information.

ThuScene therefore models **attendance routes** and derives discovery
information from their semantics.

## 2. Core principle

ThuScene must not derive discovery pricing using:

``` text
MIN(all source prices)
```

Instead:

``` text
source evidence
      ↓
event / occurrence
      ↓
intended public
      ↓
attendance routes
      ↓
applicability
      +
attendance action
      +
pricing mechanism
      +
amount structure
      +
monetary components
      +
charge basis
      +
party coverage
      +
occurrence coverage
      +
current availability
      ↓
currently applicable attendance routes
      ↓
discovery presentation
```

The fundamental unit of interpretation is therefore the **attendance
route**, not the isolated price.

## 3. Event and occurrence

An **event** describes what is happening.

An **occurrence** describes a concrete instance of that event:
principally when and where it happens.

ThuScene continues to use concrete occurrences rather than recurrence
rules.

An attendance route may apply to one occurrence, several occurrences, or
an entire course, series, pass or similar collection.

Therefore an attendance offer must not be assumed to belong to exactly
one occurrence.

## 4. Intended public

The **intended public** is the audience for whom the event or occurrence
is genuinely intended.

It must be established independently from relevant evidence, such as:

-   explicit audience description;
-   age restriction or guidance;
-   event format;
-   organiser/source classification;
-   trusted editorial classification;
-   other reliable source evidence.

It must **not** be inferred solely from the price structure being
evaluated.

This prevents circular reasoning such as deciding that a child ticket is
ordinary admission merely because it is the cheapest ticket.

## 5. Ordinary attendance

An **ordinary attendance route** is a route genuinely available to an
ordinary member of the intended public without requiring an incidental
special status.

This definition is contextual.

For a conventional general event:

``` text
Adult/General          £20
Restricted concession £15
```

£20 may represent ordinary attendance.

For an event explicitly intended for young people:

``` text
Age 16–25        £10
Adult supporter  £20
```

£10 may instead represent ordinary attendance.

Therefore ThuScene must not encode universal assumptions such as:

``` text
child = never ordinary
accessibility = never ordinary
concession = always restricted
```

## 6. Attendance route

An **attendance route** is a valid way in which a person can attend an
occurrence or covered set of occurrences.

It is broader than a ticket or attendance offer.

For example:

``` text
Paid theatre performance
└── buy ticket
    └── attendance offer exists
```

whereas:

``` text
Free drop-in parade
└── turn up
    └── no attendance offer required
```

An occurrence can therefore have an attendance route without having a
ticket offer.

## 7. Attendance offer

An **attendance offer** is a source-supported offer, product,
registration or equivalent mechanism through which an attendance
entitlement may be obtained.

It may contain or relate to source identity, offer semantics, pricing,
monetary components, charge basis, party coverage, occurrence coverage,
applicability conditions, availability and attendance action.

An attendance offer is not synonymous with an attendance route.

The conceptual term `attendance offer` is also broader than the existing
database table `ticket_offers`.

The existing database structure must not constrain this conceptual
definition.

## 8. Source identity

Source identity and ThuScene semantics are separate.

For example:

``` text
SOURCE IDENTITY
BOV ticket type 17050AT...

SOURCE NAME
Standard

THUSCENE INTERPRETATION
determined separately
```

Where a source provides stable identifiers, they should be preferred
over human-readable names for source-specific mappings.

A source name such as `Standard`, `Adult`, `Concession` or
`Open Concession` does not by itself establish its ThuScene semantics.

## 9. Offer semantics

Conceptually an offer may have semantics such as:

``` text
general
concession
child
accessibility
companion
promotional
supportive
other
unknown
```

This is not yet a frozen database vocabulary.

Semantics are contextual.

In particular, a source ticket called `Concession` is not automatically
a restricted concession. Bristol Old Vic's Open Concession demonstrates
why source terminology and ThuScene semantics must remain separate.

## 10. Applicability conditions

**Applicability** answers:

> **To whom, when, or under what conditions does this attendance route
> or offer apply?**

Applicability may depend on:

``` text
age
membership
accessibility requirement
companion status
party size
party composition
arrival time
purchase timing
purchase channel
advance versus door
existing entitlement
other conditions
unknown
```

This list is conceptual and non-exhaustive.

Applicability determines whether a route should participate in the
discovery derivation for the user population being represented.

## 11. Pricing mechanism

**Pricing mechanism** answers:

> **How is the amount the attendee pays determined?**

Conceptually this may include:

``` text
conventional
flexible
donation-based
other
unknown
```

Exact database vocabulary remains undecided.

Pricing mechanism is independent of the numerical structure of the
amount.

## 12. Amount structure

**Amount structure** answers:

> **What numerical form does the amount take?**

Conceptually:

``` text
fixed
from
range
variable
none
unknown
```

For example:

``` text
Standard £20
pricing mechanism = conventional
amount structure = fixed
```

whereas:

``` text
Seats £15–£30
pricing mechanism = conventional
amount structure = range
```

and:

``` text
Pay What You Can £0–£20
pricing mechanism = flexible
amount structure = variable
```

Pricing mechanism and amount structure must not be conflated.

## 13. Monetary components and conditions

Attendance may involve several distinct monetary components.

Conceptually these include:

``` text
admission/ticket charge
mandatory additional fee
mandatory minimum spend/purchase
refundable deposit
redeemable payment/credit
optional contribution
other
unknown
```

These components must retain their meaning.

A refundable deposit must not silently become an admission price. An
optional donation must not silently become a mandatory charge. A
mandatory fee must not disappear merely because it is not part of the
advertised ticket face value.

## 14. Admission price versus monetary commitment

The admission/ticket charge and the complete monetary commitment
required to attend are not necessarily identical.

Example:

``` text
Ticket                 £20
Mandatory booking fee   £2
```

The ticket charge is £20, but the route cannot be completed for £20.

Likewise:

``` text
Admission       £0
Minimum spend  £20
```

has zero admission price but a mandatory £20 monetary condition.

ThuScene must preserve these distinctions.

## 15. Free attendance

**Free attendance** means:

> **No mandatory monetary commitment is required in order to use the
> relevant ordinary attendance route.**

Free must be positively established.

The following does **not** establish Free:

``` text
no ticket offers recorded
```

because that could mean free drop-in, paid on the door, ticket
information unavailable, price unknown, import incomplete, or not yet on
sale.

## 16. Zero admission price is not necessarily Free attendance

These are distinct:

``` text
Admission price = £0
```

and:

``` text
Attendance = Free
```

For example:

``` text
Admission          £0
Mandatory deposit £10
```

has zero admission price but is not unqualified Free attendance under
the model.

Likewise:

``` text
Admission      £0
Minimum spend £20
```

has zero admission price but requires a monetary commitment.

The eventual UI may use phrases such as
`Free entry · £20 minimum spend`, but the underlying semantic model must
preserve the mandatory condition.

## 17. Optional contributions

An optional contribution does not prevent an attendance route from being
Free.

For example:

``` text
Admission £0
Donation  optional
```

may truthfully produce:

> **Free · Optional donation**

Similarly:

``` text
Admission          £0
Suggested donation £5
Payment genuinely optional
```

may produce:

> **Free · £5 suggested donation**

ThuScene does not attempt to model subjective social pressure. It
records the objective distinction between optional and mandatory
payment.

## 18. Mandatory contributions

If a payment must be made in order to attend, it is a mandatory monetary
condition regardless of the organiser's terminology.

For example:

``` text
Minimum donation £5 required
```

does not constitute Free attendance.

## 19. Mandatory fees

Mandatory ancillary charges must be preserved.

Their basis also matters.

For example:

``` text
£2 per ticket
```

is different from:

``` text
£2 per booking/transaction
```

For two £20 tickets, these could produce totals of £44 and £42
respectively.

ThuScene must not manufacture a complete per-person price unless the
basis of all mandatory components is sufficiently known.

## 20. Refundable deposits

A mandatory refundable deposit is a material attendance condition but is
not an admission charge.

Example:

``` text
Admission          £0
Refundable deposit £10
```

A truthful presentation could be:

> **£0 admission · £10 refundable deposit**

or another suitable UI formulation.

The important requirement is that neither fact is lost.

## 21. Redeemable payments

A mandatory payment redeemable against another purchase is similarly
distinct.

Example:

``` text
£10 required
£10 redeemable against food/drink
```

is not economically identical to a £10 admission fee.

The payment remains mandatory, but its redeemable nature must be
preserved.

## 22. Charge basis

**Charge basis** answers:

> **To what unit does a monetary amount apply?**

Conceptually this may include:

``` text
per_person
per_package
per_booking/transaction
other
unknown
```

This is separate from party coverage.

## 23. Party coverage

**Party coverage** answers:

> **Who or how many attendees receive attendance entitlement from the
> offer?**

For example:

``` text
Family package
£30
covers up to 5 people
```

can be represented conceptually as:

``` text
charge basis = per_package
party coverage = up to 5 people
```

This must not be converted into `£6 per person` unless the source itself
defines a £6 per-person rate.

## 24. Group eligibility versus charge basis

Consider:

``` text
Groups of 10+
£15 per person
```

This means:

``` text
applicability:
minimum party size = 10

charge basis:
per_person
```

It does **not** mean £150 per group unless the source actually sells a
£150 group package.

Applicability and charge basis are independent.

## 25. Occurrence coverage

**Occurrence coverage** answers:

> **Which occurrence or occurrences does this attendance entitlement
> cover?**

Conceptually:

``` text
single occurrence
multiple specified occurrences
whole course/series/event
other
unknown
```

Occurrence coverage is independent of party coverage.

## 26. Multi-occurrence offers

Example:

``` text
Friday         £30
Saturday       £30
Sunday         £30
Weekend pass   £60
```

The weekend pass is one attendance offer covering multiple occurrences.

It must not be represented as three independent £60 offers merely
because the database is occurrence-centric.

## 27. Courses and series

Example:

``` text
Six-week pottery course
£120
```

with six scheduled sessions means:

``` text
one enrolment
£120
covers six occurrences
```

not:

``` text
six independent £120 admissions
```

This is conceptually supported even if the current database schema later
proves unable to represent it directly.

## 28. Attendance action

**Attendance action** describes what action is relevant to obtaining or
exercising attendance.

Conceptually:

``` text
turn_up
buy
book
register
apply
join_waitlist
other
unknown
```

However, these actions do not all have the same effect.

## 29. Securing versus contingent actions

A **securing/exercising action** is one whose successful completion
obtains or exercises the relevant attendance entitlement, subject to the
source's normal conditions.

Examples:

``` text
buy
book
register
turn_up
```

A **contingent action** does not itself guarantee attendance.

Examples:

``` text
apply to ballot
join waitlist
```

This distinction prevents application or waitlist availability from
being mistaken for admission availability.

## 30. Availability

**Attendance availability** answers:

> **Can the relevant attendance entitlement or route currently be
> obtained or exercised?**

Availability should be interpreted at the finest reliable level provided
by the source.

That may include occurrence, attendance route, ticket type, price band,
accessibility allocation, or another source-supported level.

The availability of an associated action does not establish attendance
availability.

For example:

``` text
waitlist open
```

does not mean:

``` text
tickets available
```

## 31. Ballots

Example:

``` text
Free event
Applications open
Places allocated by ballot
```

The attendee can apply, but attendance is not guaranteed.

A truthful presentation might be:

> **Free · Ballot open**

provided `Free` describes the monetary requirement rather than implying
guaranteed availability.

## 32. Waitlists

Example:

``` text
Tickets sold out
Waitlist open
```

The correct concepts coexist:

``` text
attendance availability = sold out
contingent action = join waitlist
```

A possible presentation:

> **Sold out · Waitlist available**

## 33. Configured versus currently available prices

A configured source price is not necessarily currently obtainable.

Therefore:

> **Configured price ≠ currently available price.**

Where sufficiently granular availability exists, unavailable price
routes must be removed before deriving the live discovery price.

## 34. Availability before aggregation

The BLAZE FM test demonstrated this.

Configured Standard prices:

``` text
Band A £19
Band B £16
Band Z £12
```

Current source availability identified Band A and Band B but not Band Z.

Therefore the currently available Standard range is:

``` text
£16–£19
```

not:

``` text
£12–£19
```

The required sequence is:

``` text
configured source prices
        ↓
availability filtering
        ↓
applicability filtering
        ↓
semantic interpretation
        ↓
aggregation of equivalent routes
        ↓
discovery presentation
```

## 35. Multiple ordinary prices

Where several currently available prices genuinely apply to the ordinary
intended public:

``` text
General A £15
General B £20
General C £25
```

a discovery result such as:

> **From £15**

may be valid.

The rule depends on applicability and semantics, not the existence of a
source ticket called `Standard`.

## 36. Restricted and conditional prices

A lower restricted price does not establish the ordinary headline merely
because it is numerically lower.

Example:

``` text
General                £20
Restricted concession  £15
Essential Companion     £0
```

ordinary discovery remains:

> **£20**

assuming the general route is currently available.

## 37. Flexible pricing

Flexible pricing must be identified before individual levels are
interpreted conventionally.

A source may use predefined levels such as:

``` text
Open Concession
Standard
Pay It Forward
```

as choices within one flexible pricing mechanism.

They must not automatically be interpreted as conventional restricted
concession/general/premium tickets.

## 38. Pay What You Can / Pay What You Choose

Source terminology should be preserved where meaningful.

Pay What You Can and Pay What You Choose must not automatically be
assumed to operate identically.

Possible implementations include predefined levels, arbitrary amounts
above a minimum, a suggested amount with lower values permitted, zero
permitted, or a mandatory minimum contribution.

Evidence for the mechanism should preferably come from:

1.  explicit structured source data;
2.  explicit event/source wording;
3.  documented source policy plus evidence that the event participates;
4.  trusted source-specific mapping/editorial classification;
5.  otherwise unknown.

Ticket-name patterns alone must not become universal semantics.

## 39. Flexible pricing where zero is permitted

Consider:

``` text
Pay What You Can
£0–£20
£0 genuinely permitted
```

No mandatory monetary commitment is required.

The route therefore satisfies the semantic condition for free
attendance.

However, presentation may prefer the more informative pricing mechanism:

> **Pay What You Can · £0+**

rather than simply:

> Free

Classification and presentation are therefore distinct.

A richer pricing description may take presentation precedence over a
less informative but technically true label.

## 40. Free drop-in attendance

Where reliable source evidence establishes:

``` text
mandatory monetary commitment = none
attendance action = turn_up
attendance offer = none
```

the occurrence can truthfully be described as:

> **Free**

No synthetic zero-price ticket offer should be created.

## 41. Free registration

Where:

``` text
mandatory monetary commitment = none
attendance action = register
```

a result such as:

> **Free · Registration required**

is legitimate.

Free and attendance action are independent.

## 42. Paid on the door

Example:

``` text
£5 mandatory admission charge
no advance ticket
attendance action = turn_up / pay at door
```

is paid attendance.

The absence of an advance ticket offer does not make the occurrence
Free.

## 43. Memberships and existing entitlements

Example:

``` text
Members        Free
General public £15
```

Membership is an applicability condition.

Ordinary public discovery remains:

> **£15**

assuming the intended public is the general public.

Likewise:

``` text
Annual pass holder £0
General public     £20
```

does not make the occurrence Free to the ordinary public.

## 44. Products conferring attendance

Consider:

``` text
Single admission  £20
Annual membership £30
Membership includes admission
```

The £30 membership is not automatically another event ticket price.

It is a separate product conferring an entitlement.

Ordinary event discovery remains:

> **£20**

unless attendance genuinely requires acquisition of the broader product.

ThuScene Pricing & Ticketing v1 does not attempt to become a general
membership/subscription model.

## 45. Time-dependent pricing

Example:

``` text
Free before 22:00
£10 after 22:00
```

is represented using temporal applicability.

A possible discovery presentation:

> **Free before 10pm · £10 after**

No separate pricing architecture is required.

## 46. Advance versus door pricing

Example:

``` text
Advance £15
Door    £20
```

Both can be ordinary attendance routes with different applicability
conditions.

If the £15 advance route is currently available:

> **From £15**

may be appropriate.

If advance tickets are no longer available and the £20 door route
remains available:

> **£20**

may be appropriate.

## 47. Family and group pricing

Example:

``` text
Adult          £10 per person
Family package £30
```

The ordinary individual headline remains:

> **£10**

The family package can be presented secondarily.

It must not create an invented effective price such as £7.50.

Where only family admission exists:

``` text
Family package £30
```

a truthful result might be:

> **£30 per family**

rather than simply £30.

## 48. Optional paid upgrades

Example:

``` text
General exhibition    Free
Optional guided tour  £8
```

ordinary exhibition attendance remains:

> **Free**

The optional tour is a separate paid experience/add-on and does not make
the base attendance paid.

## 49. Composite events

A free festival with separately ticketed performances may primarily be
an event-modelling issue rather than a pricing issue.

ThuScene should distinguish separate experiences that deserve separate
event/occurrence modelling from one attendance offer covering several
already-modelled occurrences.

Pricing must not compensate for incorrect event decomposition.

## 50. Unknown

`unknown` is a genuine state.

It must not silently become:

``` text
general
free
paid
available
unavailable
```

For example, if a source says only:

``` text
From £10
```

and ThuScene cannot establish what the £10 price represents, it must not
manufacture certainty.

A conservative presentation may eventually use `See tickets`,
`Price varies`, or appropriately qualified source-reported pricing.

Exact fallback wording is a UI decision.

## 51. Freshness

Pricing and availability can change.

Therefore a live discovery result represents ThuScene's **most recently
established applicable state**, not an immutable event property.

Freshness information such as `last_checked_at` is therefore materially
important.

The threshold at which data becomes too stale for particular claims
remains an implementation decision.

## 52. Derived presentation

Strings such as:

``` text
£20
From £16
Free
Free · Optional donation
Pay What You Choose · From £12
£30 per family
Sold out · Waitlist available
```

are derived presentation.

They are not the authoritative underlying pricing facts.

The underlying semantic information must remain sufficient to regenerate
an appropriate presentation.

## 53. Source-adapter responsibility

Where source data permits, ingestion should conceptually:

``` text
retrieve source offers/prices
        ↓
retain stable source identities
        ↓
retrieve availability
        ↓
relate availability to relevant routes/bands
        ↓
interpret trusted source semantics
        ↓
preserve monetary components and conditions
        ↓
normalise into ThuScene concepts
```

Source-specific interpretation belongs upstream of presentation.

## 54. Presentation responsibility

The presentation layer may choose between appropriate outputs such as:

``` text
£20
From £16
Free
Free · Optional donation
Pay What You Choose · From £12
£30 per family
```

It must not itself determine what a particular Spektrix ticket type,
source-specific band or provider-specific label means.

No EventCard logic such as:

``` ts
name === "Standard"
```

or:

``` ts
provider === "Bristol Old Vic"
```

should determine pricing semantics.

## 55. Derivation precedence

For a discovery result, apply the following sequence.

**P1 --- Establish evidence quality.**\
Distinguish explicit source facts, trusted mappings, editorial
classification, inference and unknowns.

**P2 --- Establish event/occurrence scope and intended public.**\
Determine what is being attended and independently establish the
audience for whom it is intended.

**P3 --- Identify candidate attendance routes and their occurrence
coverage.**

**P4 --- Apply applicability conditions.**\
Determine which routes genuinely apply to the intended public/context
being represented.

**P5 --- Establish attendance action and whether it secures/exercises
attendance or is merely contingent.**

**P6 --- Establish pricing mechanism and amount structure.**

**P7 --- Identify all material monetary components and their charge
basis.**

**P8 --- Establish party coverage.**

**P9 --- Apply current attendance availability at the finest reliable
source-supported level.**

**P10 --- Remove routes/prices that are unavailable or inapplicable to
the discovery context.**

**P11 --- Aggregate equivalent remaining prices only after filtering.**

**P12 --- Derive the discovery presentation, preserving material
qualifiers and preferring a more informative semantic description where
appropriate.**

## 56. Invariants

**I1 --- No lowest-price shortcut.**\
Discovery pricing must never be derived by blindly taking the lowest
numeric source price.

**I2 --- Source identity is not semantics.**\
Source ticket names and IDs identify source objects; they do not alone
establish ThuScene meaning.

**I3 --- Prefer stable source identity.**\
Stable source identifiers should be retained and used for
source-specific mapping where available.

**I4 --- Intended public requires independent evidence.**\
It must not be inferred solely from the price structure being
classified.

**I5 --- Applicability precedes aggregation.**\
Inapplicable routes must not influence the ordinary discovery price.

**I6 --- Availability precedes live-price aggregation.**\
Configured but unavailable routes/prices must not establish the live
discovery minimum where sufficient availability information exists.

**I7 --- Price and availability are independent.**\
A configured price does not prove current availability.

**I8 --- Pricing mechanism and amount structure are independent.**\
Conventional/flexible describes how pricing works; fixed/range/variable
describes its numerical form.

**I9 --- Monetary components retain their semantics.**\
Admission charges, mandatory fees, deposits, minimum spends, credits and
optional contributions must not be collapsed into indistinguishable
prices.

**I10 --- Free attendance requires no mandatory monetary commitment.**\
A zero admission price alone does not establish Free where another
mandatory monetary condition exists.

**I11 --- Free must be positively established.**\
Missing offers or prices must never themselves imply Free.

**I12 --- Optional contributions are compatible with Free attendance.**

**I13 --- Mandatory contributions remain mandatory regardless of their
label.**

**I14 --- Conditional zero-price offers do not make ordinary attendance
Free.**

**I15 --- Charge basis must be respected.**\
Amounts with different bases must not be treated as directly equivalent.

**I16 --- Package totals must not be divided into invented per-person
prices.**

**I17 --- Party coverage and occurrence coverage are independent.**

**I18 --- One attendance offer may cover multiple occurrences.**\
It must not be duplicated into independent offers merely to fit an
occurrence-centric implementation.

**I19 --- Applicability is broader than demographic eligibility.**\
Time, channel, membership, party composition and other conditions may
determine whether a route applies.

**I20 --- Attendance action and attendance availability are
independent.**

**I21 --- Contingent actions do not guarantee attendance.**\
Applying to a ballot or joining a waitlist must not be treated as
obtaining admission.

**I22 --- Availability applies to the relevant attendance route or
entitlement.**\
The availability of some other route or action must not be substituted
for it.

**I23 --- Entitlement products are not automatically event ticket
offers.**

**I24 --- Unknown remains unknown.**\
Incomplete semantics must not be converted into confident discovery
claims.

**I25 --- Presentation is derived.**\
Display strings are not authoritative pricing facts.

**I26 --- Richer semantic presentation may take precedence over a
technically true simpler label.**\
For example, `Pay What You Can · £0+` may be more appropriate than
simply `Free`.

**I27 --- Source-specific semantic interpretation belongs upstream of UI
presentation.**

## 57. Canonical adversarial examples

  -------------------------------------------------------------------------
  Source facts             Derived interpretation  Discovery result
  ------------------------ ----------------------- ------------------------
  General £20; restricted  concession inapplicable **£20**
  concession £15           to ordinary general     
                           route                   

  General £20; companion   companion conditional   **£20**
  £0                                               

  Adult £20; under-4 £0    child price conditional **£20** for general
                                                   adult discovery

  Several genuine general  all applicable and      **From £15**
  prices £15/£20/£25       available               

  £12 band unavailable;    unavailable £12         **From £16**
  £16/£19 available        filtered first          

  BOV PWYChoose; Open      flexible mechanism      **Pay What You Choose ·
  Concession £12 genuinely                         From £12**
  open to all                                      

  Free drop-in             no mandatory monetary   **Free**
                           commitment; turn up     

  Free, registration       free + securing action  **Free · Registration
  required                                         required**

  Free + optional donation optional contribution   **Free · Optional
                                                   donation**

  Free + suggested £5      optional contribution   **Free · £5 suggested
  donation                                         donation**

  Minimum £5 "donation"    mandatory monetary      **Not Free**
  mandatory                component               

  £0 admission + £10       mandatory deposit       **£0 admission · £10
  refundable deposit                               refundable deposit**
                                                   conceptually

  £0 admission + £20       mandatory spend         **£0 admission · £20
  minimum spend                                    minimum spend**
                                                   conceptually

  Ticket £20 + mandatory   admission + mandatory   **£20 + mandatory fee**
  £2 fee                   ancillary fee           unless safe total
                                                   derivable

  Adult £10; family        distinct charge/party   **£10**, family price
  package £30              basis                   secondary

  Family-only £30          package route           **£30 per family**

  Group 10+ £15/person     party-size              conditional £15/person
                           applicability +         
                           per-person charge       

  Members free; public £15 membership              **£15** ordinary public
                           applicability           

  Public £20; annual       membership separate     **£20**
  membership £30 includes  entitlement product     
  entry                                            

  Advance £15; door £20,   temporal/channel        **From £15**
  both available           applicability           

  Advance £15 unavailable; availability filtering  **£20**
  door £20 available                               

  Free before 22:00; £10   temporal applicability  **Free before 10pm · £10
  after                                            after**

  Free ballot              contingent application  **Free · Ballot open**
                           action                  

  Sold out; waitlist open  no attendance           **Sold out · Waitlist
                           availability;           available**
                           contingent action       
                           available               

  Friday/Saturday/Sunday   pass covers multiple    **£30 day / £60 weekend
  £30; weekend pass £60    occurrences             pass**,
                                                   context-dependent

  Six-session course £120  one offer covers six    **£120 for course**
                           occurrences             

  PWYC £0--£20             flexible mechanism; no  **Pay What You Can ·
                           mandatory minimum       £0+**

  Free exhibition;         tour separate optional  **Free**
  optional tour £8         experience              

  Paid £5 on door, no      mandatory admission     **£5**
  advance ticket           charge; turn up/pay     

  Source only says "From   insufficient evidence   **Unknown/conservative
  £10" with no semantics                           presentation**
  -------------------------------------------------------------------------

## 58. Deliberate exclusions and deferred implementation decisions

This specification deliberately does not decide:

-   PostgreSQL table structure;
-   exact column names;
-   exact enum vocabularies;
-   whether `attendance_routes` becomes a physical table;
-   whether `attendance_offers` becomes a physical table;
-   whether `ticket_offers` is renamed or retained;
-   how multi-occurrence offer relationships are implemented;
-   how monetary components are persisted;
-   how detailed party composition is normalised;
-   exact applicability-condition storage;
-   exact source-confidence representation;
-   exact freshness thresholds;
-   exact card/detail-page wording;
-   whether derived discovery price is stored, cached or computed;
-   whether every source price-band row is permanently persisted.

These are database/application-design questions to be considered **after
this conceptual specification is frozen**.

## 59. Relationship to the Frozen Database Specification v1

This frozen conceptual specification does **not** alter the existing
Frozen Database Specification v1.

It does, however, establish conceptual requirements against which that
database must subsequently be tested.

Potential areas of mismatch already visible include:

-   stable source ticket-type identity;
-   source price-band identity/availability;
-   monetary components other than ticket price;
-   charge basis;
-   party coverage;
-   occurrence coverage;
-   multi-occurrence offers;
-   attendance actions;
-   applicability conditions;
-   positive free-attendance representation;
-   optional contributions;
-   attendance-route-specific availability.

Those are **audit targets**, not yet proposed schema changes.

Migration `007` must not be designed until that comparison has been
completed.

## 60. Frozen v1 summary

The model can be summarised as:

> **ThuScene determines which attendance routes genuinely apply to the
> intended public, what actions those routes require, what monetary
> commitments they impose, who and what occurrences they cover, and
> whether they are currently obtainable. It then derives a truthful
> discovery presentation from those facts.**

That replaces the unsafe question:

> What's the cheapest ticket?

with the stronger question:

> **What does an ordinary member of the intended public actually need to
> pay and do to attend?**

------------------------------------------------------------------------

## Verification status

Before freezing, the model was verified in the sequence:

**definitions → rules → invariants → precedence → canonical examples**

The verification found:

-   definitions internally distinct;
-   rules using definitions consistently;
-   substantive rules represented by invariants;
-   invariants mutually compatible;
-   precedence satisfying the invariants;
-   canonical examples following the stated precedence;
-   no remaining duplicate major concepts;
-   no material undefined concepts;
-   no unresolved conceptual contradiction;
-   no further conceptual redesign indicated.

**Final verification result: PASS.**

------------------------------------------------------------------------

**END --- ThuScene Pricing & Ticketing Model v1.0 --- FROZEN**
