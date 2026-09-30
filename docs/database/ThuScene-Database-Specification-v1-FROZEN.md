# ThuScene Database Specification v1

**Status:** Frozen — authoritative Database Specification v1  
**Database:** ThuScene Supabase / PostgreSQL  
**Live-state interrogation date:** 19 September 2026  
**Baseline:** live database after `005_taxonomy_v1` and `006_security_harden_database_functions`

> This document describes the database that actually exists in PostgreSQL at the date above. It is a post-migration state specification, not executable migration SQL. Where an editorial/application rule is not enforced by PostgreSQL, that distinction is stated explicitly.

## 1. Status, source of truth and migration baseline

The primary source of truth for this document is direct read-only interrogation of the live ThuScene PostgreSQL catalogue and data. The frozen Taxonomy v1 design explains intent; this document records the resulting implemented database state.

Applied Supabase migrations relevant to this state:

| Version | Migration |
|---|---|
| `20260919161304` | `005_taxonomy_v1` |
| `20260919163108` | `006_security_harden_database_functions` |

There are 16 ThuScene application tables in `public`. RLS is enabled on all 16. It is not forced for table owners.

## 2. Conceptual model and relationship diagram

The core separation is:

- `events` — **what is happening**
- `event_occurrences` — **when and where a particular attendance opportunity happens**
- `ticket_offers` — **how that occurrence can be attended/booked and its price/availability**
- `venues` — physical places
- `organisers` / `artists` — entities associated many-to-many with events
- `categories` — broad discovery routes; events may have many, with at most one primary
- `event_forms` — structural form; an event has zero or one
- `tags` — controlled descriptors; events may have many
- `sources` / `event_sources` — provenance and verification
- `taxonomy_aliases` — private source/global vocabulary mappings into canonical taxonomy

```text
                                   event_forms
                                       ^
                                       | 0..1
                                       |
artists <--- event_artists ---> events <--- event_categories ---> categories
                                  |
organisers <- event_organisers --+--- event_tags -------------> tags
                                  |
sources <---- event_sources ------+
                                  |
                                  +--- event_occurrences ---> venues
                                           |
                                           +---> ticket_offers

sources ---- optional scope ----> taxonomy_aliases
                                      |
                                      +--> exactly one of:
                                           categories
                                           event_forms
                                           tags
```

Deletion follows ownership/reference semantics: event-owned junction/occurrence data generally cascades when an event is deleted; reusable canonical entities generally cannot be deleted while referenced.

## 3. The 16 tables

Notation: **NN** = NOT NULL; **NULL** = nullable. `uuid` IDs default to `gen_random_uuid()` unless stated otherwise. All 16 tables have `created_at timestamptz NN DEFAULT now()` and `updated_at timestamptz NN DEFAULT now()` unless explicitly noted. All 16 have an enabled `BEFORE UPDATE` trigger invoking `public.set_updated_at()`.

### 3.1 `events`

Purpose: canonical event identity and event-level descriptive/editorial state.

| Column | Type | Null/default |
|---|---|---|
| id | uuid | NN, `gen_random_uuid()` |
| title | text | NN |
| slug | text | NN |
| short_description | text | NULL |
| description | text | NULL |
| status | text | NN, `'draft'` |
| image_url | text | NULL |
| age_restriction | text | NULL |
| accessibility_info | text | NULL |
| created_at | timestamptz | NN, `now()` |
| updated_at | timestamptz | NN, `now()` |
| event_form_id | uuid | NULL |
| category_review_status | text | NN, `'unreviewed'` |
| category_last_reviewed_at | timestamptz | NULL |
| event_form_review_status | text | NN, `'unreviewed'` |
| event_form_last_reviewed_at | timestamptz | NULL |
| tags_review_status | text | NN, `'unreviewed'` |
| tags_last_reviewed_at | timestamptz | NULL |

Constraints: PK `id`; UNIQUE `slug`; status ∈ `draft,published,cancelled,postponed,archived`; each taxonomy review status ∈ `unreviewed,reviewed,needs_review`; `event_form_id → event_forms(id) ON DELETE RESTRICT`.

Indexes: PK/slug unique indexes; `events_event_form_id_idx`.

