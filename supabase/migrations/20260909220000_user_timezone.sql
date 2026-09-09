-- Digest, Home, and user prefs use USER.timezone. Campaign end dates stay on ENTITY.

ALTER TABLE public.app_user
  ADD COLUMN IF NOT EXISTS timezone text;

UPDATE public.app_user u
SET timezone = src.reference_timezone
FROM (
  SELECT DISTINCT ON (ue.user_id)
    ue.user_id,
    e.reference_timezone
  FROM public.user_entity ue
  JOIN public.entity e ON e.id = ue.entity_id
  WHERE e.reference_timezone IS NOT NULL
    AND btrim(e.reference_timezone) <> ''
  ORDER BY ue.user_id,
    CASE ue.status WHEN 'active' THEN 0 WHEN 'inactive' THEN 1 ELSE 2 END,
    ue.last_accessed_at DESC NULLS LAST,
    ue.created_at
) src
WHERE u.id = src.user_id
  AND (u.timezone IS NULL OR btrim(u.timezone) = '');

UPDATE public.app_user
SET timezone = 'UTC'
WHERE timezone IS NULL OR btrim(timezone) = '';

ALTER TABLE public.app_user
  ALTER COLUMN timezone SET DEFAULT 'UTC',
  ALTER COLUMN timezone SET NOT NULL;

CREATE OR REPLACE FUNCTION public.app_user_timezone(p_user uuid, p_entity uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT COALESCE(
    NULLIF(btrim(u.timezone), ''),
    NULLIF(btrim(e.reference_timezone), ''),
    'UTC'
  )
  FROM public.app_user u
  LEFT JOIN public.entity e ON e.id = p_entity
  WHERE u.id = p_user
$$;

CREATE OR REPLACE FUNCTION public.app_job_digest_due()
RETURNS TABLE (
  due_user_id uuid,
  due_email text,
  due_entity_id uuid,
  due_entity_name text,
  due_timezone text,
  due_frequency text,
  due_local_date date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ue.user_id,
    u.email,
    e.id,
    e.entity_name,
    public.app_user_timezone(u.id, e.id),
    ue.digest_frequency,
    (timezone(public.app_user_timezone(u.id, e.id), now()))::date
  FROM public.user_entity ue
  JOIN public.entity e ON e.id = ue.entity_id
  JOIN public.app_user u ON u.id = ue.user_id
  WHERE ue.status = 'active'
    AND e.status = 'Active'
    AND u.status = 'active'
    AND ue.digest_frequency IN ('Daily', 'Weekly', 'Monthly')
    AND EXTRACT(HOUR FROM timezone(public.app_user_timezone(u.id, e.id), now()))
        >= EXTRACT(HOUR FROM e.digest_send_local_time)
    AND ue.digest_last_sent_date
        IS DISTINCT FROM (timezone(public.app_user_timezone(u.id, e.id), now()))::date
    AND (
      ue.digest_frequency = 'Daily'
      OR (
        ue.digest_frequency = 'Weekly'
        AND EXTRACT(ISODOW FROM (timezone(public.app_user_timezone(u.id, e.id), now()))::date) = 1
      )
      OR (
        ue.digest_frequency = 'Monthly'
        AND EXTRACT(DAY FROM (timezone(public.app_user_timezone(u.id, e.id), now()))::date) = 1
      )
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.app_set_user_timezone(p_user uuid, p_timezone text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF p_timezone IS NULL OR btrim(p_timezone) = '' THEN
    RAISE EXCEPTION 'timezone is required';
  END IF;
  PERFORM timezone(p_timezone, now());
  UPDATE public.app_user
  SET timezone = btrim(p_timezone),
      updated_at = now()
  WHERE id = p_user;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_entity_settings(p_user uuid, p_entity uuid)
RETURNS TABLE (
  settings_entity_name text,
  settings_country text,
  settings_timezone text,
  settings_digest_hour time,
  settings_digest_frequency text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT public.app_has_active_membership(p_user, p_entity) THEN
    RAISE EXCEPTION 'no access to this entity';
  END IF;
  RETURN QUERY
  SELECT
    e.entity_name,
    e.country,
    public.app_user_timezone(p_user, e.id),
    e.digest_send_local_time,
    ue.digest_frequency
  FROM public.entity e
  JOIN public.user_entity ue ON ue.entity_id = e.id AND ue.user_id = p_user
  WHERE e.id = p_entity AND ue.status = 'active';
END;
$$;

DROP FUNCTION IF EXISTS public.app_update_entity_general(uuid, uuid, text, time);

CREATE OR REPLACE FUNCTION public.app_update_entity_general(
  p_user uuid,
  p_entity uuid,
  p_digest_time time
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  IF EXTRACT(MINUTE FROM p_digest_time) <> 0 OR EXTRACT(SECOND FROM p_digest_time) <> 0 THEN
    RAISE EXCEPTION 'digest send time must be a whole hour';
  END IF;
  UPDATE public.entity
  SET digest_send_local_time = p_digest_time,
      updated_at = now()
  WHERE id = p_entity;
END;
$$;

DROP FUNCTION IF EXISTS public.app_ensure_user(uuid, text, text, text);

CREATE OR REPLACE FUNCTION public.app_ensure_user(
  p_user uuid,
  p_email text,
  p_first_name text,
  p_last_name text,
  p_timezone text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  INSERT INTO public.app_user (
    id, email, first_name, last_name, status, last_login, timezone
  )
  VALUES (
    p_user,
    lower(p_email),
    p_first_name,
    p_last_name,
    'active',
    now(),
    COALESCE(NULLIF(btrim(p_timezone), ''), 'UTC')
  )
  ON CONFLICT (id) DO UPDATE
    SET email = excluded.email,
        first_name = COALESCE(excluded.first_name, public.app_user.first_name),
        last_name = COALESCE(excluded.last_name, public.app_user.last_name),
        status = 'active',
        last_login = now(),
        timezone = CASE
          WHEN NULLIF(btrim(p_timezone), '') IS NULL THEN public.app_user.timezone
          ELSE btrim(p_timezone)
        END,
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.app_seed_invite_timezone(p_user uuid, p_entity uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  UPDATE public.app_user u
  SET timezone = e.reference_timezone,
      updated_at = now()
  FROM public.entity e
  WHERE u.id = p_user
    AND e.id = p_entity
    AND u.timezone = 'UTC'
    AND e.reference_timezone IS DISTINCT FROM 'UTC'
    AND u.created_at > now() - interval '5 minutes';
END;
$$;
REVOKE ALL ON FUNCTION public.app_user_timezone(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_set_user_timezone(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_seed_invite_timezone(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_update_entity_general(uuid, uuid, time) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_ensure_user(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.app_user_timezone(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_set_user_timezone(uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_seed_invite_timezone(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_update_entity_general(uuid, uuid, time) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_ensure_user(uuid, text, text, text, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_job_digest_due() TO postgres;
