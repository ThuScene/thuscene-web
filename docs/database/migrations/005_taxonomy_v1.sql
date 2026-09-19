-- ThuScene Taxonomy v1 migration
-- Implements: ThuScene Taxonomy Data Model Specification v1 (Frozen)
-- Starting point: verified pre-taxonomy database checkpoint, 2026-09-18
--
-- IMPORTANT:
--   * Run against the verified live pre-taxonomy state only.
--   * Do NOT rerun the original 12-table migration first.
--   * This migration performs no editorial event reclassification.

BEGIN;

-- Fail quickly rather than wait indefinitely behind unrelated DDL.
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. PRE-FLIGHT ASSERTIONS
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  missing_tables text[];
  present_new_tables text[];
  present_new_columns text[];
  unexpected_categories integer;
  primary_duplicates integer;
  primary_unique_enforced boolean;
  fn_present boolean;
BEGIN
  SELECT array_agg(x.name ORDER BY x.name)
  INTO missing_tables
  FROM (VALUES
    ('events'), ('event_occurrences'), ('venues'), ('organisers'),
    ('event_organisers'), ('artists'), ('event_artists'), ('categories'),
    ('event_categories'), ('sources'), ('event_sources'), ('ticket_offers')
  ) AS x(name)
  WHERE to_regclass('public.' || x.name) IS NULL;

  IF missing_tables IS NOT NULL THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: missing required tables: %', missing_tables;
  END IF;

  SELECT array_agg(x.name ORDER BY x.name)
  INTO present_new_tables
  FROM (VALUES ('event_forms'), ('tags'), ('event_tags'), ('taxonomy_aliases')) AS x(name)
  WHERE to_regclass('public.' || x.name) IS NOT NULL;

  IF present_new_tables IS NOT NULL THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: new taxonomy tables already exist: %', present_new_tables;
  END IF;

  SELECT array_agg(c.column_name ORDER BY c.column_name)
  INTO present_new_columns
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name = 'events'
    AND c.column_name IN (
      'event_form_id',
      'category_review_status', 'category_last_reviewed_at',
      'event_form_review_status', 'event_form_last_reviewed_at',
      'tags_review_status', 'tags_last_reviewed_at'
    );

  IF present_new_columns IS NOT NULL THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: taxonomy columns already exist on events: %', present_new_columns;
  END IF;

  -- The migration is intentionally tied to the verified eight-row starting vocabulary.
  SELECT count(*)
  INTO unexpected_categories
  FROM public.categories;

  IF unexpected_categories <> 8 THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: expected exactly 8 starting categories, found %', unexpected_categories;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.categories c
    LEFT JOIN (VALUES
      ('Live Music', 'live-music', 1, 'active'),
      ('Comedy', 'comedy', 2, 'active'),
      ('Theatre & Shows', 'theatre-shows', 3, 'active'),
      ('Festivals', 'festivals', 4, 'active'),
      ('Family', 'family', 5, 'active'),
      ('Sport & Activities', 'sport-activities', 6, 'active'),
      ('Food & Drink', 'food-drink', 7, 'active'),
      ('Arts, Culture & Talks', 'arts-culture-talks', 8, 'active')
    ) AS expected(name, slug, display_order, status)
      ON c.name = expected.name
     AND c.slug = expected.slug
     AND c.display_order = expected.display_order
     AND c.status = expected.status
    WHERE expected.name IS NULL
  ) OR EXISTS (
    SELECT 1
    FROM (VALUES
      ('Live Music', 'live-music', 1, 'active'),
      ('Comedy', 'comedy', 2, 'active'),
      ('Theatre & Shows', 'theatre-shows', 3, 'active'),
      ('Festivals', 'festivals', 4, 'active'),
      ('Family', 'family', 5, 'active'),
      ('Sport & Activities', 'sport-activities', 6, 'active'),
      ('Food & Drink', 'food-drink', 7, 'active'),
      ('Arts, Culture & Talks', 'arts-culture-talks', 8, 'active')
    ) AS expected(name, slug, display_order, status)
    LEFT JOIN public.categories c
      ON c.name = expected.name
     AND c.slug = expected.slug
     AND c.display_order = expected.display_order
     AND c.status = expected.status
    WHERE c.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: starting category name/slug/status/display_order does not match the verified checkpoint';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.categories
    WHERE (name = 'Sport' OR slug = 'sport' OR name = 'Arts & Culture' OR slug = 'arts-culture')
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: target category name/slug collision already exists';
  END IF;

  SELECT count(*) INTO primary_duplicates
  FROM (
    SELECT event_id
    FROM public.event_categories
    WHERE is_primary
    GROUP BY event_id
    HAVING count(*) > 1
  ) d;

  IF primary_duplicates <> 0 THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: event_categories contains events with multiple primary categories';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'event_categories'
      AND i.indisunique
      AND i.indpred IS NOT NULL
      AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%is_primary%'
      AND EXISTS (
        SELECT 1
        FROM unnest(i.indkey) AS k(attnum)
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
        WHERE a.attname = 'event_id'
      )
  ) INTO primary_unique_enforced;

  IF NOT primary_unique_enforced THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: could not verify a partial unique primary-category rule on event_categories(event_id)';
  END IF;

  SELECT to_regprocedure('public.set_updated_at()') IS NOT NULL INTO fn_present;
  IF NOT fn_present THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: public.set_updated_at() is missing';
  END IF;

  -- Importer/Spektrix extensions must be present exactly as dependencies of this migration.
  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('event_occurrences', 'source_reference', 'text'),
      ('event_occurrences', 'available_quantity', 'integer'),
      ('event_occurrences', 'capacity', 'integer'),
      ('ticket_offers', 'source_reference', 'text'),
      ('ticket_offers', 'available_quantity', 'integer'),
      ('ticket_offers', 'capacity', 'integer')
    ) AS expected(table_name, column_name, data_type)
    LEFT JOIN information_schema.columns c
      ON c.table_schema = 'public'
     AND c.table_name = expected.table_name
     AND c.column_name = expected.column_name
     AND c.data_type = expected.data_type
    WHERE c.column_name IS NULL
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: verified importer extension columns/types are missing';
  END IF;
