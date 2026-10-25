\set ON_ERROR_STOP on

-- ThuScene S6.6 concurrency-protocol prototype.
-- DISPOSABLE TEST DATABASE ONLY. This is not a production migration.

CREATE TABLE events (
    id uuid PRIMARY KEY,
    name text NOT NULL
);

CREATE TABLE attendance_routes (
    id uuid PRIMARY KEY,
    event_id uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    name text NOT NULL
);

CREATE TABLE event_occurrences (
    id uuid PRIMARY KEY,
    event_id uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    name text NOT NULL
);

CREATE TABLE attendance_route_occurrences (
    attendance_route_id uuid NOT NULL REFERENCES attendance_routes(id) ON DELETE CASCADE,
    event_occurrence_id uuid NOT NULL REFERENCES event_occurrences(id) ON DELETE CASCADE,
    PRIMARY KEY (attendance_route_id, event_occurrence_id)
);

-- One deliberately global lock for all writes that can affect the invariant.
-- These integer keys are test-only and must not be reused by production code.
CREATE FUNCTION s66_require_preheld_lock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_locks AS l
        WHERE l.locktype = 'advisory'
          AND l.pid = pg_backend_pid()
          AND l.granted
          AND l.classid = 73142::oid
          AND l.objid = 9001::oid
          AND l.objsubid = 2
    ) THEN
        RAISE EXCEPTION
            'S6.6 protected write requires the advisory lock to be acquired before the statement'
            USING ERRCODE = '55000';
    END IF;
    RETURN NULL; -- statement-level trigger
END;
$$;

-- Defensive guards do NOT acquire a potentially late lock. They reject
-- direct writes unless the transaction acquired the lock before the statement.
CREATE TRIGGER s66_guard_link_insert_update
BEFORE INSERT OR UPDATE ON attendance_route_occurrences
FOR EACH STATEMENT EXECUTE FUNCTION s66_require_preheld_lock();

CREATE TRIGGER s66_guard_route_event_change
BEFORE UPDATE OF event_id ON attendance_routes
FOR EACH STATEMENT EXECUTE FUNCTION s66_require_preheld_lock();

CREATE TRIGGER s66_guard_occurrence_event_change
BEFORE UPDATE OF event_id ON event_occurrences
FOR EACH STATEMENT EXECUTE FUNCTION s66_require_preheld_lock();

-- Deferred validation checks the current database state, not OLD/NEW alone.
CREATE FUNCTION s66_validate_same_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.attendance_route_occurrences AS aro
        JOIN public.attendance_routes AS ar
          ON ar.id = aro.attendance_route_id
        JOIN public.event_occurrences AS eo
          ON eo.id = aro.event_occurrence_id
        WHERE ar.event_id <> eo.event_id
    ) THEN
        RAISE EXCEPTION
            'S6.6 invariant violated: linked route and occurrence belong to different events'
            USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER s66_check_link_after_insert_update
AFTER INSERT OR UPDATE ON attendance_route_occurrences
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION s66_validate_same_event();

CREATE CONSTRAINT TRIGGER s66_check_route_event_change
AFTER UPDATE ON attendance_routes
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
WHEN (OLD.event_id IS DISTINCT FROM NEW.event_id)
EXECUTE FUNCTION s66_validate_same_event();

CREATE CONSTRAINT TRIGGER s66_check_occurrence_event_change
AFTER UPDATE ON event_occurrences
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
WHEN (OLD.event_id IS DISTINCT FROM NEW.event_id)
EXECUTE FUNCTION s66_validate_same_event();

-- Controlled write functions: lock before ownership reads or modifications.
-- They use SECURITY DEFINER with a fixed search_path; production still needs a reviewed privilege model.
CREATE FUNCTION s66_create_link(p_route_id uuid, p_occurrence_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'S6.6 prototype supports READ COMMITTED only';
    END IF;
    PERFORM pg_advisory_xact_lock(73142, 9001);
    INSERT INTO public.attendance_route_occurrences(attendance_route_id, event_occurrence_id)
    VALUES (p_route_id, p_occurrence_id);
END;
$$;

CREATE FUNCTION s66_delete_link(p_route_id uuid, p_occurrence_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'S6.6 prototype supports READ COMMITTED only';
    END IF;
    PERFORM pg_advisory_xact_lock(73142, 9001);
    DELETE FROM public.attendance_route_occurrences
    WHERE attendance_route_id = p_route_id
      AND event_occurrence_id = p_occurrence_id;
END;
$$;

CREATE FUNCTION s66_move_route(p_route_id uuid, p_new_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'S6.6 prototype supports READ COMMITTED only';
    END IF;
    PERFORM pg_advisory_xact_lock(73142, 9001);
    UPDATE public.attendance_routes SET event_id = p_new_event_id WHERE id = p_route_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'route not found: %', p_route_id; END IF;
END;
$$;

CREATE FUNCTION s66_move_occurrence(p_occurrence_id uuid, p_new_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'S6.6 prototype supports READ COMMITTED only';
    END IF;
    PERFORM pg_advisory_xact_lock(73142, 9001);
    UPDATE public.event_occurrences SET event_id = p_new_event_id WHERE id = p_occurrence_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'occurrence not found: %', p_occurrence_id; END IF;
END;
$$;

-- Seed two events, one route and one occurrence. IDs are stable test fixtures.
INSERT INTO events(id, name) VALUES
('00000000-0000-0000-0000-000000000001', 'Event A'),
('00000000-0000-0000-0000-000000000002', 'Event B');

INSERT INTO attendance_routes(id, event_id, name) VALUES
('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'Route R');

INSERT INTO event_occurrences(id, event_id, name) VALUES
('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'Occurrence O');


-- Privilege-boundary fixture. The app role receives function execution only;
-- it gets no direct table DML rights. Functions/trigger validators are owned by
-- the bootstrap owner (postgres) and use fixed search paths.
CREATE ROLE s66_app NOLOGIN;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO s66_app;
REVOKE ALL ON public.events, public.attendance_routes, public.event_occurrences,
    public.attendance_route_occurrences FROM PUBLIC, s66_app;
REVOKE ALL ON FUNCTION public.s66_create_link(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.s66_delete_link(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.s66_move_route(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.s66_move_occurrence(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.s66_create_link(uuid, uuid) TO s66_app;
GRANT EXECUTE ON FUNCTION public.s66_delete_link(uuid, uuid) TO s66_app;
GRANT EXECUTE ON FUNCTION public.s66_move_route(uuid, uuid) TO s66_app;
GRANT EXECUTE ON FUNCTION public.s66_move_occurrence(uuid, uuid) TO s66_app;
