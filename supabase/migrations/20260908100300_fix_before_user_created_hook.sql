-- Auth calls this hook outside a transaction block, so a function-level
-- SET search_path (SET LOCAL) fails. PL/pgSQL variable `domain` also
-- clashed with domain_deny_list.domain.

CREATE OR REPLACE FUNCTION public.hook_before_user_created(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_email text;
  v_domain text;
  v_allow_hit boolean;
  v_deny_hit boolean;
BEGIN
  v_email := lower(btrim(event->'user'->>'email'));
  IF v_email IS NULL OR position('@' IN v_email) < 2 THEN
    RETURN jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message', 'A company email address is required.'
      )
    );
  END IF;

  v_domain := split_part(v_email, '@', 2);

  SELECT EXISTS (
    SELECT 1 FROM public.domain_deny_list AS deny_row
    WHERE deny_row.domain = v_domain AND deny_row.kind = 'operator_allow'
  ) INTO v_allow_hit;

  IF v_allow_hit THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.domain_deny_list AS deny_row
    WHERE deny_row.domain = v_domain AND deny_row.kind IN ('operator_block', 'source_deny')
  ) INTO v_deny_hit;

  IF v_deny_hit THEN
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