END
$$;

-- Transaction-local preservation baselines.
CREATE TEMP TABLE _taxonomy_v1_row_counts (
  table_name text PRIMARY KEY,
  row_count bigint NOT NULL
) ON COMMIT DROP;

DO $$
DECLARE
  t text;
  n bigint;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'events','event_occurrences','venues','organisers','event_organisers','artists',
    'event_artists','categories','event_categories','sources','event_sources','ticket_offers'
  ] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
    INSERT INTO _taxonomy_v1_row_counts(table_name, row_count) VALUES (t, n);
  END LOOP;
END
$$;

CREATE TEMP TABLE _taxonomy_v1_category_baseline ON COMMIT DROP AS
SELECT id, name, slug, display_order, status
FROM public.categories;

CREATE TEMP TABLE _taxonomy_v1_event_categories_baseline ON COMMIT DROP AS
SELECT id, event_id, category_id, is_primary, display_order
FROM public.event_categories;

CREATE TEMP TABLE _taxonomy_v1_existing_events ON COMMIT DROP AS
SELECT id FROM public.events;

-- Preserve the verified importer-specific indexes/check constraints byte-for-byte
-- at catalog-definition level. The migration does not modify these objects.
CREATE TEMP TABLE _taxonomy_v1_importer_indexes ON COMMIT DROP AS
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname='public'
  AND indexname IN ('event_occurrences_source_reference_idx', 'ticket_offers_source_reference_idx');

DO $$
BEGIN
  IF (SELECT count(*) FROM _taxonomy_v1_importer_indexes) <> 2 THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: verified importer source_reference indexes are missing';
  END IF;
END
$$;

CREATE TEMP TABLE _taxonomy_v1_ticket_quantity_checks ON COMMIT DROP AS
SELECT c.conname, pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
JOIN pg_class t ON t.oid=c.conrelid
JOIN pg_namespace ns ON ns.oid=t.relnamespace
WHERE ns.nspname='public' AND t.relname='ticket_offers' AND c.contype='c'
  AND (pg_get_constraintdef(c.oid) ILIKE '%available_quantity%'
       OR pg_get_constraintdef(c.oid) ILIKE '%capacity%');

DO $$
BEGIN
  IF (SELECT count(*) FROM _taxonomy_v1_ticket_quantity_checks) < 3 THEN
    RAISE EXCEPTION 'Taxonomy v1 pre-flight failed: verified ticket quantity/capacity checks are missing';
  END IF;
END
$$;

CREATE TEMP TABLE _taxonomy_v1_service_privileges ON COMMIT DROP AS
SELECT t.table_name, p.privilege_type
FROM (VALUES
  ('events'),('event_occurrences'),('venues'),('organisers'),('event_organisers'),('artists'),
  ('event_artists'),('categories'),('event_categories'),('sources'),('event_sources'),('ticket_offers')
) AS t(table_name)
CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) AS p(privilege_type)
WHERE has_table_privilege('service_role', format('public.%I', t.table_name), p.privilege_type);

CREATE TEMP TABLE _taxonomy_v1_unrelated_policies ON COMMIT DROP AS
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'events','event_occurrences','venues','organisers','event_organisers','artists',
    'event_artists','sources','event_sources','ticket_offers'
  );

-- ---------------------------------------------------------------------------
-- 2. NEW CANONICAL TAXONOMY TABLES
-- ---------------------------------------------------------------------------

