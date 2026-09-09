-- Phase 5: privileged job helpers, digest prefs, privacy-operator path.
-- Job functions are not granted to app_runtime. Call them without SET ROLE.

CREATE OR REPLACE FUNCTION public.app_job_held(p_type text, p_subject uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.legal_hold hold
    WHERE hold.subject_type = p_type
      AND hold.subject_id = p_subject
      AND hold.released_at IS NULL
      AND (hold.held_until IS NULL OR hold.held_until > now())
  );
$$;

CREATE OR REPLACE FUNCTION public.app_job_close_ended_campaigns()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  cancelled_n integer := 0;
  completed_n integer := 0;
BEGIN
  UPDATE public.action x
  SET status = 'Cancelled',
      cancelled_at = COALESCE(x.cancelled_at, now()),
      cancellation_reason = COALESCE(NULLIF(x.cancellation_reason, ''), 'Campaign ended'),
      updated_at = now()
  FROM public.campaign cam
  JOIN public.entity e ON e.id = cam.entity_id
  WHERE x.campaign_id = cam.id
    AND x.entity_id = cam.entity_id
    AND x.status = 'Open'
    AND (timezone(e.reference_timezone, now()))::date > cam.end_date;
  GET DIAGNOSTICS cancelled_n = ROW_COUNT;

  UPDATE public.campaign cam
  SET status = 'Completed',
      updated_at = now()
  FROM public.entity e
  WHERE e.id = cam.entity_id
    AND cam.status IN ('Planned', 'Active')
    AND (timezone(e.reference_timezone, now()))::date > cam.end_date;
  GET DIAGNOSTICS completed_n = ROW_COUNT;

  RETURN jsonb_build_object(
    'cancelled_actions', cancelled_n,
    'completed_campaigns', completed_n
  );