### 3.2 `event_occurrences`

Purpose: concrete attendable instances of an event.

| Column | Type | Null/default |
|---|---|---|
| id | uuid | NN, generated |
| event_id | uuid | NN |
| venue_id | uuid | NULL |
| start_at | timestamptz | NN |
| end_at | timestamptz | NULL |
| is_all_day | boolean | NN, `false` |
| status | text | NN, `'scheduled'` |
| occurrence_label | text | NULL |
| notes | text | NULL |
| created_at / updated_at | timestamptz | NN, `now()` |
| source_reference | text | NULL |
| available_quantity | integer | NULL |
| capacity | integer | NULL |

Constraints: PK; `event_id → events ON DELETE CASCADE`; `venue_id → venues ON DELETE SET NULL`; `end_at IS NULL OR end_at >= start_at`; status ∈ `scheduled,cancelled,postponed,rescheduled,completed`.

Indexes: event, venue, start time and source reference. **There are currently no non-negative/capacity relationship CHECKs on occurrence-level `available_quantity`/`capacity`.**

### 3.3 `venues`

Purpose: reusable physical places.

Columns: `id uuid NN`; `name text NN`; `slug text NN`; `description text NULL`; `venue_type text NULL`; `address_line_1 text NULL`; `address_line_2 text NULL`; `town_city text NULL`; `postcode text NULL`; `latitude numeric NULL`; `longitude numeric NULL`; `website_url text NULL`; `image_url text NULL`; `accessibility_notes text NULL`; `status text NN DEFAULT 'active'`; timestamps.

Constraints: PK; UNIQUE slug; latitude −90..90 when present; longitude −180..180 when present; status ∈ `active,inactive`.

### 3.4 `organisers`

Purpose: reusable organising/presenting entities.

Columns: `id uuid NN`; `name text NN`; `slug text NN`; `description text NULL`; `website_url text NULL`; `email text NULL`; `phone text NULL`; `image_url text NULL`; `status text NN DEFAULT 'active'`; timestamps.

Constraints: PK; UNIQUE slug; status ∈ `active,inactive`.

### 3.5 `event_organisers`

Purpose: many-to-many event/organiser relationship.

Columns: `id uuid NN`; `event_id uuid NN`; `organiser_id uuid NN`; `role text NULL`; `is_primary boolean NN DEFAULT false`; `display_order integer NN DEFAULT 0`; timestamps.

Constraints: PK; UNIQUE `(event_id, organiser_id)`; display_order ≥ 0; event FK CASCADE; organiser FK RESTRICT.

Indexes: organiser lookup; partial UNIQUE `(event_id) WHERE is_primary=true`, enforcing at most one primary organiser per event.

### 3.6 `artists`

Purpose: performers/participants broadly construed.

Columns: `id uuid NN`; `name text NN`; `slug text NN`; `artist_type text NULL`; `description text NULL`; `image_url text NULL`; `website_url text NULL`; `social_links jsonb NULL`; `status text NN DEFAULT 'active'`; timestamps.

Constraints: PK; UNIQUE slug; status ∈ `active,inactive`.

### 3.7 `event_artists`

Purpose: many-to-many event/artist relationship.

Columns: `id uuid NN`; `event_id uuid NN`; `artist_id uuid NN`; `role text NULL`; `is_primary boolean NN DEFAULT false`; `display_order integer NN DEFAULT 0`; timestamps.

Constraints: PK; UNIQUE `(event_id, artist_id)`; display_order ≥ 0; event FK CASCADE; artist FK RESTRICT.

Indexes: artist lookup; partial UNIQUE `(event_id) WHERE is_primary=true`, enforcing at most one primary artist.

### 3.8 `categories`

Purpose: controlled Discovery Category vocabulary.

Columns: `id uuid NN`; `name text NN`; `slug text NN`; `description text NULL`; `display_order integer NN DEFAULT 0`; `status text NN DEFAULT 'active'`; timestamps.

Constraints: PK; UNIQUE name; UNIQUE slug; display_order ≥ 0; status ∈ `active,inactive`.

### 3.9 `event_categories`

Purpose: many-to-many category assignment with optional primary category.