CREATE TABLE public.event_forms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  slug text NOT NULL UNIQUE,
  description text,
  display_order integer NOT NULL CHECK (display_order > 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_event_forms_updated_at
BEFORE UPDATE ON public.event_forms
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.event_forms ENABLE ROW LEVEL SECURITY;

INSERT INTO public.event_forms (name, slug, description, display_order, status) VALUES
  ('Performance', 'performance', 'A live audience watches a theatrical, comedic, choreographic, circus, puppetry, performance-art or comparable performed work.', 1, 'active'),
  ('Concert', 'concert', 'Musicians perform music live for an audience; gigs, recitals and live sets may map to this form.', 2, 'active'),
  ('Exhibition', 'exhibition', 'A curated display in which visitors explore works, objects or other presented material.', 3, 'active'),
  ('Film Screening', 'film-screening', 'A scheduled presentation of film or other moving-image work to an audience.', 4, 'active'),
  ('Workshop', 'workshop', 'A focused practical or creative session in which participants actively make, practise, explore or develop something.', 5, 'active'),
  ('Class', 'class', 'An instructor-led session for learning or practising in a recognisable class format.', 6, 'active'),
  ('Course', 'course', 'Multiple linked sessions that collectively form a programme of learning or development.', 7, 'active'),
  ('Guided Tour', 'guided-tour', 'A led experience through a place, route, site, collection or environment with interpretation.', 8, 'active'),
  ('Demonstration', 'demonstration', 'An event centred on watching a practitioner show a process or technique.', 9, 'active'),
  ('Talk', 'talk', 'A speaker or speakers present ideas, knowledge, stories or discussion to an audience, including lectures, conversations and panels.', 10, 'active'),
  ('Festival', 'festival', 'An overarching programme containing multiple activities or events under a shared identity.', 11, 'active'),
  ('Market', 'market', 'An event centred on browsing or purchasing from multiple vendors or traders.', 12, 'active'),
  ('Fair', 'fair', 'A multi-exhibitor showcase where exhibition, discovery or engagement is at least as fundamental as retail.', 13, 'active'),
  ('Open Day', 'open-day', 'An organisation or site invites people to explore it through a specially open or programmed experience rather than ordinary opening hours.', 14, 'active'),
  ('Retreat', 'retreat', 'An extended immersive experience centred on sustained activity, practice or reflection; overnight participation is not required.', 15, 'active'),
  ('Meetup', 'meetup', 'A gathering centred on people interacting around a shared interest, activity, identity or purpose.', 16, 'active'),
  ('Conference', 'conference', 'A professional, academic, industry or specialist gathering containing multiple programmed sessions.', 17, 'active'),
  ('Quiz', 'quiz', 'An organised event structured around questions and scoring.', 18, 'active'),
  ('Tasting', 'tasting', 'An event centred on sampling, comparing or evaluating food or drink.', 19, 'active'),
  ('Parade', 'parade', 'An organised public procession.', 20, 'active'),
  ('Race', 'race', 'A competitive event on a defined course, route or distance where outcome is principally determined by time or finishing order.', 21, 'active'),
  ('Club Night', 'club-night', 'A nightlife event centred on DJs or recorded music and dancing rather than an audience watching a live concert.', 22, 'active'),
  ('Competition', 'competition', 'A competitive event under rules or judging that is neither more specifically a Match nor a Race.', 23, 'active'),
  ('Match', 'match', 'A single defined sporting contest between two opposing individuals or teams.', 24, 'active');

CREATE TABLE public.tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  slug text NOT NULL UNIQUE,
  description text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_tags_updated_at
BEFORE UPDATE ON public.tags
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.event_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES public.tags(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT event_tags_event_id_tag_id_key UNIQUE (event_id, tag_id)
);

CREATE INDEX event_tags_tag_id_idx ON public.event_tags(tag_id);

CREATE TRIGGER set_event_tags_updated_at
BEFORE UPDATE ON public.event_tags
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.event_tags ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.taxonomy_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alias_text text NOT NULL,
  alias_key text NOT NULL,
  source_id uuid REFERENCES public.sources(id) ON DELETE RESTRICT,
  source_field text,
  category_id uuid REFERENCES public.categories(id) ON DELETE RESTRICT,
  event_form_id uuid REFERENCES public.event_forms(id) ON DELETE RESTRICT,
  tag_id uuid REFERENCES public.tags(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT taxonomy_aliases_exactly_one_target_chk
    CHECK (num_nonnulls(category_id, event_form_id, tag_id) = 1),
  CONSTRAINT taxonomy_aliases_source_field_requires_source_chk
    CHECK (source_field IS NULL OR source_id IS NOT NULL)
);

CREATE UNIQUE INDEX taxonomy_aliases_active_scope_key_uidx
ON public.taxonomy_aliases (source_id, source_field, alias_key) NULLS NOT DISTINCT
WHERE status = 'active';

CREATE INDEX taxonomy_aliases_source_id_idx ON public.taxonomy_aliases(source_id);
CREATE INDEX taxonomy_aliases_category_id_idx ON public.taxonomy_aliases(category_id);
CREATE INDEX taxonomy_aliases_event_form_id_idx ON public.taxonomy_aliases(event_form_id);
CREATE INDEX taxonomy_aliases_tag_id_idx ON public.taxonomy_aliases(tag_id);

CREATE TRIGGER set_taxonomy_aliases_updated_at
BEFORE UPDATE ON public.taxonomy_aliases
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.taxonomy_aliases ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 3. EXTEND EVENTS
-- ---------------------------------------------------------------------------

ALTER TABLE public.events
  ADD COLUMN event_form_id uuid,
  ADD COLUMN category_review_status text NOT NULL DEFAULT 'unreviewed',
  ADD COLUMN category_last_reviewed_at timestamptz,
  ADD COLUMN event_form_review_status text NOT NULL DEFAULT 'unreviewed',
  ADD COLUMN event_form_last_reviewed_at timestamptz,
  ADD COLUMN tags_review_status text NOT NULL DEFAULT 'unreviewed',
  ADD COLUMN tags_last_reviewed_at timestamptz,
  ADD CONSTRAINT events_event_form_id_fkey
    FOREIGN KEY (event_form_id) REFERENCES public.event_forms(id) ON DELETE RESTRICT,
  ADD CONSTRAINT events_category_review_status_chk
    CHECK (category_review_status IN ('unreviewed', 'reviewed', 'needs_review')),
  ADD CONSTRAINT events_event_form_review_status_chk
    CHECK (event_form_review_status IN ('unreviewed', 'reviewed', 'needs_review')),
  ADD CONSTRAINT events_tags_review_status_chk
    CHECK (tags_review_status IN ('unreviewed', 'reviewed', 'needs_review'));

CREATE INDEX events_event_form_id_idx ON public.events(event_form_id);

-- ---------------------------------------------------------------------------
-- 4. TRANSFORM EXISTING CATEGORIES IN PLACE
-- ---------------------------------------------------------------------------

UPDATE public.categories SET display_order = 1 WHERE slug = 'live-music';
UPDATE public.categories SET display_order = 2 WHERE slug = 'comedy';
UPDATE public.categories SET display_order = 3 WHERE slug = 'theatre-shows';
UPDATE public.categories SET display_order = 4 WHERE slug = 'food-drink';

UPDATE public.categories
SET name = 'Arts & Culture', slug = 'arts-culture', display_order = 5
WHERE slug = 'arts-culture-talks';

UPDATE public.categories
SET name = 'Sport', slug = 'sport', display_order = 6
WHERE slug = 'sport-activities';

UPDATE public.categories SET display_order = 7 WHERE slug = 'family';
UPDATE public.categories SET status = 'inactive', display_order = 8 WHERE slug = 'festivals';

-- ---------------------------------------------------------------------------
-- 5. TAXONOMY RLS POLICIES
-- ---------------------------------------------------------------------------

CREATE POLICY public_can_read_event_forms
ON public.event_forms
FOR SELECT TO anon, authenticated
USING (true);

CREATE POLICY public_can_read_tags
ON public.tags
FOR SELECT TO anon, authenticated
USING (true);

CREATE POLICY public_can_read_tags_of_published_events
ON public.event_tags
FOR SELECT TO anon, authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.id = event_tags.event_id
      AND e.status = 'published'
  )
);

