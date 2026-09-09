-- Phase 7: verified global email change (all-or-nothing across memberships).

CREATE TABLE public.user_email_change (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.app_user (id),
  old_email text NOT NULL,
  new_email text NOT NULL,
  status text NOT NULL CHECK (status IN ('Pending', 'Confirmed', 'Failed')),
  detail text,
  created_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz
);

CREATE INDEX user_email_change_user_id_idx ON public.user_email_change (user_id, created_at DESC);

ALTER TABLE public.user_email_change ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_email_change FORCE ROW LEVEL SECURITY;

CREATE POLICY user_email_change_self
  ON public.user_email_change
  FOR SELECT
  TO app_runtime
  USING (user_id = public.app_claim_sub());

REVOKE ALL ON public.user_email_change FROM PUBLIC;
GRANT SELECT ON public.user_email_change TO app_runtime;

CREATE OR REPLACE FUNCTION public.app_email_change_precheck(p_user uuid, p_new_email text)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  normalized text;
  email_domain text;
  rec record;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  normalized := lower(btrim(p_new_email));
  IF normalized IS NULL OR position('@' IN normalized) = 0 THEN
    RAISE EXCEPTION 'invalid email';
  END IF;
  email_domain := split_part(normalized, '@', 2);
  IF email_domain = '' OR position('.' IN email_domain) = 0 THEN
    RAISE EXCEPTION 'invalid email';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.app_user u
    WHERE lower(u.email) = normalized AND u.id <> p_user
  ) THEN
    RAISE EXCEPTION 'email belongs to another account; contact support@stufe7.com';
  END IF;
  FOR rec IN
    SELECT e.id AS entity_id, e.entity_name
    FROM public.user_entity ue
    JOIN public.entity e ON e.id = ue.entity_id
    WHERE ue.user_id = p_user AND ue.status IN ('active', 'inactive')
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.entity_domain d
      WHERE d.entity_id = rec.entity_id
        AND d.status = 'Approved'
        AND d.domain = email_domain
    ) THEN
      RAISE EXCEPTION 'new email domain is not an approved domain for %', rec.entity_name;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_email_change_start(p_user uuid, p_new_email text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  normalized text;
  old_email text;
  change_id uuid;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  PERFORM public.app_email_change_precheck(p_user, p_new_email);
  SELECT u.email INTO old_email FROM public.app_user u WHERE u.id = p_user;
  IF old_email IS NULL THEN
    RAISE EXCEPTION 'user not found';
  END IF;
  normalized := lower(btrim(p_new_email));
  IF lower(old_email) = normalized THEN
    RAISE EXCEPTION 'email is unchanged';
  END IF;
  INSERT INTO public.user_email_change (user_id, old_email, new_email, status)
  VALUES (p_user, old_email, normalized, 'Pending')
  RETURNING id INTO change_id;
  RETURN change_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_email_change_commit(p_user uuid, p_new_email text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  normalized text;
  old_email text;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  normalized := lower(btrim(p_new_email));
  SELECT u.email INTO old_email FROM public.app_user u WHERE u.id = p_user FOR UPDATE;
  IF old_email IS NULL THEN
    RAISE EXCEPTION 'user not found';
  END IF;
  IF lower(old_email) = normalized THEN
    RETURN normalized;
  END IF;
  BEGIN
    PERFORM public.app_email_change_precheck(p_user, normalized);
  EXCEPTION
    WHEN OTHERS THEN
      INSERT INTO public.user_email_change (user_id, old_email, new_email, status, detail)
      VALUES (p_user, old_email, normalized, 'Failed', SQLERRM);
      RAISE;
  END;
  BEGIN
    UPDATE public.app_user
    SET email = normalized, updated_at = now()
    WHERE id = p_user;
  EXCEPTION
    WHEN unique_violation THEN
      INSERT INTO public.user_email_change (user_id, old_email, new_email, status, detail)
      VALUES (
        p_user, old_email, normalized, 'Failed',
        'email belongs to another account; contact support@stufe7.com'
      );
      RAISE EXCEPTION 'email belongs to another account; contact support@stufe7.com';
  END;
  UPDATE public.user_invitation
  SET status = 'Revoked', updated_at = now()
  WHERE status = 'Pending' AND lower(email) = lower(old_email);
  UPDATE public.user_email_change
  SET status = 'Confirmed', confirmed_at = now()
  WHERE user_id = p_user AND new_email = normalized AND status = 'Pending';
  IF NOT FOUND THEN
    INSERT INTO public.user_email_change (
      user_id, old_email, new_email, status, confirmed_at
    ) VALUES (
      p_user, old_email, normalized, 'Confirmed', now()
    );
  END IF;
  RETURN normalized;
END;
$$;

REVOKE ALL ON FUNCTION public.app_email_change_precheck(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_email_change_start(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_email_change_commit(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_email_change_precheck(uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_email_change_start(uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_email_change_commit(uuid, text) TO app_runtime;
