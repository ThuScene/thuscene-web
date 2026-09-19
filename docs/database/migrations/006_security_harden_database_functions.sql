-- ThuScene database security hardening
-- Purpose:
--   1. Give public.set_updated_at() an explicit safe search_path.
--   2. Remove unnecessary PUBLIC direct EXECUTE access from
--      public.rls_auto_enable() and public.set_updated_at().
--
-- This is deliberately separate from 005_taxonomy_v1.
-- It does not alter taxonomy data, RLS policies, table privileges,
-- the ensure_rls event trigger, or any table trigger definition.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

-- ---------------------------------------------------------------------------
-- 1. PRE-FLIGHT ASSERTIONS
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  ensure_rls_count integer;
  updated_at_trigger_count integer;
BEGIN
  IF to_regprocedure('public.rls_auto_enable()') IS NULL THEN
    RAISE EXCEPTION 'Security hardening pre-flight failed: public.rls_auto_enable() is missing';
  END IF;

  IF to_regprocedure('public.set_updated_at()') IS NULL THEN
    RAISE EXCEPTION 'Security hardening pre-flight failed: public.set_updated_at() is missing';
  END IF;

  -- Confirm the event trigger is exactly the infrastructure we audited:
  -- enabled, ddl_command_end, and bound to public.rls_auto_enable().
  SELECT count(*)
  INTO ensure_rls_count
  FROM pg_event_trigger e
  JOIN pg_proc p ON p.oid = e.evtfoid
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE e.evtname = 'ensure_rls'
    AND e.evtevent = 'ddl_command_end'
    AND e.evtenabled <> 'D'
    AND n.nspname = 'public'
    AND p.proname = 'rls_auto_enable'
    AND pg_get_function_identity_arguments(p.oid) = '';

  IF ensure_rls_count <> 1 THEN
    RAISE EXCEPTION
      'Security hardening pre-flight failed: expected one enabled ensure_rls event trigger bound to public.rls_auto_enable(), found %',
      ensure_rls_count;
  END IF;

  -- Confirm rls_auto_enable remains SECURITY DEFINER with the already-safe
  -- pg_catalog search_path.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'rls_auto_enable'
      AND pg_get_function_identity_arguments(p.oid) = ''
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=pg_catalog']::text[]
  ) THEN
    RAISE EXCEPTION
      'Security hardening pre-flight failed: rls_auto_enable() does not match the audited SECURITY DEFINER/search_path state';
  END IF;

  -- set_updated_at is expected to remain SECURITY INVOKER.
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'set_updated_at'
      AND pg_get_function_identity_arguments(p.oid) = ''
      AND p.prosecdef
  ) THEN
    RAISE EXCEPTION
      'Security hardening pre-flight failed: set_updated_at() unexpectedly uses SECURITY DEFINER';
  END IF;

  -- The audited ThuScene schema has exactly 16 non-internal table triggers
  -- using set_updated_at(), all enabled.
  SELECT count(*)
  INTO updated_at_trigger_count
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace pn ON pn.oid = p.pronamespace
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace cn ON cn.oid = c.relnamespace
  WHERE NOT t.tgisinternal
    AND pn.nspname = 'public'
    AND p.proname = 'set_updated_at'
    AND pg_get_function_identity_arguments(p.oid) = ''
    AND cn.nspname = 'public'
    AND c.relname IN (
      'events', 'event_occurrences', 'venues', 'organisers',
      'event_organisers', 'artists', 'event_artists', 'categories',
      'event_categories', 'sources', 'event_sources', 'ticket_offers',
      'event_forms', 'tags', 'event_tags', 'taxonomy_aliases'
    )
    AND t.tgenabled <> 'D';

  IF updated_at_trigger_count <> 16 THEN
    RAISE EXCEPTION
      'Security hardening pre-flight failed: expected 16 enabled ThuScene set_updated_at triggers, found %',
      updated_at_trigger_count;
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- 2. HARDEN FUNCTIONS
-- ---------------------------------------------------------------------------

ALTER FUNCTION public.set_updated_at()
  SET search_path = pg_catalog;

REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_updated_at() FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 3. POST-CHANGE ASSERTIONS
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  ensure_rls_count integer;
  updated_at_trigger_count integer;
BEGIN
  -- Both functions must still be owned by postgres and executable by the owner.
  IF EXISTS (
    SELECT 1
    FROM (
      VALUES
        ('rls_auto_enable'),
        ('set_updated_at')
    ) AS expected(function_name)
    WHERE NOT EXISTS (
      SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_roles r ON r.oid = p.proowner
      WHERE n.nspname = 'public'
        AND p.proname = expected.function_name
        AND pg_get_function_identity_arguments(p.oid) = ''
        AND r.rolname = 'postgres'
        AND has_function_privilege('postgres', p.oid, 'EXECUTE')
    )
  ) THEN
    RAISE EXCEPTION
      'Security hardening validation failed: postgres ownership/execution was not preserved';
  END IF;

  -- PUBLIC, anon and authenticated must no longer be able to invoke either
  -- function directly. Checking effective privileges catches inheritance.
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('rls_auto_enable', 'set_updated_at')
      AND pg_get_function_identity_arguments(p.oid) = ''
      AND (
        has_function_privilege('public', p.oid, 'EXECUTE')
        OR has_function_privilege('anon', p.oid, 'EXECUTE')
        OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
      )
  ) THEN
    RAISE EXCEPTION
      'Security hardening validation failed: PUBLIC/anon/authenticated still has effective EXECUTE on a hardened function';
  END IF;

  -- The updated-at function must now have the explicit safe search_path and
  -- must still be SECURITY INVOKER.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'set_updated_at'
      AND pg_get_function_identity_arguments(p.oid) = ''
      AND NOT p.prosecdef
      AND p.proconfig @> ARRAY['search_path=pg_catalog']::text[]
  ) THEN
    RAISE EXCEPTION
      'Security hardening validation failed: set_updated_at() search_path/security mode is not as expected';
  END IF;

  -- rls_auto_enable must remain SECURITY DEFINER with its existing safe path.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'rls_auto_enable'
      AND pg_get_function_identity_arguments(p.oid) = ''
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=pg_catalog']::text[]
  ) THEN
    RAISE EXCEPTION
      'Security hardening validation failed: rls_auto_enable() security configuration changed unexpectedly';
  END IF;

  -- ensure_rls must remain enabled and bound to rls_auto_enable().
  SELECT count(*)
  INTO ensure_rls_count
  FROM pg_event_trigger e
  JOIN pg_proc p ON p.oid = e.evtfoid
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE e.evtname = 'ensure_rls'
    AND e.evtevent = 'ddl_command_end'
    AND e.evtenabled <> 'D'
    AND n.nspname = 'public'
    AND p.proname = 'rls_auto_enable'
    AND pg_get_function_identity_arguments(p.oid) = '';

  IF ensure_rls_count <> 1 THEN
    RAISE EXCEPTION
      'Security hardening validation failed: ensure_rls event trigger was not preserved';
  END IF;

  -- All 16 audited updated_at triggers must remain present and enabled.
  SELECT count(*)
  INTO updated_at_trigger_count
  FROM pg_trigger t
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace pn ON pn.oid = p.pronamespace
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace cn ON cn.oid = c.relnamespace
  WHERE NOT t.tgisinternal
    AND pn.nspname = 'public'
    AND p.proname = 'set_updated_at'
    AND pg_get_function_identity_arguments(p.oid) = ''
    AND cn.nspname = 'public'
    AND c.relname IN (
      'events', 'event_occurrences', 'venues', 'organisers',
      'event_organisers', 'artists', 'event_artists', 'categories',
      'event_categories', 'sources', 'event_sources', 'ticket_offers',
      'event_forms', 'tags', 'event_tags', 'taxonomy_aliases'
    )
    AND t.tgenabled <> 'D';

  IF updated_at_trigger_count <> 16 THEN
    RAISE EXCEPTION
      'Security hardening validation failed: expected 16 enabled ThuScene set_updated_at triggers after hardening, found %',
      updated_at_trigger_count;
  END IF;
END
$$;

COMMIT;