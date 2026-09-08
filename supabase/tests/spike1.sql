-- Spike 1 grant assertions. Run in the SQL Editor after 20260909020000.
-- SET ROLE app_authz must be proven while connected as app_runtime
-- (backend/scripts/prove_spike1.py). A superuser SQL Editor session can
-- still SET ROLE and is not a valid proof.

DO $$
BEGIN
  IF has_function_privilege(
    'anon',
    'public.app_has_active_membership(uuid,uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.app_has_active_membership(uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon/authenticated must not EXECUTE app_has_active_membership';
  END IF;
  IF NOT has_function_privilege(
    'app_runtime',
    'public.app_has_active_membership(uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'app_runtime must EXECUTE app_has_active_membership';
  END IF;
  IF has_function_privilege(
    'anon',
    'public.app_authorize_membership(uuid,uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.app_authorize_membership(uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon/authenticated must not EXECUTE app_authorize_membership';
  END IF;
  IF NOT has_function_privilege(
    'app_runtime',
    'public.app_authorize_membership(uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'app_runtime must EXECUTE app_authorize_membership';
  END IF;
END
$$;