Columns: `id uuid NN`; `event_id uuid NN`; `category_id uuid NN`; `is_primary boolean NN DEFAULT false`; `display_order integer NN DEFAULT 0`; timestamps.

Constraints: PK; UNIQUE `(event_id, category_id)`; display_order ≥ 0; event FK CASCADE; category FK RESTRICT.

Indexes: category lookup; partial UNIQUE `(event_id) WHERE is_primary=true`, enforcing **at most one** primary Category. PostgreSQL does not require an event to have any category or any primary category.

### 3.10 `sources`

Purpose: private provenance/source registry.

Columns: `id uuid NN`; `name text NN`; `slug text NN`; `source_type text NN`; `website_url text NULL`; `description text NULL`; `status text NN DEFAULT 'active'`; timestamps.

Constraints: PK; UNIQUE slug; status ∈ `active,inactive`.

### 3.11 `event_sources`

Purpose: event provenance, checking and verification per source.

Columns: `id uuid NN`; `event_id uuid NN`; `source_id uuid NN`; `source_url text NULL`; `first_seen_at timestamptz NN DEFAULT now()`; `last_checked_at timestamptz NULL`; `last_changed_at timestamptz NULL`; `verification_status text NN DEFAULT 'unverified'`; `notes text NULL`; timestamps.

Constraints: PK; UNIQUE `(event_id, source_id)`; event FK CASCADE; source FK RESTRICT; verification status ∈ `unverified,verified,needs_review`.

Index: source lookup.

### 3.12 `ticket_offers`

Purpose: occurrence-level price, booking and availability options.

| Column | Type | Null/default |
|---|---|---|
| id | uuid | NN, generated |
| event_occurrence_id | uuid | NN |
| name | text | NN |
| description | text | NULL |
| ticket_url | text | NULL |
| minimum_price | numeric(10,2) | NULL |
| maximum_price | numeric(10,2) | NULL |
| currency | text | NN, `'GBP'` |
| price_type | text | NN, `'unknown'` |
| availability_status | text | NN, `'unknown'` |
| booking_required | boolean | NN, `true` |
| provider_name | text | NULL |
| last_checked_at | timestamptz | NULL |
| created_at / updated_at | timestamptz | NN, `now()` |
| available_quantity | integer | NULL |
| capacity | integer | NULL |
| source_reference | text | NULL |

Constraints: occurrence FK CASCADE; prices non-negative when present; maximum ≥ minimum when both present; available_quantity/capacity non-negative when present; available ≤ capacity when both present. `price_type` ∈ `free,fixed,from,to,range,variable,pay_what_you_can,unknown`. `availability_status` ∈ `available,limited,sold_out,closed,cancelled,unknown`.

Indexes: occurrence and source reference.

### 3.13 `event_forms`

Purpose: canonical 0..1 structural form vocabulary.

Columns: `id uuid NN`; `name text NN`; `slug text NN`; `description text NULL`; `display_order integer NN` (no default); `status text NN DEFAULT 'active'`; timestamps.

Constraints: PK; UNIQUE name; UNIQUE slug; display_order > 0; status ∈ `active,inactive`.

### 3.14 `tags`

Purpose: canonical controlled-tag vocabulary.

Columns: `id uuid NN`; `name text NN`; `slug text NN`; `description text NULL`; `status text NN DEFAULT 'active'`; timestamps.

Constraints: PK; UNIQUE name; UNIQUE slug; status ∈ `active,inactive`.

No Tags are seeded in v1.

### 3.15 `event_tags`

Purpose: many-to-many event/tag assignment.

Columns: `id uuid NN`; `event_id uuid NN`; `tag_id uuid NN`; timestamps.

Constraints: PK; UNIQUE `(event_id, tag_id)`; event FK CASCADE; tag FK RESTRICT.

Index: tag lookup. There is deliberately no primary flag or display order.

### 3.16 `taxonomy_aliases`

Purpose: private mapping of global/source vocabulary to canonical Category, Event Form or Tag.

Columns: `id uuid NN`; `alias_text text NN`; `alias_key text NN`; `source_id uuid NULL`; `source_field text NULL`; `category_id uuid NULL`; `event_form_id uuid NULL`; `tag_id uuid NULL`; `status text NN DEFAULT 'active'`; timestamps.