-- taxonomy_aliases intentionally receives no public policy.

DROP POLICY public_can_read_active_categories ON public.categories;
CREATE POLICY public_can_read_categories
ON public.categories
FOR SELECT TO anon, authenticated
USING (true);

DROP POLICY public_can_read_categories_of_published_events ON public.event_categories;
CREATE POLICY public_can_read_categories_of_published_events
ON public.event_categories
FOR SELECT TO anon, authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.id = event_categories.event_id
      AND e.status = 'published'
  )
);

-- ---------------------------------------------------------------------------
-- 6. TABLE PRIVILEGES / SECURITY HARDENING
-- ---------------------------------------------------------------------------

-- Remove all table privileges for browser roles across the 16 ThuScene tables,
-- then grant only the intended public SELECT surface.
REVOKE ALL PRIVILEGES ON TABLE
  public.events,
  public.event_occurrences,
  public.venues,
  public.organisers,
  public.event_organisers,
  public.artists,
  public.event_artists,
  public.categories,
  public.event_categories,
  public.sources,
  public.event_sources,
  public.ticket_offers,
  public.event_forms,
  public.tags,
  public.event_tags,
  public.taxonomy_aliases
FROM anon, authenticated;

GRANT SELECT ON TABLE
  public.events,
  public.event_occurrences,
  public.venues,
  public.organisers,
  public.event_organisers,
  public.artists,
  public.event_artists,
  public.categories,
  public.event_categories,
  public.ticket_offers,
  public.event_forms,
  public.tags,
  public.event_tags
TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.event_forms,
  public.tags,
  public.event_tags,
  public.taxonomy_aliases
TO service_role;

-- ---------------------------------------------------------------------------
-- 7. POST-MIGRATION STRUCTURAL VALIDATION
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  n integer;
  ok boolean;
