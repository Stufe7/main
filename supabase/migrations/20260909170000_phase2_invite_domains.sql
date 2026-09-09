-- Phase 2 remaining: invitations and domain-addition requests.
-- Helpers are SECURITY DEFINER; callers must set_config JWT claims first.

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
  IF invite_id IS NOT NULL THEN
    RETURN invite_id;
  END IF;

  INSERT INTO public.user_invitation (
    entity_id, email, role, status, invited_by_user_id, expires_at
  ) VALUES (
    p_entity, normalized, p_role, 'Pending', p_user, now() + interval '14 days'
  )
  RETURNING id INTO invite_id;
  RETURN invite_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_accept_invitation(
  p_user uuid,
  p_invitation uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  inv public.user_invitation%ROWTYPE;
  user_email text;
  existing_status text;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'invitation cannot be accepted';
  END IF;

  SELECT email INTO user_email FROM public.app_user WHERE id = p_user;
  SELECT * INTO inv FROM public.user_invitation WHERE id = p_invitation FOR UPDATE;
  IF NOT FOUND
     OR user_email IS NULL
     OR lower(user_email) IS DISTINCT FROM lower(inv.email)
     OR inv.status <> 'Pending'
     OR inv.expires_at < now() THEN
    RAISE EXCEPTION 'invitation cannot be accepted';
  END IF;

  SELECT status INTO existing_status
  FROM public.user_entity
  WHERE user_id = p_user AND entity_id = inv.entity_id;

  IF existing_status = 'removed' THEN
    RAISE EXCEPTION 'invitation cannot be accepted';
  END IF;

  INSERT INTO public.user_entity (user_id, entity_id, role, status, invited_by_user_id)
  VALUES (p_user, inv.entity_id, inv.role, 'active', inv.invited_by_user_id)
  ON CONFLICT (user_id, entity_id) DO UPDATE
    SET role = excluded.role,
        status = 'active',
        updated_at = now()
    WHERE public.user_entity.status <> 'removed';

  UPDATE public.user_invitation
  SET status = 'Accepted',
      accepted_by_user_id = p_user,
      accepted_at = now(),
      updated_at = now()
  WHERE id = p_invitation;

  RETURN inv.entity_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_request_domain_addition(
  p_user uuid,
  p_entity uuid,
  p_domain text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  normalized text;
  request_id uuid;
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
  normalized := lower(btrim(p_domain));
  IF normalized LIKE '%@%' OR normalized = '' OR position('.' IN normalized) = 0 THEN
    RAISE EXCEPTION 'invalid domain';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.entity_domain
    WHERE entity_id = p_entity AND domain = normalized AND status = 'Approved'
  ) THEN
    RAISE EXCEPTION 'domain is already approved';
  END IF;

  SELECT id INTO request_id
  FROM public.entity_change_request
  WHERE entity_id = p_entity
    AND request_type = 'Domain Addition'
    AND status = 'Pending'
    AND payload = jsonb_build_object('domain', normalized);
  IF request_id IS NOT NULL THEN
    RETURN request_id;
  END IF;

  INSERT INTO public.entity_change_request (
    entity_id, request_type, requested_by_user_id, payload, status
  ) VALUES (
    p_entity, 'Domain Addition', p_user, jsonb_build_object('domain', normalized), 'Pending'
  )
  RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_approve_domain_addition(
  p_request uuid,
  p_admin_user uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  req public.entity_change_request%ROWTYPE;
  domain text;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_admin_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT public.app_is_platform_admin(p_admin_user) THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;
  SELECT * INTO req FROM public.entity_change_request WHERE id = p_request FOR UPDATE;
  IF NOT FOUND OR req.request_type <> 'Domain Addition' THEN
    RAISE EXCEPTION 'request not found';
  END IF;
  IF req.status = 'Approved' THEN
    RETURN;
  END IF;
  IF req.status <> 'Pending' THEN
    RAISE EXCEPTION 'request is not pending';
  END IF;
  domain := lower(req.payload ->> 'domain');
  INSERT INTO public.entity_domain (
    entity_id, domain, status, is_primary, added_via, approved_at, approved_by_platform_admin_id
  ) VALUES (
    req.entity_id, domain, 'Approved', false, 'Domain Addition Request', now(),
    (SELECT id FROM public.platform_admin WHERE user_id = p_admin_user AND status = 'Active')
  )
  ON CONFLICT (entity_id, domain) DO UPDATE
    SET status = 'Approved',
        added_via = 'Domain Addition Request',
        approved_at = now(),
        updated_at = now();

  UPDATE public.entity_change_request
  SET status = 'Approved',
      reviewed_at = now(),
      reviewed_by_platform_admin_id = (
        SELECT id FROM public.platform_admin WHERE user_id = p_admin_user AND status = 'Active'
      ),
      updated_at = now()
  WHERE id = p_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_reject_domain_addition(
  p_request uuid,
  p_admin_user uuid,
  p_feedback text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_admin_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT public.app_is_platform_admin(p_admin_user) THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;
  IF p_feedback IS NULL OR btrim(p_feedback) = '' THEN
    RAISE EXCEPTION 'requester_feedback is required';
  END IF;
  UPDATE public.entity_change_request
  SET status = 'Rejected',
      requester_feedback = p_feedback,
      reviewed_at = now(),
      reviewed_by_platform_admin_id = (
        SELECT id FROM public.platform_admin WHERE user_id = p_admin_user AND status = 'Active'
      ),
      updated_at = now()
  WHERE id = p_request AND request_type = 'Domain Addition' AND status = 'Pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request is not pending';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_list_pending_domain_requests(p_user uuid)
RETURNS TABLE (
  id uuid,
  entity_id uuid,
  entity_name text,
  domain text,
  created_at timestamptz
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
  IF NOT public.app_is_platform_admin(p_user) THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;
  RETURN QUERY
  SELECT r.id, r.entity_id, e.entity_name, r.payload ->> 'domain', r.created_at
  FROM public.entity_change_request r
  JOIN public.entity e ON e.id = r.entity_id
  WHERE r.request_type = 'Domain Addition' AND r.status = 'Pending'
  ORDER BY r.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.app_invite_colleague(uuid, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_accept_invitation(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_request_domain_addition(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_approve_domain_addition(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_reject_domain_addition(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_list_pending_domain_requests(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.app_invite_colleague(uuid, uuid, text, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_accept_invitation(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_request_domain_addition(uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_approve_domain_addition(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_reject_domain_addition(uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_list_pending_domain_requests(uuid) TO app_runtime;

CREATE OR REPLACE FUNCTION public.app_list_members(
  p_user uuid,
  p_entity uuid
) RETURNS TABLE (
  user_id uuid,
  email text,
  first_name text,
  last_name text,
  role text,
  status text
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
  IF NOT EXISTS (
    SELECT 1 FROM public.user_entity ue
    WHERE ue.user_id = p_user AND ue.entity_id = p_entity AND ue.status = 'active'
  ) THEN
    RAISE EXCEPTION 'no access to this entity';
  END IF;
  RETURN QUERY
  SELECT ue.user_id, u.email, u.first_name, u.last_name, ue.role, ue.status
  FROM public.user_entity ue
  JOIN public.app_user u ON u.id = ue.user_id
  WHERE ue.entity_id = p_entity AND ue.status = 'active'
  ORDER BY u.email;
END;
$$;

REVOKE ALL ON FUNCTION public.app_list_members(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_list_members(uuid, uuid) TO app_runtime;