Constraints:
- PK.
- exactly one target: `num_nonnulls(category_id,event_form_id,tag_id)=1`;
- `source_field` may be non-NULL only when `source_id` is non-NULL;
- source/category/form/tag FKs all RESTRICT;
- status ∈ `active,inactive`.

Indexes: each FK target plus the important partial unique index:

```sql
UNIQUE (source_id, source_field, alias_key)
NULLS NOT DISTINCT
WHERE status = 'active'
```

Thus at most one active alias exists for a given scope/key, with NULL scope values treated as equal. Inactive historical aliases may coexist.

## 4. Relationship and deletion summary

| Child/reference | Parent | Delete behaviour |
|---|---|---|
| event_occurrences.event_id | events | CASCADE |
| event_occurrences.venue_id | venues | SET NULL |
| ticket_offers.event_occurrence_id | event_occurrences | CASCADE |
| event_organisers.event_id | events | CASCADE |
| event_organisers.organiser_id | organisers | RESTRICT |
| event_artists.event_id | events | CASCADE |
| event_artists.artist_id | artists | RESTRICT |
| event_categories.event_id | events | CASCADE |
| event_categories.category_id | categories | RESTRICT |
| event_sources.event_id | events | CASCADE |
| event_sources.source_id | sources | RESTRICT |
| events.event_form_id | event_forms | RESTRICT |
| event_tags.event_id | events | CASCADE |
| event_tags.tag_id | tags | RESTRICT |
| taxonomy_aliases.source_id | sources | RESTRICT |
| taxonomy_aliases.category_id | categories | RESTRICT |
| taxonomy_aliases.event_form_id | event_forms | RESTRICT |
| taxonomy_aliases.tag_id | tags | RESTRICT |

## 5. Indexes and cardinality enforcement

Beyond PK/UNIQUE backing indexes, live PostgreSQL contains:

- `events_event_form_id_idx`
- occurrences: `event_id`, `venue_id`, `start_at`, `source_reference`
- organisers junction: `organiser_id` plus partial one-primary index
- artists junction: `artist_id` plus partial one-primary index
- categories junction: `category_id` plus partial one-primary index
- sources junction: `source_id`
- ticket offers: `event_occurrence_id`, `source_reference`
- event tags: `tag_id`
- taxonomy aliases: source/category/form/tag lookup indexes plus active scope/key unique index.

Database-enforced cardinalities of particular importance:

- Event → Event Form: 0..1 (nullable FK on `events`).
- Event → Categories: 0..many; duplicate pair prohibited; at most one primary.
- Event → Tags: 0..many; duplicate pair prohibited.
- Event → Artists/Organisers: 0..many; duplicate pair prohibited; at most one primary of each.
- Alias → canonical taxonomy target: exactly one of Category/Form/Tag.

## 6. Canonical Categories

The live table contains seven active Discovery Categories and the preserved inactive former Festivals category.

| Order | Name | Slug | Status | UUID |
|---:|---|---|---|---|
| 1 | Live Music | live-music | active | `99bb4ffa-c05a-48a2-832d-0221875d03a4` |
| 2 | Comedy | comedy | active | `80d37d9e-23b2-4601-abf3-04daa2859fc6` |
| 3 | Theatre & Shows | theatre-shows | active | `d0e0deba-e7d3-43a0-813a-8768cd4048e2` |
| 4 | Food & Drink | food-drink | active | `9287ebc7-991b-4e7c-8c99-0c8b3f74d5fa` |
| 5 | Arts & Culture | arts-culture | active | `1663399e-e90d-499e-9f97-aa8a14f11785` |
| 6 | Sport | sport | active | `4e6bb5af-f86b-4947-b582-a2fc79f18ac7` |
| 7 | Family | family | active | `6e90c928-69f9-487a-99ae-5f45ecef3878` |
| 8 | Festivals | festivals | inactive | `867030fb-8589-48ba-a576-c9bb45f4d640` |

The UUIDs were preserved during Taxonomy v1 migration. Existing relationships to an inactive canonical value remain valid and readable.