BEGIN
  -- All 16 named ThuScene application tables exist.
  SELECT count(*) INTO n
  FROM (VALUES
    ('events'),('event_occurrences'),('venues'),('organisers'),('event_organisers'),('artists'),
    ('event_artists'),('categories'),('event_categories'),('sources'),('event_sources'),('ticket_offers'),
    ('event_forms'),('tags'),('event_tags'),('taxonomy_aliases')
  ) AS x(name)
  WHERE to_regclass('public.' || x.name) IS NOT NULL;
  IF n <> 16 THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: not all 16 application tables exist'; END IF;

  -- Seven new event columns and core type/null/default properties.
  SELECT count(*) INTO n
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'events'
    AND column_name IN (
      'event_form_id','category_review_status','category_last_reviewed_at',
      'event_form_review_status','event_form_last_reviewed_at','tags_review_status','tags_last_reviewed_at'
    );
  IF n <> 7 THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: expected seven new events columns'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='events' AND column_name='event_form_id'
      AND data_type='uuid' AND is_nullable='YES' AND column_default IS NULL
  ) INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: events.event_form_id properties are incorrect'; END IF;

  SELECT count(*) INTO n
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='events'
    AND column_name IN ('category_review_status','event_form_review_status','tags_review_status')
    AND data_type='text' AND is_nullable='NO'
    AND column_default LIKE '%unreviewed%';
  IF n <> 3 THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: review status column properties are incorrect'; END IF;

  SELECT count(*) INTO n
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='events'
    AND column_name IN ('category_last_reviewed_at','event_form_last_reviewed_at','tags_last_reviewed_at')
    AND data_type='timestamp with time zone' AND is_nullable='YES';
  IF n <> 3 THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: review timestamp column properties are incorrect'; END IF;

  -- FK from events.event_form_id prevents referenced-form deletion.
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid=c.conrelid
    JOIN pg_namespace ns ON ns.oid=t.relnamespace
    JOIN pg_class rt ON rt.oid=c.confrelid
    WHERE ns.nspname='public' AND t.relname='events' AND rt.relname='event_forms'
      AND c.contype='f' AND c.confdeltype IN ('r','a')
      AND pg_get_constraintdef(c.oid) ILIKE '%event_form_id%'
  ) INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: events.event_form_id FK/delete behaviour missing'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='events' AND indexdef ILIKE '%(event_form_id)%'
  ) INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: events.event_form_id index missing'; END IF;

  -- Core checks/uniqueness/triggers for new tables.
  SELECT count(*) INTO n
  FROM pg_trigger tg
  JOIN pg_class t ON t.oid=tg.tgrelid
  JOIN pg_namespace ns ON ns.oid=t.relnamespace
  WHERE ns.nspname='public' AND t.relname IN ('event_forms','tags','event_tags','taxonomy_aliases')
    AND NOT tg.tgisinternal
    AND pg_get_triggerdef(tg.oid) ILIKE '%set_updated_at%';
  IF n <> 4 THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: expected four updated_at triggers on new tables'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=t.relnamespace
    WHERE ns.nspname='public' AND t.relname='event_tags' AND c.contype='u'
      AND pg_get_constraintdef(c.oid) ILIKE '%event_id%tag_id%'
  ) INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: event_tags unique(event_id, tag_id) missing'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='event_tags'
      AND indexdef ILIKE '%(tag_id)%'
  ) INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: event_tags reverse tag_id index missing'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=t.relnamespace
    WHERE ns.nspname='public' AND t.relname='taxonomy_aliases' AND c.contype='c'
      AND pg_get_constraintdef(c.oid) ILIKE '%num_nonnulls%category_id%event_form_id%tag_id%'
  ) INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: taxonomy_aliases exactly-one-target check missing'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=t.relnamespace
    WHERE ns.nspname='public' AND t.relname='taxonomy_aliases' AND c.contype='c'
      AND pg_get_constraintdef(c.oid) ILIKE '%source_field%source_id%'
  ) INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: taxonomy_aliases source-field/source check missing'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='taxonomy_aliases'
      AND indexdef ILIKE '%UNIQUE%source_id%source_field%alias_key%NULLS NOT DISTINCT%'
      AND indexdef ILIKE '%WHERE%status%active%'
  ) INTO ok;
  IF NOT ok THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: active NULL-aware taxonomy alias uniqueness missing'; END IF;

  -- RLS remains enabled on all 16 application tables.
  SELECT count(*) INTO n
  FROM pg_class t JOIN pg_namespace ns ON ns.oid=t.relnamespace
  WHERE ns.nspname='public'
    AND t.relname IN (
      'events','event_occurrences','venues','organisers','event_organisers','artists','event_artists',
      'categories','event_categories','sources','event_sources','ticket_offers',
      'event_forms','tags','event_tags','taxonomy_aliases'
    )
    AND t.relrowsecurity;
  IF n <> 16 THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: RLS is not enabled on all 16 application tables'; END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- 8. TAXONOMY / DATA-PRESERVATION VALIDATION
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  n bigint;
  t text;
  before_count bigint;
  after_count bigint;
