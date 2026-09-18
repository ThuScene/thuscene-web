# ThuScene pre-taxonomy database state

**Snapshot date:** 18 September 2026
**Database:** Supabase / PostgreSQL
**Purpose:** Source-control record of the live ThuScene database immediately before the Taxonomy v1 migration.

> This is a reconstructed **state record**, not a migration to run against Supabase. It was reconciled against the live database using read-only information-schema, constraint, index, RLS-policy, and privilege queries.

## Core model

The live database currently has the original 12 ThuScene tables:

1. events
2. event_occurrences
3. venues
4. organisers
5. event_organisers
6. artists
7. event_artists
8. categories
9. event_categories
10. sources
11. event_sources
12. ticket_offers

Core separation remains: events = what is happening; event_occurrences = when/where it can be attended; ticket_offers = how a particular occurrence can be attended/booked. Junction tables model organisers, artists and categories. sources/event_sources hold provenance and verification information.

## Original audited baseline

The database began from the FINAL AUDITED 12-TABLE DATABASE MIGRATION. That baseline created the 12 tables, UUID primary keys, foreign keys and delete behaviour, uniqueness/check constraints, partial unique indexes enforcing at most one primary organiser/artist/category per event, performance indexes, the shared public.set_updated_at() function and 12 updated_at triggers, RLS on all 12 tables, and eight initial discovery categories.

The original migration deliberately created no RLS policies. Policies were added later.

## Initial category seed

| Order | Name | Slug |
| ---: | --- | --- |
| 1 | Live Music | live-music |
| 2 | Comedy | comedy |
| 3 | Theatre & Shows | theatre-shows |
| 4 | Festivals | festivals |
| 5 | Family | family |
| 6 | Sport & Activities | sport-activities |
| 7 | Food & Drink | food-drink |
| 8 | Arts, Culture & Talks | arts-culture-talks |

## Importer / Spektrix extensions found in the live schema

These columns are present in the live database but were not in the original audited migration.

### event_occurrences

- source_reference text
- available_quantity integer
- capacity integer

Additional index:
- event_occurrences_source_reference_idx on source_reference

No additional live check constraints were found on event_occurrences.available_quantity or event_occurrences.capacity at snapshot time.

### ticket_offers

- available_quantity integer
- capacity integer
- source_reference text

Additional index:
- ticket_offers_source_reference_idx on source_reference

Additional live constraints:
- available_quantity is null or >= 0
- capacity is null or >= 0
- available_quantity/capacity may be null, otherwise available_quantity <= capacity

## Public read RLS policies

RLS is enabled on all 12 tables. Ten public SELECT policies currently exist for anon and authenticated:

- artists — public_can_read_active_artists
- categories — public_can_read_active_categories
- event_artists — public_can_read_artists_of_published_events
- event_categories — public_can_read_categories_of_published_events
- event_occurrences — public_can_read_occurrences_of_published_events
- event_organisers — public_can_read_organisers_of_published_events
- events — public_can_read_published_events
- organisers — public_can_read_active_organisers
- ticket_offers — public_can_read_tickets_for_published_events
- venues — public_can_read_active_venues

There are no public SELECT policies on sources or event_sources, keeping provenance/verification data private from the public application.

## Table privileges at snapshot time

service_role has full SELECT, INSERT, UPDATE and DELETE privileges on:
- events
- event_occurrences
- venues
- categories
- event_categories
- sources
- event_sources
- ticket_offers

At snapshot time service_role does not have those CRUD privileges on artists, event_artists, organisers, or event_organisers. Those four show REFERENCES, TRIGGER and TRUNCATE.

anon and authenticated have SELECT on the ten publicly readable tables above and no SELECT on sources/event_sources.

The privilege audit also showed REFERENCES, TRIGGER and TRUNCATE grants for anon/authenticated across the 12 tables. These appear broader than the public application requires and should be reviewed during security hardening; this snapshot records them without changing them.

## Important live constraints and indexes

The original audited constraints and indexes remain present, including unique slugs; unique category name/slug; unique junction pairs; unique (event_id, source_id) on event_sources; partial unique primary-organiser/artist/category indexes; occurrence event/venue/start indexes; junction reverse-lookup indexes; ticket-offer occurrence index; and the original status, price, coordinate, ordering and date-range checks.

The importer source_reference indexes and three ticket quantity/capacity checks described above are also present.

## Known pre-taxonomy observations

These are observations for later review, not changes made by this snapshot:

1. event_occurrences.available_quantity and capacity do not currently have equivalent non-negative / quantity-not-over-capacity checks to ticket_offers.
2. Public roles currently have REFERENCES, TRIGGER and TRUNCATE table privileges that appear broader than required and should be reviewed.
3. service_role CRUD permissions currently cover the importer-facing subset, not artist/organiser tables.
4. The database remains the 12-table model at this checkpoint. Taxonomy v1 has not been represented in this snapshot.

## Migration-history interpretation

The verified live state is consistent with this logical history:

Original audited 12-table schema
→ Public read-security additions
→ Importer / Spektrix schema extensions
→ Importer service_role permissions
→ **THIS PRE-TAXONOMY CHECKPOINT**
→ Taxonomy v1 (next)

The earlier steps may not exist in Git as separate historical migration files. This document therefore does not invent migration history or claim that reconstructed files were originally executed. It records the verified live state before the next migration.

## Rule for the next step

Any Taxonomy v1 migration must be designed against this live pre-taxonomy state, preserve existing data and category identifiers where required, and be additive / safely reversible where practical.

**Do not rerun the original 12-table migration against the existing Supabase database.**
