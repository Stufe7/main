-- Invited colleagues must already exist in Auth so OTP login works
-- (signups are disabled; shouldCreateUser=false refuses unknown emails).

CREATE OR REPLACE FUNCTION public.app_ensure_auth_login(p_email text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, auth
AS $$
DECLARE
  v_email text;
  v_user uuid;
BEGIN
  v_email := lower(btrim(p_email));
  IF v_email IS NULL OR position('@' IN v_email) < 2 THEN
    RAISE EXCEPTION 'invalid email';
  END IF;

  SELECT id INTO v_user
  FROM auth.users
  WHERE lower(email) = v_email
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
      v_email,
      extensions.crypt(encode(extensions.gen_random_bytes(16), 'hex'), extensions.gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
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
      'email', v_email,
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

  RETURN v_user;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_invitation_preview(p_invitation uuid)
RETURNS TABLE (
  email text,
  role text,
  status text,
  entity_name text,
  expires_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT i.email, i.role, i.status, e.entity_name, i.expires_at
  FROM public.user_invitation i
  JOIN public.entity e ON e.id = i.entity_id
  WHERE i.id = p_invitation
    AND i.status = 'Pending'
    AND i.expires_at >= now()
$$;

CREATE OR REPLACE FUNCTION public.app_invite_colleague(
  p_user uuid,
  p_entity uuid,
  p_email text,
  p_role text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  invite_id uuid;
  normalized text;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_entity
    WHERE user_id = p_user AND entity_id = p_entity
      AND status = 'active' AND role = 'Entity Admin'
  ) THEN
    RAISE EXCEPTION 'not an Entity Admin';
  END IF;
  normalized := lower(btrim(p_email));
  IF normalized !~ '^[^@]+@[^@]+\.[^@]+$' THEN
    RAISE EXCEPTION 'invalid email';
  END IF;
  IF p_role NOT IN ('Entity Admin', 'Manager', 'User') THEN
    RAISE EXCEPTION 'invalid role';
  END IF;

  SELECT id INTO invite_id
  FROM public.user_invitation
  WHERE entity_id = p_entity
    AND lower(email) = normalized
    AND status = 'Pending';
  IF invite_id IS NULL THEN
    INSERT INTO public.user_invitation (
      entity_id, email, role, status, invited_by_user_id, expires_at
    ) VALUES (
      p_entity, normalized, p_role, 'Pending', p_user, now() + interval '14 days'
    )
    RETURNING id INTO invite_id;
  END IF;

  PERFORM public.app_ensure_auth_login(normalized);
  RETURN invite_id;
END;
$$;

REVOKE ALL ON FUNCTION public.app_ensure_auth_login(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_invitation_preview(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_ensure_auth_login(text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_invitation_preview(uuid) TO app_runtime;

SELECT public.app_ensure_auth_login(i.email)
FROM public.user_invitation i
WHERE i.status = 'Pending' AND i.expires_at >= now()
GROUP BY i.email;
