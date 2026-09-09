-- Phase 6: remaining ENTITY_CHANGE_REQUEST types, weekly stats read, deny health.

CREATE OR REPLACE FUNCTION public.app_domain_is_denied(p_domain text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.domain_deny_list d
    WHERE d.domain = lower(btrim(p_domain))
      AND d.kind IN ('operator_block', 'source_deny')
  ) AND NOT EXISTS (
    SELECT 1 FROM public.domain_deny_list d
    WHERE d.domain = lower(btrim(p_domain))
      AND d.kind = 'operator_allow'
  );
$$;

CREATE OR REPLACE FUNCTION public.app_domain_has_attached_users(p_entity uuid, p_domain text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_entity ue
    JOIN public.app_user u ON u.id = ue.user_id
    WHERE ue.entity_id = p_entity
      AND ue.status IN ('active', 'inactive')
      AND split_part(lower(u.email), '@', 2) = lower(btrim(p_domain))
  ) OR EXISTS (
    SELECT 1
    FROM public.user_invitation ui
    WHERE ui.entity_id = p_entity
      AND ui.status = 'Pending'
      AND split_part(lower(ui.email), '@', 2) = lower(btrim(p_domain))
  );
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
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  normalized := lower(btrim(p_domain));
  IF normalized LIKE '%@%' OR normalized = '' OR position('.' IN normalized) = 0 THEN
    RAISE EXCEPTION 'invalid domain';
  END IF;
  IF public.app_domain_is_denied(normalized) THEN
    RAISE EXCEPTION 'domain is not allowed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.entity_domain
    WHERE entity_id = p_entity AND domain = normalized AND status = 'Approved'
  ) THEN
    RAISE EXCEPTION 'domain is already approved';
  END IF;
  SELECT r.id INTO request_id
  FROM public.entity_change_request r
  WHERE r.entity_id = p_entity
    AND r.request_type = 'Domain Addition'
    AND r.status = 'Pending'
    AND r.payload ->> 'domain' = normalized;
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
  IF public.app_domain_is_denied(domain) THEN
    RAISE EXCEPTION 'domain is not allowed';
  END IF;
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

