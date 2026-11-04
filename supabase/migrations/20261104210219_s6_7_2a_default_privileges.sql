
-- ThuScene Database Design 007
-- Stage 6.7.2A: Default privilege hardening
--
-- Scope:
--   1. Restrict default table privileges for future objects
--      created by postgres in the public schema.
--   2. Revoke PostgreSQL's default PUBLIC EXECUTE privilege
--      for future functions and procedures created by postgres.
--
-- Existing object privileges are unchanged.
-- Sequence defaults are unchanged.
-- supabase_admin defaults are unchanged.

ALTER DEFAULT PRIVILEGES
    FOR ROLE postgres
    IN SCHEMA public
    REVOKE MAINTAIN, REFERENCES, TRIGGER, TRUNCATE
    ON TABLES
    FROM anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES
    FOR ROLE postgres
    REVOKE EXECUTE ON FUNCTIONS
    FROM PUBLIC;
