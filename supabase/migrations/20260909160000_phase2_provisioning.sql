-- Phase 2: allow-listed provisioning helpers. Called by app_runtime after JWT
-- set_config. Do not call auth.uid(). Paste in SQL Editor if GitHub has not applied.

CREATE OR REPLACE FUNCTION public.app_claim_sub()
RETURNS uuid
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $$
  SELECT (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
$$;

CREATE OR REPLACE FUNCTION public.app_ensure_user(
  p_user uuid,
  p_email text,
  p_first_name text,
  p_last_name text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  INSERT INTO public.app_user (id, email, first_name, last_name, status, last_login)
  VALUES (p_user, lower(p_email), p_first_name, p_last_name, 'active', now())
  ON CONFLICT (id) DO UPDATE
    SET email = excluded.email,
        first_name = COALESCE(excluded.first_name, public.app_user.first_name),
        last_name = COALESCE(excluded.last_name, public.app_user.last_name),
        status = 'active',
        last_login = now(),
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.app_record_consent(
  p_user uuid,
  p_consent_type text,
  p_document_version text,
  p_source text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  INSERT INTO public.user_consent (
    user_id, consent_type, document_version, accepted_at, source
  ) VALUES (
    p_user, p_consent_type, p_document_version, now(), p_source
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.app_provision_self_serve(
  p_user uuid,
  p_provisioning_key text,
  p_entity_name text,
  p_country text,
  p_website text,
  p_timezone text,
  p_email_domain text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  existing uuid;
  new_entity uuid;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;

  SELECT entity_id INTO existing
  FROM public.self_serve_provisioning
  WHERE provisioning_key = p_provisioning_key
    AND status = 'Provisioned'
    AND entity_id IS NOT NULL;
  IF existing IS NOT NULL THEN
    RETURN existing;
  END IF;

  INSERT INTO public.entity (
    entity_name, country, website, reference_timezone, digest_send_local_time, status
  ) VALUES (
    p_entity_name, p_country, p_website, p_timezone, '08:00:00', 'Active'
  )
  RETURNING id INTO new_entity;

  INSERT INTO public.entity_domain (
    entity_id, domain, status, is_primary, added_via, approved_at
  ) VALUES (
    new_entity, lower(p_email_domain), 'Approved', true, 'Signup', now()
  );

  INSERT INTO public.user_entity (user_id, entity_id, role, status)
  VALUES (p_user, new_entity, 'Entity Admin', 'active');

  INSERT INTO public.self_serve_provisioning (
    user_id, entity_id, provisioning_key, status, verified_at
  ) VALUES (
    p_user, new_entity, p_provisioning_key, 'Provisioned', now()
  )
  ON CONFLICT (provisioning_key) DO UPDATE
    SET entity_id = excluded.entity_id,
        status = 'Provisioned',
        updated_at = now();

  RETURN new_entity;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_create_registration_request(
  p_user uuid,
  p_first_name text,
  p_last_name text,
  p_work_email text,
  p_email_domain text,
  p_company_name text,
  p_company_url text,
  p_website_domain text,
  p_country text,
  p_timezone text,
  p_reason_code text,
  p_summary text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  existing uuid;
  created uuid;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;

  SELECT id INTO existing
  FROM public.registration_request
  WHERE user_id = p_user AND status = 'Pending Review';
  IF existing IS NOT NULL THEN
    RETURN existing;
  END IF;

  INSERT INTO public.registration_request (
    user_id, first_name, last_name, work_email, email_domain, company_name,
    company_url, website_domain, country, reference_timezone,
    verification_status, verification_reason_code, verification_summary, status
  ) VALUES (
    p_user, p_first_name, p_last_name, lower(p_work_email), lower(p_email_domain),
    p_company_name, p_company_url, p_website_domain, p_country, p_timezone,
    'Review Required', p_reason_code, p_summary, 'Pending Review'
  )
  RETURNING id INTO created;
  RETURN created;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_approve_registration(
  p_request uuid,
  p_admin_user uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  req public.registration_request%ROWTYPE;
  entity uuid;
  admin_ok boolean;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_admin_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM public.platform_admin pa
    WHERE pa.user_id = p_admin_user AND pa.status = 'Active'
  ) INTO admin_ok;
  IF NOT admin_ok THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;

  SELECT * INTO req FROM public.registration_request WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'registration request not found';
  END IF;
  IF req.status = 'Approved' THEN
    RETURN (
      SELECT entity_id FROM public.self_serve_provisioning
      WHERE user_id = req.user_id AND entity_id IS NOT NULL
      ORDER BY created_at DESC LIMIT 1
    );
  END IF;
  IF req.status <> 'Pending Review' THEN
    RAISE EXCEPTION 'request is not pending';
  END IF;

  INSERT INTO public.entity (
    entity_name, country, website, reference_timezone, digest_send_local_time, status
  ) VALUES (
    req.company_name, req.country, req.company_url, req.reference_timezone, '08:00:00', 'Active'
  )
  RETURNING id INTO entity;

  INSERT INTO public.entity_domain (
    entity_id, domain, status, is_primary, added_via, approved_at
  ) VALUES (
    entity, req.email_domain, 'Approved', true, 'Registration Approval', now()
  );

  INSERT INTO public.user_entity (user_id, entity_id, role, status)
  VALUES (req.user_id, entity, 'Entity Admin', 'active')
  ON CONFLICT (user_id, entity_id) DO UPDATE
    SET status = 'active', role = 'Entity Admin', updated_at = now();

  UPDATE public.registration_request
  SET status = 'Approved',
      reviewed_at = now(),
      reviewed_by_platform_admin_id = (
        SELECT id FROM public.platform_admin
        WHERE user_id = p_admin_user AND status = 'Active'
      ),
      updated_at = now()
  WHERE id = p_request;

  RETURN entity;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_reject_registration(
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
  IF NOT EXISTS (
    SELECT 1 FROM public.platform_admin
    WHERE user_id = p_admin_user AND status = 'Active'
  ) THEN
    RAISE EXCEPTION 'not a platform admin';
  END IF;
  IF p_feedback IS NULL OR btrim(p_feedback) = '' THEN
    RAISE EXCEPTION 'applicant_feedback is required';
  END IF;
  UPDATE public.registration_request
  SET status = 'Rejected',
      applicant_feedback = p_feedback,
      reviewed_at = now(),
      reviewed_by_platform_admin_id = (
        SELECT id FROM public.platform_admin
        WHERE user_id = p_admin_user AND status = 'Active'
      ),
      updated_at = now()
  WHERE id = p_request AND status = 'Pending Review';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request is not pending';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.app_ensure_user(uuid, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_record_consent(uuid, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_provision_self_serve(uuid, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_create_registration_request(uuid, text, text, text, text, text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_approve_registration(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_reject_registration(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.app_ensure_user(uuid, text, text, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_record_consent(uuid, text, text, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_provision_self_serve(uuid, text, text, text, text, text, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_create_registration_request(uuid, text, text, text, text, text, text, text, text, text, text, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_approve_registration(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_reject_registration(uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_claim_sub() TO app_runtime;

CREATE OR REPLACE FUNCTION public.app_is_platform_admin(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.platform_admin
    WHERE user_id = p_user AND status = 'Active'
  );
$$;

REVOKE ALL ON FUNCTION public.app_is_platform_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_is_platform_admin(uuid) TO app_runtime;

GRANT SELECT ON public.platform_admin TO app_runtime;

DROP POLICY IF EXISTS registration_request_platform ON public.registration_request;
CREATE POLICY registration_request_platform ON public.registration_request
  FOR ALL TO app_runtime
  USING (public.app_is_platform_admin(public.app_claim_sub()))
  WITH CHECK (public.app_is_platform_admin(public.app_claim_sub()));