## 7. Canonical Event Forms

All 24 are active.

| # | Event Form | Slug | UUID |
|---:|---|---|---|
| 1 | Performance | performance | `e401e89f-a13e-47be-9e92-56194d266638` |
| 2 | Concert | concert | `2f3faab9-9486-411f-a77b-06f0a4f1022b` |
| 3 | Exhibition | exhibition | `9e1874d6-dcea-4cb9-9d6f-53728a2d567a` |
| 4 | Film Screening | film-screening | `a5eaa5c9-a1c8-4326-ac2f-999bbcfa8d4c` |
| 5 | Workshop | workshop | `07d9d543-407e-4e38-af57-4ada3addb7e2` |
| 6 | Class | class | `20850bde-ed6d-46bc-9de2-ca5038a0d531` |
| 7 | Course | course | `e5bc5677-e8c8-4723-bef3-755bb409b928` |
| 8 | Guided Tour | guided-tour | `4922537f-a302-4c5f-9b1d-6cf7a11abdb0` |
| 9 | Demonstration | demonstration | `73118228-52d6-420f-b8ea-bd96088de76b` |
| 10 | Talk | talk | `83f30911-7d80-468c-a80d-dbcc14f49035` |
| 11 | Festival | festival | `28a0335d-c4b7-4b9a-ae06-f82417c1d637` |
| 12 | Market | market | `214496d8-9133-440f-87b1-e0db0d8979b9` |
| 13 | Fair | fair | `71b7a1ca-f390-4544-b5e5-9ff797854c09` |
| 14 | Open Day | open-day | `80404379-51c8-4d72-81cd-1c7fe19906f1` |
| 15 | Retreat | retreat | `9d48c5fd-91c1-482b-a69a-06c5474b988a` |
| 16 | Meetup | meetup | `f0f8794d-f763-40dc-b7a7-08877a1cdb22` |
| 17 | Conference | conference | `0a0817c7-850d-46c8-a723-7eec67cc3628` |
| 18 | Quiz | quiz | `65b41dfb-658e-4a64-bd3c-8de009a679b4` |
| 19 | Tasting | tasting | `1e65d04b-6dee-405b-b2b2-669fd2231e29` |
| 20 | Parade | parade | `decd8f40-6c99-4075-818f-97e2f16ff254` |
| 21 | Race | race | `3516c546-a8a2-4729-b04e-91872651c2ac` |
| 22 | Club Night | club-night | `59cb519d-3c93-49b6-a4e6-6906f34226fe` |
| 23 | Competition | competition | `c1562f06-65e6-4841-afff-181270a32e25` |
| 24 | Match | match | `abeea711-9311-4d49-8a16-f3acb16a6387` |

Canonical live descriptions:

1. **Performance** — A live audience watches a theatrical, comedic, choreographic, circus, puppetry, performance-art or comparable performed work.
2. **Concert** — Musicians perform music live for an audience; gigs, recitals and live sets may map to this form.
3. **Exhibition** — A curated display in which visitors explore works, objects or other presented material.
4. **Film Screening** — A scheduled presentation of film or other moving-image work to an audience.
5. **Workshop** — A focused practical or creative session in which participants actively make, practise, explore or develop something.
6. **Class** — An instructor-led session for learning or practising in a recognisable class format.
7. **Course** — Multiple linked sessions that collectively form a programme of learning or development.
8. **Guided Tour** — A led experience through a place, route, site, collection or environment with interpretation.
9. **Demonstration** — An event centred on watching a practitioner show a process or technique.
10. **Talk** — A speaker or speakers present ideas, knowledge, stories or discussion to an audience, including lectures, conversations and panels.
11. **Festival** — An overarching programme containing multiple activities or events under a shared identity.
12. **Market** — An event centred on browsing or purchasing from multiple vendors or traders.
13. **Fair** — A multi-exhibitor showcase where exhibition, discovery or engagement is at least as fundamental as retail.
14. **Open Day** — An organisation or site invites people to explore it through a specially open or programmed experience rather than ordinary opening hours.
15. **Retreat** — An extended immersive experience centred on sustained activity, practice or reflection; overnight participation is not required.
16. **Meetup** — A gathering centred on people interacting around a shared interest, activity, identity or purpose.
17. **Conference** — A professional, academic, industry or specialist gathering containing multiple programmed sessions.
18. **Quiz** — An organised event structured around questions and scoring.
19. **Tasting** — An event centred on sampling, comparing or evaluating food or drink.
20. **Parade** — An organised public procession.
21. **Race** — A competitive event on a defined course, route or distance where outcome is principally determined by time or finishing order.
22. **Club Night** — A nightlife event centred on DJs or recorded music and dancing rather than an audience watching a live concert.
23. **Competition** — A competitive event under rules or judging that is neither more specifically a Match nor a Race.
24. **Match** — A single defined sporting contest between two opposing individuals or teams.

