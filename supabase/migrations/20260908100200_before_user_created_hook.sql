-- Spike 2: Before User Created. Postgres function (preferred over HTTP).
-- Rejects free/consumer operator_block and source_deny domains. operator_allow wins.

CREATE OR REPLACE FUNCTION public.hook_before_user_created(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  email text;
  domain text;
  allow_hit boolean;
  deny_hit boolean;
BEGIN
  email := lower(btrim(event->'user'->>'email'));
  IF email IS NULL OR position('@' IN email) < 2 THEN
    RETURN jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message', 'A company email address is required.'
      )
    );
  END IF;

  domain := split_part(email, '@', 2);

  SELECT EXISTS (
    SELECT 1 FROM public.domain_deny_list d
    WHERE d.domain = domain AND d.kind = 'operator_allow'
  ) INTO allow_hit;

  IF allow_hit THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.domain_deny_list d
    WHERE d.domain = domain AND d.kind IN ('operator_block', 'source_deny')
  ) INTO deny_hit;

  IF deny_hit THEN
    RETURN jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message', 'Use a company email address. Personal or disposable providers are not accepted.'
      )
    );
  END IF;

  RETURN '{}'::jsonb;
END;
$$;

REVOKE ALL ON FUNCTION public.hook_before_user_created(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hook_before_user_created(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.hook_before_user_created(jsonb) FROM anon, authenticated;
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