CREATE OR REPLACE FUNCTION public.app_request_domain_removal(
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
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  normalized := lower(btrim(p_domain));
  IF NOT EXISTS (
    SELECT 1 FROM public.entity_domain d
    WHERE d.entity_id = p_entity AND d.domain = normalized AND d.status = 'Approved'
  ) THEN
    RAISE EXCEPTION 'domain is not an approved domain';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.entity_domain d
    WHERE d.entity_id = p_entity AND d.domain = normalized AND d.is_primary
  ) THEN
    RAISE EXCEPTION 'primary domain cannot be removed';
  END IF;
  IF public.app_domain_has_attached_users(p_entity, normalized) THEN
    RAISE EXCEPTION 'domain still has memberships or pending invitations';
  END IF;
  SELECT r.id INTO request_id
  FROM public.entity_change_request r
  WHERE r.entity_id = p_entity
    AND r.request_type = 'Domain Removal'
    AND r.status = 'Pending'
    AND r.payload ->> 'domain' = normalized;
  IF request_id IS NOT NULL THEN
    RETURN request_id;
  END IF;
  INSERT INTO public.entity_change_request (
    entity_id, request_type, requested_by_user_id, payload, status
  ) VALUES (
    p_entity, 'Domain Removal', p_user, jsonb_build_object('domain', normalized), 'Pending'
  )
  RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_approve_domain_removal(
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
  IF NOT FOUND OR req.request_type <> 'Domain Removal' THEN
    RAISE EXCEPTION 'request not found';
  END IF;
  IF req.status = 'Approved' THEN
    RETURN;
  END IF;
  IF req.status <> 'Pending' THEN
    RAISE EXCEPTION 'request is not pending';
  END IF;
  domain := lower(req.payload ->> 'domain');
  IF EXISTS (
    SELECT 1 FROM public.entity_domain d
    WHERE d.entity_id = req.entity_id AND d.domain = domain AND d.is_primary
  ) THEN
    RAISE EXCEPTION 'primary domain cannot be removed';
  END IF;
  IF public.app_domain_has_attached_users(req.entity_id, domain) THEN
    RAISE EXCEPTION 'domain still has memberships or pending invitations';
  END IF;
  UPDATE public.entity_domain
  SET status = 'Revoked',
      is_primary = false,
      updated_at = now()
  WHERE entity_id = req.entity_id AND domain = domain AND status = 'Approved';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'domain is not an approved domain';
  END IF;
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

CREATE OR REPLACE FUNCTION public.app_request_domain_primary(
  p_user uuid,
  p_entity uuid,
  p_to_domain text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  normalized text;
  from_domain text;
  request_id uuid;
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  normalized := lower(btrim(p_to_domain));
  SELECT d.domain INTO from_domain
  FROM public.entity_domain d
  WHERE d.entity_id = p_entity AND d.status = 'Approved' AND d.is_primary;
  IF from_domain IS NULL THEN
    RAISE EXCEPTION 'entity has no primary domain';
  END IF;
  IF from_domain = normalized THEN
    RAISE EXCEPTION 'domain is already primary';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.entity_domain d
    WHERE d.entity_id = p_entity AND d.domain = normalized AND d.status = 'Approved'
  ) THEN
    RAISE EXCEPTION 'replacement must be an approved domain';
  END IF;
  SELECT r.id INTO request_id
  FROM public.entity_change_request r
  WHERE r.entity_id = p_entity
    AND r.request_type = 'Domain Primary Transfer'
    AND r.status = 'Pending'
    AND r.payload ->> 'to_domain' = normalized;
  IF request_id IS NOT NULL THEN
    RETURN request_id;
  END IF;
  INSERT INTO public.entity_change_request (
    entity_id, request_type, requested_by_user_id, payload, status
  ) VALUES (
    p_entity, 'Domain Primary Transfer', p_user,
    jsonb_build_object('from_domain', from_domain, 'to_domain', normalized),
    'Pending'
  )
  RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_approve_domain_primary(
  p_request uuid,
  p_admin_user uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  req public.entity_change_request%ROWTYPE;
  to_domain text;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_admin_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT public.app_is_platform_admin(p_admin_user) THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;
  SELECT * INTO req FROM public.entity_change_request WHERE id = p_request FOR UPDATE;
  IF NOT FOUND OR req.request_type <> 'Domain Primary Transfer' THEN
    RAISE EXCEPTION 'request not found';
  END IF;
  IF req.status = 'Approved' THEN
    RETURN;
  END IF;
  IF req.status <> 'Pending' THEN
    RAISE EXCEPTION 'request is not pending';
  END IF;
  to_domain := lower(req.payload ->> 'to_domain');
  IF NOT EXISTS (
    SELECT 1 FROM public.entity_domain d
    WHERE d.entity_id = req.entity_id AND d.domain = to_domain AND d.status = 'Approved'
  ) THEN
    RAISE EXCEPTION 'replacement must be an approved domain';
  END IF;
  UPDATE public.entity_domain
  SET is_primary = false, updated_at = now()
  WHERE entity_id = req.entity_id AND status = 'Approved' AND is_primary;
  UPDATE public.entity_domain
  SET is_primary = true, updated_at = now()
  WHERE entity_id = req.entity_id AND domain = to_domain AND status = 'Approved';
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

CREATE OR REPLACE FUNCTION public.app_request_entity_rename(
  p_user uuid,
  p_entity uuid,
  p_entity_name text,
  p_legal_name text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  new_name text;
  legal text;
  request_id uuid;
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  new_name := btrim(p_entity_name);
  legal := NULLIF(btrim(COALESCE(p_legal_name, '')), '');
  IF new_name IS NULL OR new_name = '' THEN
    RAISE EXCEPTION 'entity name is required';
  END IF;
  SELECT r.id INTO request_id
  FROM public.entity_change_request r
  WHERE r.entity_id = p_entity
    AND r.request_type = 'Entity Rename'
    AND r.status = 'Pending';
  IF request_id IS NOT NULL THEN
    RETURN request_id;
  END IF;
  INSERT INTO public.entity_change_request (
    entity_id, request_type, requested_by_user_id, payload, status
  ) VALUES (
    p_entity, 'Entity Rename', p_user,
    jsonb_strip_nulls(jsonb_build_object('entity_name', new_name, 'legal_name', legal)),
    'Pending'
  )
  RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_approve_entity_rename(
  p_request uuid,
  p_admin_user uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  req public.entity_change_request%ROWTYPE;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_admin_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT public.app_is_platform_admin(p_admin_user) THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;
  SELECT * INTO req FROM public.entity_change_request WHERE id = p_request FOR UPDATE;
  IF NOT FOUND OR req.request_type <> 'Entity Rename' THEN
    RAISE EXCEPTION 'request not found';
  END IF;
  IF req.status = 'Approved' THEN
    RETURN;
  END IF;
  IF req.status <> 'Pending' THEN
    RAISE EXCEPTION 'request is not pending';
  END IF;
  UPDATE public.entity
  SET entity_name = COALESCE(NULLIF(btrim(req.payload ->> 'entity_name'), ''), entity_name),
      legal_name = CASE
        WHEN req.payload ? 'legal_name' THEN NULLIF(btrim(req.payload ->> 'legal_name'), '')
        ELSE legal_name
      END,
      updated_at = now()
  WHERE id = req.entity_id;
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

CREATE OR REPLACE FUNCTION public.app_reject_change_request(
  p_request uuid,
  p_admin_user uuid,
  p_feedback text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  req public.entity_change_request%ROWTYPE;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_admin_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT public.app_is_platform_admin(p_admin_user) THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;
  SELECT * INTO req FROM public.entity_change_request WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request not found';
  END IF;
  IF req.status = 'Rejected' THEN
    RETURN;
  END IF;
  IF req.status <> 'Pending' THEN
    RAISE EXCEPTION 'request is not pending';
  END IF;
  IF req.request_type IN ('Domain Addition', 'Domain Removal')
     AND (p_feedback IS NULL OR btrim(p_feedback) = '') THEN
    RAISE EXCEPTION 'requester_feedback is required';
  END IF;
  UPDATE public.entity_change_request
  SET status = 'Rejected',
      requester_feedback = NULLIF(btrim(COALESCE(p_feedback, '')), ''),
      reviewed_at = now(),
      reviewed_by_platform_admin_id = (
        SELECT id FROM public.platform_admin WHERE user_id = p_admin_user AND status = 'Active'
      ),
      updated_at = now()
  WHERE id = p_request;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_list_pending_change_requests(p_user uuid)
RETURNS TABLE (
  req_id uuid,
  req_type text,
  req_entity_id uuid,
  req_entity_name text,
  req_summary text,
  req_created_at timestamptz
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
  SELECT
    r.id,
    r.request_type,
    r.entity_id,
    e.entity_name,
    CASE r.request_type
      WHEN 'Domain Addition' THEN r.payload ->> 'domain'
      WHEN 'Domain Removal' THEN r.payload ->> 'domain'
      WHEN 'Domain Primary Transfer' THEN
        coalesce(r.payload ->> 'from_domain', '') || ' → ' || coalesce(r.payload ->> 'to_domain', '')
      WHEN 'Entity Rename' THEN coalesce(r.payload ->> 'entity_name', '')
      ELSE r.payload::text
    END,
    r.created_at
  FROM public.entity_change_request r
  JOIN public.entity e ON e.id = r.entity_id
  WHERE r.status = 'Pending'
  ORDER BY r.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_change_request_requester_email(p_request uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT u.email
  FROM public.entity_change_request r
  JOIN public.app_user u ON u.id = r.requested_by_user_id
  WHERE r.id = p_request
    AND public.app_is_platform_admin(public.app_claim_sub())
$$;

CREATE OR REPLACE FUNCTION public.app_platform_weekly_stats(p_user uuid)
RETURNS TABLE (
  stat_week_start date,
  stat_new_users integer,
  stat_new_entities integer,
  stat_active_entities integer,
  stat_active_users integer,
  stat_actions_created integer,
  stat_from_rollup boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  week_monday date;
  i integer;
  week_start_ts timestamptz;
  week_end timestamptz;
  n_users integer;
  n_entities integer;
  n_active_entities integer;
  n_active_users integer;
  n_actions integer;
  roll public.platform_weekly_stat%ROWTYPE;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT public.app_is_platform_admin(p_user) THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;
  week_monday := date_trunc('week', timezone('UTC', now()))::date;
  FOR i IN 0..11 LOOP
    SELECT * INTO roll
    FROM public.platform_weekly_stat s
    WHERE s.week_start = week_monday - (i * 7);
    IF FOUND THEN
      stat_week_start := roll.week_start;
      stat_new_users := roll.new_users;
      stat_new_entities := roll.new_entities;
      stat_active_entities := roll.active_entities;
      stat_active_users := roll.active_users;
      stat_actions_created := roll.actions_created;
      stat_from_rollup := true;
      RETURN NEXT;
    ELSE
      week_start_ts := (week_monday - (i * 7))::timestamp AT TIME ZONE 'UTC';
      week_end := week_start_ts + interval '7 days';
      SELECT count(*) INTO n_users
      FROM public.app_user u
      WHERE u.created_at >= week_start_ts AND u.created_at < week_end;
      SELECT count(*) INTO n_entities
      FROM public.entity e
      WHERE e.created_at >= week_start_ts AND e.created_at < week_end;
      SELECT count(DISTINCT ue.entity_id) INTO n_active_entities
      FROM public.user_entity ue
      WHERE ue.last_accessed_at >= week_start_ts AND ue.last_accessed_at < week_end;
      SELECT count(DISTINCT ue.user_id) INTO n_active_users
      FROM public.user_entity ue
      WHERE ue.last_accessed_at >= week_start_ts AND ue.last_accessed_at < week_end;
      SELECT count(*) INTO n_actions
      FROM public.action x
      WHERE x.created_at >= week_start_ts AND x.created_at < week_end;
      stat_week_start := week_monday - (i * 7);
      stat_new_users := n_users;
      stat_new_entities := n_entities;
      stat_active_entities := n_active_entities;
      stat_active_users := n_active_users;
      stat_actions_created := n_actions;
      stat_from_rollup := false;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_platform_deny_health(p_user uuid)
RETURNS TABLE (
  health_refreshed_at timestamptz,
  health_status text,
  health_source_version text,
  health_entry_count integer,
  health_error_summary text
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
  SELECT r.refreshed_at, r.status, r.source_version, r.entry_count, r.error_summary
  FROM public.domain_deny_refresh r
  ORDER BY r.refreshed_at DESC
  LIMIT 1;
END;
$$;

DROP FUNCTION IF EXISTS public.app_entity_settings(uuid, uuid);

CREATE OR REPLACE FUNCTION public.app_entity_settings(p_user uuid, p_entity uuid)
RETURNS TABLE (
  settings_entity_name text,
  settings_country text,
  settings_timezone text,
  settings_digest_hour time,
  settings_digest_frequency text,
  settings_legal_name text,
  settings_plan_code text,
  settings_plan_status text
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
    ue.digest_frequency,
    e.legal_name,
    e.plan_code,
    e.plan_status
  FROM public.entity e
  JOIN public.user_entity ue ON ue.entity_id = e.id AND ue.user_id = p_user
  WHERE e.id = p_entity AND ue.status = 'active';
END;
$$;

REVOKE ALL ON FUNCTION public.app_domain_is_denied(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_domain_has_attached_users(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_request_domain_removal(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_approve_domain_removal(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_request_domain_primary(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_approve_domain_primary(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_request_entity_rename(uuid, uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_approve_entity_rename(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_reject_change_request(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_list_pending_change_requests(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_change_request_requester_email(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_platform_weekly_stats(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_platform_deny_health(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_entity_settings(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.app_domain_is_denied(text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_domain_has_attached_users(uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_request_domain_addition(uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_approve_domain_addition(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_request_domain_removal(uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_approve_domain_removal(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_request_domain_primary(uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_approve_domain_primary(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_request_entity_rename(uuid, uuid, text, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_approve_entity_rename(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_reject_change_request(uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_list_pending_change_requests(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_change_request_requester_email(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_platform_weekly_stats(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_platform_deny_health(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_entity_settings(uuid, uuid) TO app_runtime;

CREATE OR REPLACE FUNCTION public.app_approve_change_request(
  p_request uuid,
  p_admin_user uuid
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  req_type text;
BEGIN
  SELECT r.request_type INTO req_type
  FROM public.entity_change_request r
  WHERE r.id = p_request;
  IF req_type IS NULL THEN
    RAISE EXCEPTION 'request not found';
  END IF;
  IF req_type = 'Domain Addition' THEN
    PERFORM public.app_approve_domain_addition(p_request, p_admin_user);
  ELSIF req_type = 'Domain Removal' THEN
    PERFORM public.app_approve_domain_removal(p_request, p_admin_user);
  ELSIF req_type = 'Domain Primary Transfer' THEN
    PERFORM public.app_approve_domain_primary(p_request, p_admin_user);
  ELSIF req_type = 'Entity Rename' THEN
    PERFORM public.app_approve_entity_rename(p_request, p_admin_user);
  ELSE
    RAISE EXCEPTION 'unsupported request type';
  END IF;
  RETURN req_type;
END;
$$;

REVOKE ALL ON FUNCTION public.app_approve_change_request(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_approve_change_request(uuid, uuid) TO app_runtime;
