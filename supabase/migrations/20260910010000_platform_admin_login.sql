-- Sole platform login: admin@stufe7.com. OTP still goes through Auth.
-- Creates the Auth user if missing, then app_user + operator rows.

DO $$
DECLARE
  v_user uuid;
BEGIN
  SELECT id INTO v_user
  FROM auth.users
  WHERE lower(email) = 'admin@stufe7.com'
  LIMIT 1;

  IF v_user IS NULL THEN
    v_user := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      recovery_token,
      email_change_token_new,
      email_change,
      email_change_token_current,
      reauthentication_token,
      is_sso_user,
      is_anonymous
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_user,
      'authenticated',
      'authenticated',
      'admin@stufe7.com',
      extensions.crypt(encode(extensions.gen_random_bytes(16), 'hex'), extensions.gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"first_name":"Platform","last_name":"Admin"}'::jsonb,
      now(),
      now(),
      '',
      '',
      '',
      '',
      '',
      '',
      false,
      false
    );
  END IF;

  INSERT INTO auth.identities (
    id,
    user_id,
    provider_id,
    provider,
    identity_data,
    last_sign_in_at,
    created_at,
    updated_at
  )
  SELECT
    gen_random_uuid(),
    v_user,
    v_user::text,
    'email',
    jsonb_build_object(
      'sub', v_user::text,
      'email', 'admin@stufe7.com',
      'email_verified', true,
      'phone_verified', false
    ),
    now(),
    now(),
    now()
  WHERE NOT EXISTS (
    SELECT 1 FROM auth.identities
    WHERE user_id = v_user AND provider = 'email'
  );

  INSERT INTO public.app_user (
    id, email, first_name, last_name, status, last_login, timezone
  ) VALUES (
    v_user, 'admin@stufe7.com', 'Platform', 'Admin', 'active', now(), 'UTC'
  )
  ON CONFLICT (id) DO UPDATE
    SET email = excluded.email,
        status = 'active',
        updated_at = now();

  INSERT INTO public.platform_admin (user_id, status, created_by)
  VALUES (v_user, 'Active', 'seed-admin@stufe7.com')
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'Active',
        updated_at = now();

  INSERT INTO public.privacy_operator (user_id, status, created_by)
  VALUES (v_user, 'Active', 'seed-admin@stufe7.com')
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'Active',
        updated_at = now();
END
$$;

CREATE OR REPLACE FUNCTION public.app_bootstrap_platform_operator(p_user uuid, p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF lower(btrim(p_email)) IS DISTINCT FROM 'admin@stufe7.com' THEN
    RETURN;
  END IF;

  INSERT INTO public.app_user (
    id, email, first_name, last_name, status, last_login, timezone
  ) VALUES (
    p_user, 'admin@stufe7.com', 'Platform', 'Admin', 'active', now(), 'UTC'
  )
  ON CONFLICT (id) DO UPDATE
    SET email = excluded.email,
        status = 'active',
        last_login = now(),
        updated_at = now();

  INSERT INTO public.platform_admin (user_id, status, created_by)
  VALUES (p_user, 'Active', 'bootstrap-admin@stufe7.com')
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'Active',
        updated_at = now();

  INSERT INTO public.privacy_operator (user_id, status, created_by)
  VALUES (p_user, 'Active', 'bootstrap-admin@stufe7.com')
  ON CONFLICT (user_id) DO UPDATE
    SET status = 'Active',
        updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.app_bootstrap_platform_operator(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_bootstrap_platform_operator(uuid, text) TO app_runtime;