END;
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
    e.reference_timezone,
    ue.digest_frequency,
    (timezone(e.reference_timezone, now()))::date
  FROM public.user_entity ue
  JOIN public.entity e ON e.id = ue.entity_id
  JOIN public.app_user u ON u.id = ue.user_id
  WHERE ue.status = 'active'
    AND e.status = 'Active'
    AND u.status = 'active'
    AND ue.digest_frequency IN ('Daily', 'Weekly', 'Monthly')
    AND EXTRACT(HOUR FROM timezone(e.reference_timezone, now()))
        >= EXTRACT(HOUR FROM e.digest_send_local_time)
    AND ue.digest_last_sent_date IS DISTINCT FROM (timezone(e.reference_timezone, now()))::date
    AND (
      ue.digest_frequency = 'Daily'
      OR (
        ue.digest_frequency = 'Weekly'
        AND EXTRACT(ISODOW FROM (timezone(e.reference_timezone, now()))::date) = 1
      )
      OR (
        ue.digest_frequency = 'Monthly'
        AND EXTRACT(DAY FROM (timezone(e.reference_timezone, now()))::date) = 1
      )
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.app_job_digest_actions(
  p_user uuid,
  p_entity uuid,
  p_frequency text,
  p_today date
)
RETURNS TABLE (
  act_company_name text,
  act_action_type text,
  act_description text,
  act_due_date date,
  act_due_time time,
  act_bucket text,
  act_company_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  horizon date;
BEGIN
  horizon := CASE p_frequency
    WHEN 'Daily' THEN p_today
    WHEN 'Weekly' THEN p_today + ((7 - EXTRACT(ISODOW FROM p_today))::integer)
    WHEN 'Monthly' THEN (date_trunc('month', p_today::timestamp) + interval '1 month - 1 day')::date
    ELSE p_today
  END;
  RETURN QUERY
  SELECT
    co.company_name,
    x.action_type,
    x.description,
    x.due_date,
    x.due_time,
    CASE WHEN x.due_date < p_today THEN 'Overdue' ELSE 'Upcoming' END,
    x.company_id
  FROM public.action x
  JOIN public.company co ON co.id = x.company_id AND co.entity_id = x.entity_id
  WHERE x.entity_id = p_entity
    AND x.owner_user_id = p_user
    AND x.status = 'Open'
    AND x.due_date IS NOT NULL
    AND (
      x.due_date < p_today
      OR (x.due_date >= p_today AND x.due_date <= horizon)
    )
  ORDER BY
    CASE WHEN x.due_date < p_today THEN 0 ELSE 1 END,
    x.due_date,
    x.due_time NULLS LAST;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_job_mark_digest_sent(
  p_user uuid,
  p_entity uuid,
  p_local_date date
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  UPDATE public.user_entity
  SET digest_last_sent_date = p_local_date,
      updated_at = now()
  WHERE user_id = p_user
    AND entity_id = p_entity
    AND digest_last_sent_date IS DISTINCT FROM p_local_date;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_job_upsert_weekly_stat()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  week_monday date;
  week_end timestamptz;
  week_start_ts timestamptz;
  n_users integer;
  n_entities integer;
  n_active_entities integer;
  n_active_users integer;
  n_actions integer;
BEGIN
  week_monday := date_trunc('week', timezone('UTC', now()))::date;
  week_start_ts := week_monday::timestamp AT TIME ZONE 'UTC';
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

  INSERT INTO public.platform_weekly_stat (
    week_start, new_users, new_entities, active_entities, active_users,
    actions_created, computed_at
  ) VALUES (
    week_monday, n_users, n_entities, n_active_entities, n_active_users,
    n_actions, now()
  )
  ON CONFLICT (week_start) DO UPDATE
    SET new_users = EXCLUDED.new_users,
        new_entities = EXCLUDED.new_entities,
        active_entities = EXCLUDED.active_entities,
        active_users = EXCLUDED.active_users,
        actions_created = EXCLUDED.actions_created,
        computed_at = now();

  RETURN jsonb_build_object(
    'week_start', week_monday,
    'new_users', n_users,
    'new_entities', n_entities,
    'active_entities', n_active_entities,
    'active_users', n_active_users,
    'actions_created', n_actions
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.app_job_replace_source_deny(
  p_domains text[],
  p_source_version text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  kept integer;
BEGIN
  IF p_domains IS NULL OR cardinality(p_domains) = 0 THEN
    RAISE EXCEPTION 'source deny list is empty';
  END IF;

  DELETE FROM public.domain_deny_list d
  WHERE d.kind = 'source_deny'
    AND d.domain <> ALL (p_domains);

  INSERT INTO public.domain_deny_list (domain, kind, source, updated_at)
  SELECT lower(btrim(d)), 'source_deny', COALESCE(p_source_version, 'disposable-email-domains'), now()
  FROM unnest(p_domains) AS d
  WHERE btrim(d) <> ''
  ON CONFLICT (domain) DO UPDATE
    SET source = EXCLUDED.source,
        updated_at = now()
    WHERE public.domain_deny_list.kind = 'source_deny';

  INSERT INTO public.domain_deny_refresh (
    status, source_version, entry_count, error_summary
  ) VALUES (
    'Success', p_source_version, cardinality(p_domains), NULL
  );

  SELECT count(*) INTO kept
  FROM public.domain_deny_list
  WHERE kind = 'source_deny';
  RETURN kept;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_job_deny_refresh_failed(p_error text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  INSERT INTO public.domain_deny_refresh (
    status, source_version, entry_count, error_summary
  ) VALUES (
    'FailedKeptLastGood', NULL, NULL, left(COALESCE(p_error, 'refresh failed'), 500)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.app_job_deny_refresh_stale()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.domain_deny_refresh r
    WHERE r.status = 'Success'
      AND r.refreshed_at > now() - interval '7 days'
  );
$$;

CREATE OR REPLACE FUNCTION public.app_anonymize_registration_row(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  UPDATE public.registration_request
  SET first_name = NULL,
      last_name = NULL,
      work_email = 'anonymized@invalid',
      company_url = NULL,
      website_domain = NULL,
      verification_summary = NULL,
      review_note = NULL,
      applicant_feedback = COALESCE(applicant_feedback, 'anonymized'),
      updated_at = now()
  WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_job_retain_registrations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  rejected_n integer := 0;
  abandoned_n integer := 0;
  skipped_n integer := 0;
  rec record;
  orphans uuid[] := ARRAY[]::uuid[];
BEGIN
  FOR rec IN
    SELECT rr.id, rr.user_id
    FROM public.registration_request rr
    WHERE rr.status = 'Rejected'
      AND rr.reviewed_at IS NOT NULL
      AND rr.reviewed_at < now() - interval '90 days'
      AND rr.work_email IS DISTINCT FROM 'anonymized@invalid'
  LOOP
    IF public.app_job_held('REGISTRATION_REQUEST', rec.id)
       OR public.app_job_held('USER', rec.user_id)
       OR public.app_job_held('AUTH_IDENTITY', rec.user_id) THEN
      skipped_n := skipped_n + 1;
      CONTINUE;
    END IF;
    PERFORM public.app_anonymize_registration_row(rec.id);
    rejected_n := rejected_n + 1;
    IF NOT EXISTS (
      SELECT 1 FROM public.user_entity ue WHERE ue.user_id = rec.user_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.user_invitation ui
      WHERE ui.accepted_by_user_id = rec.user_id
    ) THEN
      orphans := array_append(orphans, rec.user_id);
    END IF;
  END LOOP;

  FOR rec IN
    SELECT u.id AS user_id
    FROM public.app_user u
    WHERE u.created_at < now() - interval '30 days'
      AND NOT EXISTS (
        SELECT 1 FROM public.user_entity ue WHERE ue.user_id = u.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.registration_request rr
        WHERE rr.user_id = u.id AND rr.status = 'Pending Review'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.registration_request rr
        WHERE rr.user_id = u.id
          AND rr.status = 'Rejected'
          AND rr.reviewed_at >= now() - interval '90 days'
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.user_invitation ui
        WHERE ui.accepted_by_user_id = u.id OR (
          ui.email = u.email AND ui.status = 'Pending'
        )
      )
  LOOP
    IF public.app_job_held('USER', rec.user_id)
       OR public.app_job_held('AUTH_IDENTITY', rec.user_id) THEN
      skipped_n := skipped_n + 1;
      CONTINUE;
    END IF;
    UPDATE public.app_user
    SET email = 'abandoned-' || rec.user_id::text || '@anonymized.invalid',
        first_name = NULL,
        last_name = NULL,
        status = 'disabled',
        updated_at = now()
    WHERE id = rec.user_id
      AND email NOT LIKE '%@anonymized.invalid';
    abandoned_n := abandoned_n + 1;
    orphans := array_append(orphans, rec.user_id);
  END LOOP;

  RETURN jsonb_build_object(
    'rejected_anonymized', rejected_n,
    'abandoned_anonymized', abandoned_n,
    'skipped_holds', skipped_n,
    'orphan_user_ids', to_jsonb(orphans)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.app_is_privacy_operator(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.privacy_operator po
    WHERE po.user_id = p_user AND po.status = 'Active'
  );
$$;

CREATE OR REPLACE FUNCTION public.app_privacy_list(p_user uuid)
RETURNS TABLE (
  req_id uuid,
  req_subject_type text,
  req_subject_id uuid,
  req_entity_id uuid,
  req_status text,
  req_legal_basis text,
  req_requested_at timestamptz,
  req_executed_at timestamptz
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
  IF NOT public.app_is_privacy_operator(p_user) THEN
    RAISE EXCEPTION 'not a privacy operator';
  END IF;
  RETURN QUERY
  SELECT
    pr.id, pr.subject_type, pr.subject_id, pr.entity_id, pr.status,
    pr.legal_basis, pr.requested_at, pr.executed_at
  FROM public.privacy_request pr
  ORDER BY pr.requested_at DESC
  LIMIT 200;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_privacy_execute(
  p_user uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_entity_id uuid,
  p_legal_basis text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  operator_row public.privacy_operator%ROWTYPE;
  request_id uuid;
  contact_row public.contact%ROWTYPE;
  user_row public.app_user%ROWTYPE;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  SELECT * INTO operator_row
  FROM public.privacy_operator po
  WHERE po.user_id = p_user AND po.status = 'Active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not a privacy operator';
  END IF;
  IF p_legal_basis IS NULL OR btrim(p_legal_basis) = '' THEN
    RAISE EXCEPTION 'legal basis is required';
  END IF;

  IF p_subject_type = 'CONTACT' THEN
    IF p_entity_id IS NULL THEN
      RAISE EXCEPTION 'entity is required for contact erasure';
    END IF;
    IF public.app_job_held('CONTACT', p_subject_id) THEN
      RAISE EXCEPTION 'subject is on legal hold';
    END IF;
    SELECT * INTO contact_row
    FROM public.contact c
    WHERE c.id = p_subject_id AND c.entity_id = p_entity_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'contact not found';
    END IF;
    UPDATE public.contact
    SET first_name = 'Former',
        last_name = 'Contact',
        job_title = NULL,
        telephone = NULL,
        mobile = NULL,
        email = NULL,
        linkedin_url = NULL,
        notes = NULL,
        updated_at = now()
    WHERE id = p_subject_id AND entity_id = p_entity_id;
    UPDATE public.activity
    SET subject = '[redacted]',
        description = '[redacted]',
        outcome = CASE WHEN outcome IS NULL THEN NULL ELSE '[redacted]' END,
        updated_by_user_id = p_user,
        updated_at = now()
    WHERE entity_id = p_entity_id AND contact_id = p_subject_id;
    UPDATE public.activity_revision
    SET subject = '[redacted]',
        description = '[redacted]',
        outcome = CASE WHEN outcome IS NULL THEN NULL ELSE '[redacted]' END
    WHERE entity_id = p_entity_id
      AND activity_id IN (
        SELECT a.id FROM public.activity a
        WHERE a.entity_id = p_entity_id AND a.contact_id = p_subject_id
      );

  ELSIF p_subject_type = 'USER' THEN
    IF public.app_job_held('USER', p_subject_id)
       OR public.app_job_held('AUTH_IDENTITY', p_subject_id) THEN
      RAISE EXCEPTION 'subject is on legal hold';
    END IF;
    SELECT * INTO user_row FROM public.app_user u WHERE u.id = p_subject_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'user not found';
    END IF;
    UPDATE public.app_user
    SET first_name = 'Former',
        last_name = 'User',
        email = 'former-' || p_subject_id::text || '@anonymized.invalid',
        status = 'disabled',
        updated_at = now()
    WHERE id = p_subject_id;

  ELSIF p_subject_type = 'REGISTRATION_REQUEST' THEN
    IF public.app_job_held('REGISTRATION_REQUEST', p_subject_id) THEN
      RAISE EXCEPTION 'subject is on legal hold';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.registration_request rr WHERE rr.id = p_subject_id
    ) THEN
      RAISE EXCEPTION 'registration request not found';
    END IF;
    PERFORM public.app_anonymize_registration_row(p_subject_id);

  ELSE
    RAISE EXCEPTION 'unsupported subject type';
  END IF;

  INSERT INTO public.privacy_request (
    subject_type, subject_id, entity_id, status, legal_basis,
    executed_at, executed_by_privacy_operator_id
  ) VALUES (
    p_subject_type, p_subject_id, p_entity_id, 'Executed', btrim(p_legal_basis),
    now(), operator_row.id
  )
  RETURNING id INTO request_id;
  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_set_digest_frequency(
  p_user uuid,
  p_entity uuid,
  p_frequency text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF p_frequency NOT IN ('Off', 'Daily', 'Weekly', 'Monthly') THEN
    RAISE EXCEPTION 'invalid digest frequency';
  END IF;
  IF NOT public.app_has_active_membership(p_user, p_entity) THEN
    RAISE EXCEPTION 'no access to this entity';
  END IF;
  UPDATE public.user_entity
  SET digest_frequency = p_frequency,
      updated_at = now()
  WHERE user_id = p_user AND entity_id = p_entity AND status = 'active';
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
  SELECT e.entity_name, e.country, e.reference_timezone, e.digest_send_local_time, ue.digest_frequency
  FROM public.entity e
  JOIN public.user_entity ue ON ue.entity_id = e.id AND ue.user_id = p_user
  WHERE e.id = p_entity AND ue.status = 'active';
END;
$$;

CREATE OR REPLACE FUNCTION public.app_update_entity_general(
  p_user uuid,
  p_entity uuid,
  p_timezone text,
  p_digest_time time
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  IF p_timezone IS NULL OR btrim(p_timezone) = '' THEN
    RAISE EXCEPTION 'timezone is required';
  END IF;
  PERFORM timezone(p_timezone, now());
  IF EXTRACT(MINUTE FROM p_digest_time) <> 0 OR EXTRACT(SECOND FROM p_digest_time) <> 0 THEN
    RAISE EXCEPTION 'digest send time must be a whole hour';
  END IF;
  UPDATE public.entity
  SET reference_timezone = p_timezone,
      digest_send_local_time = p_digest_time,
      updated_at = now()
  WHERE id = p_entity;
END;
$$;

REVOKE ALL ON FUNCTION public.app_job_held(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_close_ended_campaigns() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_digest_due() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_digest_actions(uuid, uuid, text, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_mark_digest_sent(uuid, uuid, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_upsert_weekly_stat() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_replace_source_deny(text[], text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_deny_refresh_failed(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_deny_refresh_stale() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_anonymize_registration_row(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_job_retain_registrations() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_is_privacy_operator(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_privacy_list(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_privacy_execute(uuid, text, uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_set_digest_frequency(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_entity_settings(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_update_entity_general(uuid, uuid, text, time) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.app_is_privacy_operator(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_privacy_list(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_privacy_execute(uuid, text, uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_set_digest_frequency(uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_entity_settings(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_update_entity_general(uuid, uuid, text, time) TO app_runtime;

GRANT EXECUTE ON FUNCTION public.app_job_held(text, uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_close_ended_campaigns() TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_digest_due() TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_digest_actions(uuid, uuid, text, date) TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_mark_digest_sent(uuid, uuid, date) TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_upsert_weekly_stat() TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_replace_source_deny(text[], text) TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_deny_refresh_failed(text) TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_deny_refresh_stale() TO postgres;
GRANT EXECUTE ON FUNCTION public.app_anonymize_registration_row(uuid) TO postgres;
GRANT EXECUTE ON FUNCTION public.app_job_retain_registrations() TO postgres;