## 8. Taxonomy and review-state rules

Implemented taxonomy layers:

- Discovery Category: 0..many through `event_categories`.
- Primary Category: 0..1 and, structurally, must be one of the event's assigned Category rows because `is_primary` is on that relationship.
- Event Form: 0..1 through nullable `events.event_form_id`.
- Controlled Tags: 0..many through `event_tags`.

NULL/no assignment is structurally valid. PostgreSQL does not require an event to have a Category, primary Category, Event Form or Tag.

Each event has independent review state for Categories, Event Form and Tags. Allowed states are `unreviewed`, `reviewed`, `needs_review`; default is `unreviewed`. Each layer has a nullable `*_last_reviewed_at`.

**Application/editorial semantics:** the timestamp means the most recent deliberate review of that layer. `reviewed` may legitimately coexist with zero Categories, NULL Event Form or zero Tags. There is deliberately no CHECK coupling review status to timestamps or assignment count, and no trigger automatically changes review state when taxonomy assignments change.

Canonical taxonomy rows can be `active` or `inactive`. **Database fact:** the public RLS policies for `categories`, `event_forms` and `tags` do not filter on status, so inactive canonical rows remain readable. **Application/editorial rule:** normal discovery/classification interfaces are expected to use active values for new work unless explicitly operating historically/admin-side.

`taxonomy_aliases.alias_key` normalization is application/importer responsibility; no normalization algorithm is enforced in PostgreSQL.

## 9. RLS and public/private model

RLS is enabled on all 16 tables.

### Publicly readable tables

`anon` and `authenticated` have table-level **SELECT only** on 13 tables:

`events`, `event_occurrences`, `venues`, `organisers`, `event_organisers`, `artists`, `event_artists`, `categories`, `event_categories`, `ticket_offers`, `event_forms`, `tags`, `event_tags`.

Policies:

- `events`: published events only.
- `event_occurrences`: only occurrences belonging to published events.
- `ticket_offers`: only offers whose occurrence belongs to a published event.
- `venues`: active only.
- `organisers`: active only.
- `artists`: active only.
- `event_organisers`: published event **and** active organiser.
- `event_artists`: published event **and** active artist.
- `categories`: all canonical rows (`true`), including inactive.
- `event_categories`: published event; Category active status is not a condition.
- `event_forms`: all canonical rows (`true`), including inactive.
- `tags`: all canonical rows (`true`), including inactive.
- `event_tags`: published event; Tag active status is not a condition.

### Private tables

`sources`, `event_sources`, `taxonomy_aliases` have RLS enabled, no public policies, and no `anon`/`authenticated` table privileges. Supabase therefore reports “RLS enabled, no policy” informational findings for these three tables; this is intentional.

## 10. Role privileges

`anon` and `authenticated`: SELECT only on the 13 public-facing tables; no table privileges on the three private tables.

`service_role` intentionally reflects historical/importer needs rather than a blanket normalized grant:

- Full table privileges including CRUD are present on `categories`, `event_categories`, `event_occurrences`, `event_sources`, `events`, `sources`, `ticket_offers`, `venues`, plus the four Taxonomy-v1 tables `event_forms`, `tags`, `event_tags`, `taxonomy_aliases`.
- `artists`, `event_artists`, `organisers`, `event_organisers` currently have only `REFERENCES`, `TRIGGER`, `TRUNCATE` granted to `service_role`, not CRUD/SELECT.

The latter is a deliberate preserved live state, not a statement that it is necessarily the final importer permission model.

