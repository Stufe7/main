-- Phase 1A helper allow-list and grant assertions.

DO $$
DECLARE
  definer_count integer;
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
    'public.app_has_active_membership(uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'app_runtime must EXECUTE app_has_active_membership';
  END IF;

  SELECT count(*)
  INTO definer_count
  FROM pg_proc
  JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
  WHERE pg_namespace.nspname = 'public'
    AND pg_proc.prosecdef
    AND pg_proc.proname NOT IN (
      'app_has_active_membership',
      'app_authorize_membership',
      'app_user_entity_last_admin_guard',
      'app_ensure_user',
      'app_record_consent',
      'app_provision_self_serve',
      'app_create_registration_request',
      'app_approve_registration',
      'app_reject_registration',
      'app_is_platform_admin',
      'hook_before_user_created'
    );
  IF definer_count <> 0 THEN
    RAISE EXCEPTION 'unexpected SECURITY DEFINER functions in public';
  END IF;
END
$$;
