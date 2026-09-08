-- Spike 1: dedicated roles. Applied to hosted Supabase via GitHub integration.
-- LOGIN password for app_runtime is set out of band (never committed).
-- If hosted Supabase rejects CREATE ROLE / BYPASSRLS, Spike 1 stops and the spec is revised.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner') THEN
    CREATE ROLE app_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime') THEN
    CREATE ROLE app_runtime NOLOGIN NOSUPERUSER NOINHERIT NOBYPASSRLS;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_authz') THEN
    CREATE ROLE app_authz NOLOGIN NOSUPERUSER NOINHERIT BYPASSRLS;
  END IF;
END
$$;

REVOKE ALL ON SCHEMA public FROM app_runtime;
GRANT USAGE ON SCHEMA public TO app_runtime;