## 11. Functions, triggers and security hardening

### `public.set_updated_at()`

Trigger function, owner `postgres`, SECURITY INVOKER. It sets `NEW.updated_at = now()` and returns `NEW`.

After migration 006 its function configuration is:

`search_path=pg_catalog`

Direct EXECUTE is not available to PUBLIC, anon, authenticated or service_role; `postgres` retains execution. All 16 table update triggers remain enabled.

### `public.rls_auto_enable()`

Event-trigger function, owner `postgres`, SECURITY DEFINER, with `search_path=pg_catalog`. It examines DDL commands and enables RLS on newly created tables/partitioned tables in `public`.

Direct EXECUTE is not available to PUBLIC, anon, authenticated or service_role; `postgres` retains execution.

### `ensure_rls`

Enabled PostgreSQL event trigger:
- event: `ddl_command_end`
- function: `rls_auto_enable()`
- tags: `CREATE TABLE`, `CREATE TABLE AS`, `SELECT INTO`.

This is a safety net, not a substitute for deliberately defining correct policies/privileges.

## 12. Database-enforced vs application/editorial rules

### Enforced by PostgreSQL

Examples include:
- PKs and UUID defaults;
- required/null columns;
- unique slugs/names where specified;
- FK existence and delete actions;
- one Event Form maximum;
- no duplicate event/category, event/tag, event/artist, event/organiser or event/source pairs;
- at most one primary Category, Artist and Organiser;
- Event Form/Category/Tag status domains;
- event/occurrence/ticket status domains;
- price/quantity checks on ticket offers;
- exactly one taxonomy-alias target;
- source_field requires source_id;
- active alias uniqueness within NULL-aware source scope;
- RLS and current grants.

### Application/editorial responsibility

Examples include:
- whether an event belongs in ThuScene at all;
- selecting appropriate active Categories/Form/Tags;
- whether a Category is a meaningful discovery route;
- whether one assigned Category should be primary;
- Event Form semantic precedence, including Match/Race/Competition;
- controlled Tag vocabulary governance;
- alias-key normalization;
- setting review statuses/timestamps correctly;
- not automatically reclassifying legacy Festival relationships;
- interpreting source vocabulary as evidence rather than authority;
- deciding what the UI displays when canonical taxonomy is inactive;
- deriving confidence/verification presentation from evidence;
- ensuring an event is not presented as attendable when all relevant ticket offers are sold out.

## 13. Current test-data state

Direct SQL counts at interrogation time:

| Table | Rows |
|---|---:|
| events | 1 |
| event_occurrences | 4 |
| venues | 1 |
| categories | 8 |
| event_categories | 1 |
| sources | 1 |
| event_sources | 1 |
| ticket_offers | 28 |
| event_forms | 24 |
| tags | 0 |
| event_tags | 0 |
| taxonomy_aliases | 0 |
| artists | 0 |
| event_artists | 0 |
| organisers | 0 |
| event_organisers | 0 |

**Verified live state:** the one existing event has `event_form_id = NULL`; all three taxonomy review statuses are `unreviewed`; and all three review timestamps are NULL. **Migration/design history:** migration 005 was intentionally written not to auto-classify that event, and existing event/category relationships were preserved.

These are **test/current-state counts, not schema invariants**.

## 14. Known deliberate limitations and design decisions