BEGIN
  SELECT count(*) INTO n FROM public.categories;
  IF n <> 8 THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: expected 8 total categories, found %', n; END IF;

  SELECT count(*) INTO n FROM public.categories WHERE status='active';
  IF n <> 7 THEN RAISE EXCEPTION 'Taxonomy v1 validation failed: expected 7 active categories, found %', n; END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('Live Music','live-music',1,'active'),
      ('Comedy','comedy',2,'active'),
      ('Theatre & Shows','theatre-shows',3,'active'),
      ('Food & Drink','food-drink',4,'active'),
      ('Arts & Culture','arts-culture',5,'active'),
      ('Sport','sport',6,'active'),
      ('Family','family',7,'active'),
      ('Festivals','festivals',8,'inactive')
    ) AS expected(name,slug,display_order,status)
    LEFT JOIN public.categories c
      ON c.name=expected.name AND c.slug=expected.slug
     AND c.display_order=expected.display_order AND c.status=expected.status
    WHERE c.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: category target vocabulary/state mismatch';
  END IF;

  -- Every original category UUID still exists; only the expressly allowed fields changed.
  IF EXISTS (
    SELECT 1
    FROM _taxonomy_v1_category_baseline b
    LEFT JOIN public.categories c ON c.id=b.id
    WHERE c.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: an original category UUID was lost';
  END IF;

  -- Exact Event Form vocabulary, order, status and seed descriptions.
  IF (SELECT count(*) FROM public.event_forms) <> 24 THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: expected exactly 24 event forms';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('Performance','performance','A live audience watches a theatrical, comedic, choreographic, circus, puppetry, performance-art or comparable performed work.',1,'active'),
      ('Concert','concert','Musicians perform music live for an audience; gigs, recitals and live sets may map to this form.',2,'active'),
      ('Exhibition','exhibition','A curated display in which visitors explore works, objects or other presented material.',3,'active'),
      ('Film Screening','film-screening','A scheduled presentation of film or other moving-image work to an audience.',4,'active'),
      ('Workshop','workshop','A focused practical or creative session in which participants actively make, practise, explore or develop something.',5,'active'),
      ('Class','class','An instructor-led session for learning or practising in a recognisable class format.',6,'active'),
      ('Course','course','Multiple linked sessions that collectively form a programme of learning or development.',7,'active'),
      ('Guided Tour','guided-tour','A led experience through a place, route, site, collection or environment with interpretation.',8,'active'),
      ('Demonstration','demonstration','An event centred on watching a practitioner show a process or technique.',9,'active'),
      ('Talk','talk','A speaker or speakers present ideas, knowledge, stories or discussion to an audience, including lectures, conversations and panels.',10,'active'),
      ('Festival','festival','An overarching programme containing multiple activities or events under a shared identity.',11,'active'),
      ('Market','market','An event centred on browsing or purchasing from multiple vendors or traders.',12,'active'),
      ('Fair','fair','A multi-exhibitor showcase where exhibition, discovery or engagement is at least as fundamental as retail.',13,'active'),
      ('Open Day','open-day','An organisation or site invites people to explore it through a specially open or programmed experience rather than ordinary opening hours.',14,'active'),
      ('Retreat','retreat','An extended immersive experience centred on sustained activity, practice or reflection; overnight participation is not required.',15,'active'),
      ('Meetup','meetup','A gathering centred on people interacting around a shared interest, activity, identity or purpose.',16,'active'),
      ('Conference','conference','A professional, academic, industry or specialist gathering containing multiple programmed sessions.',17,'active'),
      ('Quiz','quiz','An organised event structured around questions and scoring.',18,'active'),
      ('Tasting','tasting','An event centred on sampling, comparing or evaluating food or drink.',19,'active'),
      ('Parade','parade','An organised public procession.',20,'active'),
      ('Race','race','A competitive event on a defined course, route or distance where outcome is principally determined by time or finishing order.',21,'active'),
      ('Club Night','club-night','A nightlife event centred on DJs or recorded music and dancing rather than an audience watching a live concert.',22,'active'),
      ('Competition','competition','A competitive event under rules or judging that is neither more specifically a Match nor a Race.',23,'active'),
      ('Match','match','A single defined sporting contest between two opposing individuals or teams.',24,'active')
    ) AS expected(name,slug,description,display_order,status)
    LEFT JOIN public.event_forms f
      ON f.name=expected.name AND f.slug=expected.slug AND f.description=expected.description
     AND f.display_order=expected.display_order AND f.status=expected.status
    WHERE f.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: event form vocabulary/seed descriptions mismatch';
  END IF;

  IF (SELECT count(*) FROM public.tags) <> 0
     OR (SELECT count(*) FROM public.event_tags) <> 0
     OR (SELECT count(*) FROM public.taxonomy_aliases) <> 0 THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: tags/event_tags/taxonomy_aliases must be empty immediately after migration';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM _taxonomy_v1_existing_events b
    JOIN public.events e ON e.id=b.id
    WHERE e.event_form_id IS NOT NULL
       OR e.category_review_status <> 'unreviewed'
       OR e.event_form_review_status <> 'unreviewed'
       OR e.tags_review_status <> 'unreviewed'
       OR e.category_last_reviewed_at IS NOT NULL
       OR e.event_form_last_reviewed_at IS NOT NULL
       OR e.tags_last_reviewed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: existing events were classified/reviewed by the structural migration';
  END IF;

  IF EXISTS (
    (SELECT id,event_id,category_id,is_primary,display_order FROM _taxonomy_v1_event_categories_baseline
     EXCEPT
     SELECT id,event_id,category_id,is_primary,display_order FROM public.event_categories)
    UNION ALL
    (SELECT id,event_id,category_id,is_primary,display_order FROM public.event_categories
     EXCEPT
     SELECT id,event_id,category_id,is_primary,display_order FROM _taxonomy_v1_event_categories_baseline)
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: event_categories relationships changed';
  END IF;

  FOREACH t IN ARRAY ARRAY[
    'events','event_occurrences','venues','organisers','event_organisers','artists',
    'event_artists','categories','event_categories','sources','event_sources','ticket_offers'
  ] LOOP
    SELECT row_count INTO before_count FROM _taxonomy_v1_row_counts WHERE table_name=t;
    EXECUTE format('SELECT count(*) FROM public.%I', t) INTO after_count;
    IF before_count <> after_count THEN
      RAISE EXCEPTION 'Taxonomy v1 validation failed: row count changed for % (% -> %)', t, before_count, after_count;
    END IF;
  END LOOP;

  IF EXISTS (
    (SELECT schemaname,tablename,indexname,indexdef FROM _taxonomy_v1_importer_indexes
     EXCEPT
     SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes
     WHERE schemaname='public' AND indexname IN ('event_occurrences_source_reference_idx','ticket_offers_source_reference_idx'))
    UNION ALL
    (SELECT schemaname,tablename,indexname,indexdef FROM pg_indexes
     WHERE schemaname='public' AND indexname IN ('event_occurrences_source_reference_idx','ticket_offers_source_reference_idx')
     EXCEPT
     SELECT schemaname,tablename,indexname,indexdef FROM _taxonomy_v1_importer_indexes)
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: importer source_reference indexes changed';
  END IF;

  IF EXISTS (
    (SELECT conname,definition FROM _taxonomy_v1_ticket_quantity_checks
     EXCEPT
     SELECT c.conname,pg_get_constraintdef(c.oid)
     FROM pg_constraint c JOIN pg_class x ON x.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=x.relnamespace
     WHERE ns.nspname='public' AND x.relname='ticket_offers' AND c.contype='c'
       AND (pg_get_constraintdef(c.oid) ILIKE '%available_quantity%' OR pg_get_constraintdef(c.oid) ILIKE '%capacity%'))
    UNION ALL
    (SELECT c.conname,pg_get_constraintdef(c.oid)
     FROM pg_constraint c JOIN pg_class x ON x.oid=c.conrelid JOIN pg_namespace ns ON ns.oid=x.relnamespace
     WHERE ns.nspname='public' AND x.relname='ticket_offers' AND c.contype='c'
       AND (pg_get_constraintdef(c.oid) ILIKE '%available_quantity%' OR pg_get_constraintdef(c.oid) ILIKE '%capacity%')
     EXCEPT
     SELECT conname,definition FROM _taxonomy_v1_ticket_quantity_checks)
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 validation failed: ticket quantity/capacity checks changed';
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- 9. SECURITY / POLICY VALIDATION
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  t text;
  p text;
  should_select boolean;
  before_privs text[];
  after_privs text[];
  policy_count integer;
BEGIN
  -- Browser roles: SELECT only on the 13 public-facing application tables.
  FOREACH t IN ARRAY ARRAY[
    'events','event_occurrences','venues','organisers','event_organisers','artists','event_artists',
    'categories','event_categories','ticket_offers','event_forms','tags','event_tags',
    'sources','event_sources','taxonomy_aliases'
  ] LOOP
    should_select := t NOT IN ('sources','event_sources','taxonomy_aliases');

    FOREACH p IN ARRAY ARRAY['anon','authenticated'] LOOP
      IF has_table_privilege(p, format('public.%I',t), 'SELECT') <> should_select THEN
        RAISE EXCEPTION 'Taxonomy v1 security validation failed: unexpected SELECT privilege for role % on %', p, t;
      END IF;

      IF has_table_privilege(p, format('public.%I',t), 'INSERT')
         OR has_table_privilege(p, format('public.%I',t), 'UPDATE')
         OR has_table_privilege(p, format('public.%I',t), 'DELETE')
         OR has_table_privilege(p, format('public.%I',t), 'TRUNCATE')
         OR has_table_privilege(p, format('public.%I',t), 'TRIGGER')
         OR has_table_privilege(p, format('public.%I',t), 'REFERENCES') THEN
        RAISE EXCEPTION 'Taxonomy v1 security validation failed: role % retains non-SELECT table privilege on %', p, t;
      END IF;
    END LOOP;
  END LOOP;

  -- Exact taxonomy policy semantics, with no stale overlapping public policies.
  SELECT count(*) INTO policy_count FROM pg_policies
  WHERE schemaname='public' AND tablename='categories'
    AND cmd='SELECT' AND roles @> ARRAY['anon','authenticated']::name[]
    AND qual = 'true';
  IF policy_count <> 1 THEN RAISE EXCEPTION 'Taxonomy v1 security validation failed: categories public policy is not exactly the intended all-rows SELECT policy'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='categories'
      AND policyname='public_can_read_active_categories'
  ) THEN RAISE EXCEPTION 'Taxonomy v1 security validation failed: obsolete active-only category policy remains'; END IF;

  SELECT count(*) INTO policy_count FROM pg_policies
  WHERE schemaname='public' AND tablename='event_forms' AND cmd='SELECT'
    AND roles @> ARRAY['anon','authenticated']::name[] AND qual='true';
  IF policy_count <> 1 THEN RAISE EXCEPTION 'Taxonomy v1 security validation failed: event_forms public policy missing/incorrect'; END IF;

  SELECT count(*) INTO policy_count FROM pg_policies
  WHERE schemaname='public' AND tablename='tags' AND cmd='SELECT'
    AND roles @> ARRAY['anon','authenticated']::name[] AND qual='true';
  IF policy_count <> 1 THEN RAISE EXCEPTION 'Taxonomy v1 security validation failed: tags public policy missing/incorrect'; END IF;

  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='taxonomy_aliases') THEN
    RAISE EXCEPTION 'Taxonomy v1 security validation failed: taxonomy_aliases unexpectedly has an RLS policy';
  END IF;

  -- Relationship policies must key only from published event status, not taxonomy lifecycle status.
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='event_categories'
      AND policyname='public_can_read_categories_of_published_events' AND cmd='SELECT'
      AND qual ILIKE '%events%' AND qual ILIKE '%published%'
      AND qual NOT ILIKE '%categories.status%'
  ) THEN RAISE EXCEPTION 'Taxonomy v1 security validation failed: event_categories public policy missing/incorrect'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='event_tags'
      AND policyname='public_can_read_tags_of_published_events' AND cmd='SELECT'
      AND qual ILIKE '%events%' AND qual ILIKE '%published%'
      AND qual NOT ILIKE '%tags.status%'
  ) THEN RAISE EXCEPTION 'Taxonomy v1 security validation failed: event_tags public policy missing/incorrect'; END IF;

  -- Existing unrelated policy definitions must be byte-for-byte equivalent at catalog-text level.
  IF EXISTS (
    (SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM _taxonomy_v1_unrelated_policies
     EXCEPT
     SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies
     WHERE schemaname='public' AND tablename IN (
       'events','event_occurrences','venues','organisers','event_organisers','artists',
       'event_artists','sources','event_sources','ticket_offers'))
    UNION ALL
    (SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies
     WHERE schemaname='public' AND tablename IN (
       'events','event_occurrences','venues','organisers','event_organisers','artists',
       'event_artists','sources','event_sources','ticket_offers')
     EXCEPT
     SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM _taxonomy_v1_unrelated_policies)
  ) THEN
    RAISE EXCEPTION 'Taxonomy v1 security validation failed: unrelated RLS policies changed';
  END IF;

  -- New taxonomy tables: explicit service_role CRUD, no requirement for TRUNCATE/TRIGGER/REFERENCES.
  FOREACH t IN ARRAY ARRAY['event_forms','tags','event_tags','taxonomy_aliases'] LOOP
    FOREACH p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
      IF NOT has_table_privilege('service_role', format('public.%I',t), p) THEN
        RAISE EXCEPTION 'Taxonomy v1 security validation failed: service_role lacks % on %', p, t;
      END IF;
    END LOOP;
  END LOOP;

  -- Existing service_role table privileges must be unchanged.
  FOR t IN SELECT table_name FROM (VALUES
    ('events'),('event_occurrences'),('venues'),('organisers'),('event_organisers'),('artists'),
    ('event_artists'),('categories'),('event_categories'),('sources'),('event_sources'),('ticket_offers')
  ) AS x(table_name)
  LOOP
    SELECT array_agg(privilege_type ORDER BY privilege_type)
      INTO before_privs
    FROM _taxonomy_v1_service_privileges WHERE table_name=t;

    SELECT array_agg(v.p ORDER BY v.p)
      INTO after_privs
    FROM (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) AS v(p)
    WHERE has_table_privilege('service_role', format('public.%I',t), v.p);

    IF before_privs IS DISTINCT FROM after_privs THEN
      RAISE EXCEPTION 'Taxonomy v1 security validation failed: service_role privileges changed on % (% -> %)', t, before_privs, after_privs;
    END IF;
  END LOOP;
END
$$;

COMMIT;