1. **Concrete occurrences, no RRULE recurrence model.** Repeating/multi-day events are represented by concrete occurrence rows.
2. **Tickets belong to occurrences, not events.** Availability and price can differ by performance/date.
3. **Free drop-in attendance is representable** without forcing an external ticket URL.
4. **Event Form is nullable and singular.** A misleading Form is worse than NULL.
5. **Categories and Tags are many-to-many.** Category additionally supports at most one primary.
6. **Inactive taxonomy is retained/readable.** `active` controls current assignment/discovery intent, not historical existence.
7. **No database trigger restricts new assignments to active taxonomy.** That is intentionally an application/importer rule in v1.
8. **No automatic taxonomy-review triggers.** Workflow owns review state.
9. **No numeric taxonomy/AI confidence score.**
10. **No separate Genre/Style or Experience Characteristic layer.** Those concepts belong in controlled Tags where useful.
11. **Tags start empty.** Examples from the taxonomy specification were not automatically promoted to canonical records.
12. **Aliases start empty.** Source mappings are to be added deliberately.
13. **Occurrence quantity fields are less constrained than ticket quantity fields.** `event_occurrences.available_quantity/capacity` currently have no non-negative or available≤capacity CHECKs.
14. **`start_at` is mandatory.** The present occurrence model does not cleanly express “date known, time unknown” without choosing a timestamp representation.
15. **Event lifecycle and publication share `events.status`.** This is the current model and may warrant future review if editorial workflow becomes more complex.
16. **Public DB readability is not UI visibility.** Inactive canonical taxonomy can be read while normal discovery UI still filters to active values.
17. **Service-role permissions are intentionally non-uniform.** Existing importer-oriented grants were preserved rather than broadly normalized.
18. **Current index-usage statistics are not meaningful evidence for removal.** The database is tiny and newly migrated.

## 15. Schema-change governance

From this baseline onward:

1. Treat this specification plus the live PostgreSQL catalogue as the reference state.
2. Make schema changes through numbered, source-controlled migrations; do not edit an already-applied migration to change live history.
3. Before a write migration, perform read-only pre-flight checks against the live database and capture any data/relationships that must be preserved.
4. Prefer transactional migrations with explicit assertions and rollback on failed validation.
5. After applying a migration, independently re-query the live catalogue/data rather than assuming the migration produced the intended result.
6. Re-run relevant Supabase security/performance advisors after security/schema changes.
7. Preserve canonical UUIDs when evolving controlled vocabularies unless a deliberate migration explicitly requires otherwise.
8. Retire referenced canonical values by status rather than deleting them.
9. Do not perform speculative editorial reclassification as a side effect of structural migrations.
10. Clearly distinguish database invariants from application/editorial policy in both migrations and documentation.
11. Update this specification whenever the implemented schema changes materially; retain historical versions/checkpoints rather than silently rewriting history.
12. A specification should be marked **Frozen** only after comparison against the live post-migration database and explicit review.

---

## Appendix A — Trigger inventory

Each table has one enabled `BEFORE UPDATE ... FOR EACH ROW EXECUTE FUNCTION set_updated_at()` trigger:

`artists_set_updated_at`, `categories_set_updated_at`, `event_artists_set_updated_at`, `event_categories_set_updated_at`, `set_event_forms_updated_at`, `event_occurrences_set_updated_at`, `event_organisers_set_updated_at`, `event_sources_set_updated_at`, `set_event_tags_updated_at`, `events_set_updated_at`, `organisers_set_updated_at`, `sources_set_updated_at`, `set_tags_updated_at`, `set_taxonomy_aliases_updated_at`, `ticket_offers_set_updated_at`, `venues_set_updated_at`.

## Appendix B — Verification status

A second, line-by-line read-only verification pass was completed against the live PostgreSQL catalogue on 19 September 2026.

The pass rechecked:

- every column, type, nullability and default across all 16 tables;
- the complete constraint-name inventory for every table;
- the complete index-name inventory for every table;
- all 16 non-internal `updated_at` triggers and their enabled state;
- FK deletion behaviour;
- RLS enablement and policy predicates;
- `anon`, `authenticated` and `service_role` grants;
- function security mode, search path and effective direct EXECUTE privileges;
- `ensure_rls`;
- canonical Category and Event Form data;
- current direct SQL row counts; and
- the taxonomy state of the existing test event.

No structural discrepancy requiring a database change was found. Two passages were tightened to distinguish verified live database facts from application/editorial or migration-history statements.

Following successful line-by-line verification against the live PostgreSQL database, this document was explicitly approved as **Frozen**.

**Frozen baseline:** live ThuScene PostgreSQL state after migrations `005_taxonomy_v1` and `006_security_harden_database_functions`.

“Frozen” means this document is the authoritative Database Specification v1 baseline for future ThuScene database work. Future schema changes must be made through new migrations and documented as subsequent database state/specification changes; this v1 document should not be silently rewritten to describe a later schema.

Freezing this document made no change to the database.