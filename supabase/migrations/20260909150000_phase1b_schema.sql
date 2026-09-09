-- Phase 1B complete schema (spec 15 remaining, 11, 17.1–17.2, 18.1, 19).
-- Paste entire file in SQL Editor if GitHub has not applied it. No SET ROLE.
-- Policies use spec 17 claim-read. Do not call auth.uid().

ALTER TABLE public.company
  ADD COLUMN IF NOT EXISTS legal_name text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS country text,
  ADD COLUMN IF NOT EXISTS website text,
  ADD COLUMN IF NOT EXISTS telephone text,
  ADD COLUMN IF NOT EXISTS nature_of_business text,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS last_activity_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_activity_id uuid,
  ADD COLUMN IF NOT EXISTS next_action_id uuid,
  ADD COLUMN IF NOT EXISTS next_action_due_date date,
  ADD COLUMN IF NOT EXISTS projections_updated_at timestamptz;

ALTER TABLE public.contact
  ADD COLUMN IF NOT EXISTS job_title text,
  ADD COLUMN IF NOT EXISTS telephone text,
  ADD COLUMN IF NOT EXISTS mobile text,
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS linkedin_url text,
  ADD COLUMN IF NOT EXISTS notes text,
  ADD COLUMN IF NOT EXISTS last_activity_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_activity_id uuid,
  ADD COLUMN IF NOT EXISTS next_action_id uuid,
  ADD COLUMN IF NOT EXISTS next_action_due_date date,
  ADD COLUMN IF NOT EXISTS projections_updated_at timestamptz;

CREATE TABLE public.campaign (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  name text NOT NULL,
  description text,
  owner_user_id uuid NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL CHECK (status IN ('Planned', 'Active', 'Completed', 'Cancelled')),
  record_state text NOT NULL CHECK (record_state IN ('Active', 'Archived')),
  created_by_user_id uuid,
  updated_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT campaign_dates CHECK (end_date >= start_date),
  CONSTRAINT campaign_id_entity_key UNIQUE (id, entity_id),
  CONSTRAINT campaign_owner_membership_fk
    FOREIGN KEY (owner_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT campaign_created_by_membership_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT campaign_updated_by_membership_fk
    FOREIGN KEY (updated_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE TABLE public.activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  company_id uuid NOT NULL,
  contact_id uuid,
  campaign_id uuid,
  activity_type text NOT NULL CHECK (
    activity_type IN ('Note', 'Phone Call', 'Email', 'Meeting / Visit', 'WhatsApp')
  ),
  activity_date timestamptz NOT NULL,
  subject text NOT NULL,
  description text,
  outcome text,
  source_action_id uuid,
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT activity_id_entity_key UNIQUE (id, entity_id),
  CONSTRAINT activity_company_same_tenant
    FOREIGN KEY (company_id, entity_id)
    REFERENCES public.company (id, entity_id),
  CONSTRAINT activity_contact_same_tenant
    FOREIGN KEY (contact_id, entity_id)
    REFERENCES public.contact (id, entity_id),
  CONSTRAINT activity_campaign_same_tenant
    FOREIGN KEY (campaign_id, entity_id)
    REFERENCES public.campaign (id, entity_id),
  CONSTRAINT activity_created_by_membership_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT activity_updated_by_membership_fk
    FOREIGN KEY (updated_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE TABLE public.action (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  company_id uuid NOT NULL,
  contact_id uuid,
  campaign_id uuid,
  owner_user_id uuid NOT NULL,
  action_type text NOT NULL CHECK (
    action_type IN ('Phone Call', 'Email', 'Meeting / Visit', 'WhatsApp', 'Task')
  ),
  description text NOT NULL,
  due_date date,
  due_time time,
  priority text NOT NULL DEFAULT 'Normal' CHECK (priority IN ('High', 'Normal', 'Low')),
  status text NOT NULL CHECK (status IN ('Open', 'Completed', 'Cancelled')),
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  source_activity_id uuid,
  created_by_user_id uuid,
  updated_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT action_id_entity_key UNIQUE (id, entity_id),
  CONSTRAINT action_open_due_date CHECK (status <> 'Open' OR due_date IS NOT NULL),
  CONSTRAINT action_company_same_tenant
    FOREIGN KEY (company_id, entity_id)
    REFERENCES public.company (id, entity_id),
  CONSTRAINT action_contact_same_tenant
    FOREIGN KEY (contact_id, entity_id)
    REFERENCES public.contact (id, entity_id),
  CONSTRAINT action_campaign_same_tenant
    FOREIGN KEY (campaign_id, entity_id)
    REFERENCES public.campaign (id, entity_id),
  CONSTRAINT action_owner_membership_fk
    FOREIGN KEY (owner_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT action_created_by_membership_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT action_updated_by_membership_fk
    FOREIGN KEY (updated_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

ALTER TABLE public.activity
  ADD CONSTRAINT activity_source_action_same_tenant
  FOREIGN KEY (source_action_id, entity_id)
  REFERENCES public.action (id, entity_id)
  DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.action
  ADD CONSTRAINT action_source_activity_same_tenant
  FOREIGN KEY (source_activity_id, entity_id)
  REFERENCES public.activity (id, entity_id)
  DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.company
  ADD CONSTRAINT company_last_activity_fk
  FOREIGN KEY (last_activity_id, entity_id)
  REFERENCES public.activity (id, entity_id)
  DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT company_next_action_fk
  FOREIGN KEY (next_action_id, entity_id)
  REFERENCES public.action (id, entity_id)
  DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.contact
  ADD CONSTRAINT contact_last_activity_fk
  FOREIGN KEY (last_activity_id, entity_id)
  REFERENCES public.activity (id, entity_id)
  DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT contact_next_action_fk
  FOREIGN KEY (next_action_id, entity_id)
  REFERENCES public.action (id, entity_id)
  DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE public.activity_revision (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL,
  activity_id uuid NOT NULL,
  revision_number integer NOT NULL,
  activity_type text NOT NULL,
  activity_date timestamptz NOT NULL,
  subject text NOT NULL,
  description text,
  outcome text,
  contact_id uuid,
  campaign_id uuid,
  edited_by_user_id uuid NOT NULL,
  edited_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT activity_revision_unique UNIQUE (entity_id, activity_id, revision_number),
  CONSTRAINT activity_revision_activity_fk
    FOREIGN KEY (activity_id, entity_id)
    REFERENCES public.activity (id, entity_id)
);

CREATE TABLE public.campaign_company (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL,
  campaign_id uuid NOT NULL,
  company_id uuid NOT NULL,
  status text NOT NULL CHECK (
    status IN (
      'Not Started', 'Contacted', 'Interested', 'Qualified',
      'Demo / Meeting', 'Proposal', 'Won', 'Lost', 'Not Relevant'
    )
  ),
  owner_user_id uuid,
  record_state text NOT NULL CHECK (record_state IN ('Active', 'Archived')),
  notes text,
  added_at timestamptz NOT NULL DEFAULT now(),
  removed_at timestamptz,
  created_by_user_id uuid,
  updated_by_user_id uuid,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT campaign_company_unique UNIQUE (entity_id, campaign_id, company_id),
  CONSTRAINT campaign_company_id_entity_key UNIQUE (id, entity_id),
  CONSTRAINT campaign_company_campaign_fk
    FOREIGN KEY (campaign_id, entity_id)
    REFERENCES public.campaign (id, entity_id),
  CONSTRAINT campaign_company_company_fk
    FOREIGN KEY (company_id, entity_id)
    REFERENCES public.company (id, entity_id),
  CONSTRAINT campaign_company_owner_fk
    FOREIGN KEY (owner_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT campaign_company_created_by_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT campaign_company_updated_by_fk
    FOREIGN KEY (updated_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE TABLE public.company_handover (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL,
  company_id uuid NOT NULL,
  from_user_id uuid NOT NULL,
  to_user_id uuid NOT NULL,
  reason text NOT NULL CHECK (
    reason IN ('User Deactivated', 'User Removed', 'Manual Reassignment')
  ),
  status text NOT NULL CHECK (status IN ('Pending Review', 'Reviewed')),
  created_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by_user_id uuid,
  reviewed_at timestamptz,
  CONSTRAINT company_handover_reviewed CHECK (
    (
      status = 'Pending Review'
      AND reviewed_by_user_id IS NULL
      AND reviewed_at IS NULL
    )
    OR (
      status = 'Reviewed'
      AND reviewed_by_user_id IS NOT NULL
      AND reviewed_at IS NOT NULL
    )
  ),
  CONSTRAINT company_handover_company_fk
    FOREIGN KEY (company_id, entity_id)
    REFERENCES public.company (id, entity_id),
  CONSTRAINT company_handover_from_fk
    FOREIGN KEY (from_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT company_handover_to_fk
    FOREIGN KEY (to_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT company_handover_created_by_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE TABLE public.import_job (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  filename text NOT NULL,
  status text NOT NULL CHECK (
    status IN ('Uploaded', 'Validated', 'Imported', 'Failed')
  ),
  row_count integer,
  new_company_count integer,
  possible_duplicate_count integer,
  unmatched_owner_count integer,
  invalid_row_count integer,
  created_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CONSTRAINT import_job_created_by_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE TABLE public.user_invitation (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  email text NOT NULL,
  role text NOT NULL CHECK (role IN ('Entity Admin', 'Manager', 'User')),
  status text NOT NULL CHECK (status IN ('Pending', 'Accepted', 'Expired', 'Revoked')),
  invited_by_user_id uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  accepted_by_user_id uuid,
  accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_invitation_invited_by_fk
    FOREIGN KEY (invited_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE UNIQUE INDEX user_invitation_pending_email
  ON public.user_invitation (entity_id, lower(email))
  WHERE status = 'Pending';

CREATE TABLE public.entity_change_request (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  request_type text NOT NULL CHECK (
    request_type IN (
      'Domain Addition', 'Domain Removal', 'Domain Primary Transfer', 'Entity Rename'
    )
  ),
  requested_by_user_id uuid NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL CHECK (status IN ('Pending', 'Approved', 'Rejected')),
  reviewed_by_platform_admin_id uuid,
  reviewed_at timestamptz,
  review_note text,
  requester_feedback text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT entity_change_reject_feedback CHECK (
    status <> 'Rejected'
    OR request_type NOT IN ('Domain Addition', 'Domain Removal')
    OR requester_feedback IS NOT NULL
  ),
  CONSTRAINT entity_change_requested_by_fk
    FOREIGN KEY (requested_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE UNIQUE INDEX entity_change_request_pending
  ON public.entity_change_request (entity_id, request_type, payload)
  WHERE status = 'Pending';

CREATE TABLE public.platform_admin (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES public.app_user (id),
  status text NOT NULL CHECK (status IN ('Active', 'Inactive')),
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_accessed_at timestamptz
);

CREATE TABLE public.privacy_operator (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES public.app_user (id),
  status text NOT NULL CHECK (status IN ('Active', 'Inactive')),
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.user_consent (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.app_user (id),
  consent_type text NOT NULL CHECK (consent_type IN ('Terms', 'Privacy')),
  document_version text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  source text NOT NULL CHECK (source IN ('Signup', 'Invitation', 'Reacceptance')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.self_serve_provisioning (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.app_user (id),
  entity_id uuid REFERENCES public.entity (id),
  provisioning_key text NOT NULL UNIQUE,
  status text NOT NULL CHECK (
    status IN ('Pending', 'Provisioned', 'Failed', 'Review Required')
  ),
  verified_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX self_serve_provisioning_user_entity
  ON public.self_serve_provisioning (user_id, entity_id)
  WHERE entity_id IS NOT NULL;

CREATE TABLE public.registration_request (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.app_user (id),
  first_name text,
  last_name text,
  work_email text NOT NULL,
  email_domain text NOT NULL,
  company_name text NOT NULL,
  company_url text,
  website_domain text,
  country text NOT NULL,
  reference_timezone text NOT NULL,
  verification_status text NOT NULL,
  verification_reason_code text,
  verification_summary text,
  status text NOT NULL CHECK (status IN ('Pending Review', 'Approved', 'Rejected')),
  reviewed_by_platform_admin_id uuid REFERENCES public.platform_admin (id),
  reviewed_at timestamptz,
  review_note text,
  applicant_feedback text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT registration_reject_feedback CHECK (
    status <> 'Rejected' OR applicant_feedback IS NOT NULL
  )
);

CREATE UNIQUE INDEX registration_request_pending_user
  ON public.registration_request (user_id)
  WHERE status = 'Pending Review';

CREATE TABLE public.platform_weekly_stat (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  week_start date NOT NULL UNIQUE,
  new_users integer NOT NULL DEFAULT 0,
  new_entities integer NOT NULL DEFAULT 0,
  active_entities integer NOT NULL DEFAULT 0,
  active_users integer NOT NULL DEFAULT 0,
  actions_created integer NOT NULL DEFAULT 0,
  computed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.privacy_request (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type text NOT NULL CHECK (
    subject_type IN ('CONTACT', 'USER', 'REGISTRATION_REQUEST')
  ),
  subject_id uuid NOT NULL,
  entity_id uuid REFERENCES public.entity (id),
  status text NOT NULL CHECK (
    status IN ('Requested', 'Approved', 'Executed', 'Rejected')
  ),
  legal_basis text NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  executed_at timestamptz,
  executed_by_privacy_operator_id uuid REFERENCES public.privacy_operator (id),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT privacy_request_executed CHECK (
    (
      status <> 'Executed'
      AND executed_at IS NULL
      AND executed_by_privacy_operator_id IS NULL
    )
    OR (
      status = 'Executed'
      AND executed_at IS NOT NULL
      AND executed_by_privacy_operator_id IS NOT NULL
    )
  )
);

CREATE TABLE public.legal_hold (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type text NOT NULL CHECK (
    subject_type IN ('USER', 'CONTACT', 'REGISTRATION_REQUEST', 'AUTH_IDENTITY')
  ),
  subject_id uuid NOT NULL,
  reason text NOT NULL,
  held_from timestamptz NOT NULL DEFAULT now(),
  held_until timestamptz,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz
);

CREATE INDEX activity_entity_company_date_idx
  ON public.activity (entity_id, company_id, activity_date DESC);
CREATE INDEX action_entity_open_due_idx
  ON public.action (entity_id, status, due_date, due_time);
CREATE INDEX campaign_entity_id_idx ON public.campaign (entity_id);
CREATE INDEX campaign_company_entity_idx ON public.campaign_company (entity_id);
CREATE INDEX company_handover_entity_idx ON public.company_handover (entity_id);
CREATE INDEX user_invitation_entity_idx ON public.user_invitation (entity_id);
CREATE INDEX import_job_entity_idx ON public.import_job (entity_id);

CREATE FUNCTION public.app_contact_matches_company(
  p_contact uuid,
  p_company uuid,
  p_entity uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT p_contact IS NULL
    OR EXISTS (
      SELECT 1
      FROM public.contact c
      WHERE c.id = p_contact
        AND c.entity_id = p_entity
        AND c.company_id = p_company
    );
$$;

CREATE FUNCTION public.app_activity_contact_company_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.app_contact_matches_company(NEW.contact_id, NEW.company_id, NEW.entity_id) THEN
    RAISE EXCEPTION 'ACTIVITY.contact_id must belong to ACTIVITY.company_id';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.app_action_contact_company_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT public.app_contact_matches_company(NEW.contact_id, NEW.company_id, NEW.entity_id) THEN
    RAISE EXCEPTION 'ACTION.contact_id must belong to ACTION.company_id';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER activity_contact_company
BEFORE INSERT OR UPDATE ON public.activity
FOR EACH ROW
EXECUTE FUNCTION public.app_activity_contact_company_guard();

CREATE TRIGGER action_contact_company
BEFORE INSERT OR UPDATE ON public.action
FOR EACH ROW
EXECUTE FUNCTION public.app_action_contact_company_guard();

CREATE FUNCTION public.app_action_campaign_horizon_ok()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  camp public.campaign%ROWTYPE;
BEGIN
  IF NEW.campaign_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT * INTO camp
  FROM public.campaign
  WHERE id = NEW.campaign_id AND entity_id = NEW.entity_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'campaign not found for action';
  END IF;
  IF NEW.due_date IS NOT NULL
     AND (NEW.due_date < camp.start_date OR NEW.due_date > camp.end_date) THEN
    RAISE EXCEPTION 'campaign-linked ACTION.due_date must be within campaign dates';
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER action_campaign_horizon
AFTER INSERT OR UPDATE ON public.action
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.app_action_campaign_horizon_ok();

CREATE FUNCTION public.app_refresh_company_projections(p_company uuid, p_entity uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  act public.activity%ROWTYPE;
  nxt public.action%ROWTYPE;
BEGIN
  SELECT * INTO act
  FROM public.activity
  WHERE company_id = p_company AND entity_id = p_entity
  ORDER BY activity_date DESC, created_at DESC, id DESC
  LIMIT 1;

  SELECT * INTO nxt
  FROM public.action
  WHERE company_id = p_company
    AND entity_id = p_entity
    AND status = 'Open'
  ORDER BY
    due_date ASC,
    (due_time IS NULL),
    due_time ASC,
    CASE priority WHEN 'High' THEN 0 WHEN 'Normal' THEN 1 ELSE 2 END,
    created_at ASC,
    id ASC
  LIMIT 1;

  UPDATE public.company
  SET
    last_activity_id = act.id,
    last_activity_at = act.activity_date,
    next_action_id = nxt.id,
    next_action_due_date = nxt.due_date,
    projections_updated_at = now()
  WHERE id = p_company AND entity_id = p_entity;
END;
$$;

CREATE FUNCTION public.app_refresh_contact_projections(p_contact uuid, p_entity uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  act public.activity%ROWTYPE;
  nxt public.action%ROWTYPE;
BEGIN
  IF p_contact IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO act
  FROM public.activity
  WHERE contact_id = p_contact AND entity_id = p_entity
  ORDER BY activity_date DESC, created_at DESC, id DESC
  LIMIT 1;

  SELECT * INTO nxt
  FROM public.action
  WHERE contact_id = p_contact
    AND entity_id = p_entity
    AND status = 'Open'
  ORDER BY
    due_date ASC,
    (due_time IS NULL),
    due_time ASC,
    CASE priority WHEN 'High' THEN 0 WHEN 'Normal' THEN 1 ELSE 2 END,
    created_at ASC,
    id ASC
  LIMIT 1;

  UPDATE public.contact
  SET
    last_activity_id = act.id,
    last_activity_at = act.activity_date,
    next_action_id = nxt.id,
    next_action_due_date = nxt.due_date,
    projections_updated_at = now()
  WHERE id = p_contact AND entity_id = p_entity;
END;
$$;

CREATE FUNCTION public.app_activity_projection_refresh()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.app_refresh_company_projections(OLD.company_id, OLD.entity_id);
    PERFORM public.app_refresh_contact_projections(OLD.contact_id, OLD.entity_id);
    RETURN OLD;
  END IF;
  PERFORM public.app_refresh_company_projections(NEW.company_id, NEW.entity_id);
  PERFORM public.app_refresh_contact_projections(NEW.contact_id, NEW.entity_id);
  IF TG_OP = 'UPDATE' THEN
    IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
      PERFORM public.app_refresh_company_projections(OLD.company_id, OLD.entity_id);
    END IF;
    IF NEW.contact_id IS DISTINCT FROM OLD.contact_id THEN
      PERFORM public.app_refresh_contact_projections(OLD.contact_id, OLD.entity_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.app_action_projection_refresh()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.app_refresh_company_projections(OLD.company_id, OLD.entity_id);
    PERFORM public.app_refresh_contact_projections(OLD.contact_id, OLD.entity_id);
    RETURN OLD;
  END IF;
  PERFORM public.app_refresh_company_projections(NEW.company_id, NEW.entity_id);
  PERFORM public.app_refresh_contact_projections(NEW.contact_id, NEW.entity_id);
  IF TG_OP = 'UPDATE' THEN
    IF NEW.company_id IS DISTINCT FROM OLD.company_id THEN
      PERFORM public.app_refresh_company_projections(OLD.company_id, OLD.entity_id);
    END IF;
    IF NEW.contact_id IS DISTINCT FROM OLD.contact_id THEN
      PERFORM public.app_refresh_contact_projections(OLD.contact_id, OLD.entity_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER activity_projection_refresh
AFTER INSERT OR UPDATE OR DELETE ON public.activity
FOR EACH ROW
EXECUTE FUNCTION public.app_activity_projection_refresh();

CREATE TRIGGER action_projection_refresh
AFTER INSERT OR UPDATE OR DELETE ON public.action
FOR EACH ROW
EXECUTE FUNCTION public.app_action_projection_refresh();

CREATE FUNCTION public.app_activity_revision_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  next_rev integer;
  editor uuid;
BEGIN
  editor := COALESCE(
    NEW.updated_by_user_id,
    (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
  );
  SELECT COALESCE(max(revision_number), 0) + 1
  INTO next_rev
  FROM public.activity_revision
  WHERE activity_id = OLD.id AND entity_id = OLD.entity_id;

  INSERT INTO public.activity_revision (
    entity_id, activity_id, revision_number, activity_type, activity_date,
    subject, description, outcome, contact_id, campaign_id,
    edited_by_user_id, edited_at
  ) VALUES (
    OLD.entity_id, OLD.id, next_rev, OLD.activity_type, OLD.activity_date,
    OLD.subject, OLD.description, OLD.outcome, OLD.contact_id, OLD.campaign_id,
    editor, now()
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER activity_revision_snapshot
BEFORE UPDATE ON public.activity
FOR EACH ROW
EXECUTE FUNCTION public.app_activity_revision_snapshot();

CREATE FUNCTION public.app_user_entity_last_admin_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  remaining integer;
  entity_key uuid;
  old_is_admin boolean;
  new_is_admin boolean;
BEGIN
  entity_key := COALESCE(NEW.entity_id, OLD.entity_id);
  PERFORM 1 FROM public.entity WHERE id = entity_key FOR UPDATE;
  old_is_admin := (OLD.role = 'Entity Admin' AND OLD.status = 'active');
  IF TG_OP = 'DELETE' THEN
    new_is_admin := false;
  ELSE
    new_is_admin := (NEW.role = 'Entity Admin' AND NEW.status = 'active');
  END IF;
  IF old_is_admin AND NOT new_is_admin THEN
    SELECT count(*) INTO remaining
    FROM public.user_entity
    WHERE entity_id = entity_key
      AND status = 'active'
      AND role = 'Entity Admin'
      AND id IS DISTINCT FROM OLD.id;
    IF remaining < 1 THEN
      RAISE EXCEPTION 'entity % must keep at least one active Entity Admin', entity_key;
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER user_entity_last_admin_guard
BEFORE UPDATE OR DELETE ON public.user_entity
FOR EACH ROW
EXECUTE FUNCTION public.app_user_entity_last_admin_guard();

DO $$
BEGIN
  BEGIN
    ALTER FUNCTION public.app_user_entity_last_admin_guard() OWNER TO app_authz;
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'hosted limitation: last-admin guard remains owned by %', current_user;
  END;
END
$$;

CREATE FUNCTION public.app_invitation_approved_domain()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.status = 'Pending' AND NOT EXISTS (
    SELECT 1
    FROM public.entity_domain d
    WHERE d.entity_id = NEW.entity_id
      AND d.status = 'Approved'
      AND d.domain = split_part(lower(NEW.email), '@', 2)
  ) THEN
    RAISE EXCEPTION 'invitation domain is not an Approved ENTITY_DOMAIN';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER user_invitation_approved_domain
BEFORE INSERT OR UPDATE ON public.user_invitation
FOR EACH ROW
EXECUTE FUNCTION public.app_invitation_approved_domain();

REVOKE ALL ON public.campaign FROM PUBLIC;
REVOKE ALL ON public.activity FROM PUBLIC;
REVOKE ALL ON public.action FROM PUBLIC;
REVOKE ALL ON public.activity_revision FROM PUBLIC;
REVOKE ALL ON public.campaign_company FROM PUBLIC;
REVOKE ALL ON public.company_handover FROM PUBLIC;
REVOKE ALL ON public.import_job FROM PUBLIC;
REVOKE ALL ON public.user_invitation FROM PUBLIC;
REVOKE ALL ON public.entity_change_request FROM PUBLIC;
REVOKE ALL ON public.platform_admin FROM PUBLIC;
REVOKE ALL ON public.privacy_operator FROM PUBLIC;
REVOKE ALL ON public.user_consent FROM PUBLIC;
REVOKE ALL ON public.self_serve_provisioning FROM PUBLIC;
REVOKE ALL ON public.registration_request FROM PUBLIC;
REVOKE ALL ON public.platform_weekly_stat FROM PUBLIC;
REVOKE ALL ON public.privacy_request FROM PUBLIC;
REVOKE ALL ON public.legal_hold FROM PUBLIC;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.activity TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.action TO app_runtime;
GRANT SELECT, INSERT ON public.activity_revision TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.campaign_company TO app_runtime;
GRANT SELECT, INSERT, UPDATE ON public.company_handover TO app_runtime;
GRANT SELECT, INSERT, UPDATE ON public.import_job TO app_runtime;
GRANT SELECT, INSERT, UPDATE ON public.user_invitation TO app_runtime;
GRANT SELECT, INSERT, UPDATE ON public.entity_change_request TO app_runtime;
GRANT SELECT, INSERT ON public.user_consent TO app_runtime;
GRANT SELECT, INSERT, UPDATE ON public.self_serve_provisioning TO app_runtime;
GRANT SELECT, INSERT, UPDATE ON public.registration_request TO app_runtime;
GRANT SELECT, UPDATE ON public.user_entity TO app_runtime;

ALTER TABLE public.campaign ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaign FORCE ROW LEVEL SECURITY;
ALTER TABLE public.activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity FORCE ROW LEVEL SECURITY;
ALTER TABLE public.action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.action FORCE ROW LEVEL SECURITY;
ALTER TABLE public.activity_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_revision FORCE ROW LEVEL SECURITY;
ALTER TABLE public.campaign_company ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaign_company FORCE ROW LEVEL SECURITY;
ALTER TABLE public.company_handover ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_handover FORCE ROW LEVEL SECURITY;
ALTER TABLE public.import_job ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_job FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_invitation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_invitation FORCE ROW LEVEL SECURITY;
ALTER TABLE public.entity_change_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entity_change_request FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_consent ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_consent FORCE ROW LEVEL SECURITY;
ALTER TABLE public.self_serve_provisioning ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.self_serve_provisioning FORCE ROW LEVEL SECURITY;
ALTER TABLE public.registration_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registration_request FORCE ROW LEVEL SECURITY;
ALTER TABLE public.platform_admin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_admin FORCE ROW LEVEL SECURITY;
ALTER TABLE public.privacy_operator ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.privacy_operator FORCE ROW LEVEL SECURITY;
ALTER TABLE public.platform_weekly_stat ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_weekly_stat FORCE ROW LEVEL SECURITY;
ALTER TABLE public.privacy_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.privacy_request FORCE ROW LEVEL SECURITY;
ALTER TABLE public.legal_hold ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_hold FORCE ROW LEVEL SECURITY;

CREATE POLICY campaign_tenant_isolation ON public.campaign
  FOR ALL TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY activity_tenant_isolation ON public.activity
  FOR ALL TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY action_tenant_isolation ON public.action
  FOR ALL TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY activity_revision_tenant_isolation ON public.activity_revision
  FOR SELECT TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY activity_revision_insert ON public.activity_revision
  FOR INSERT TO app_runtime
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY campaign_company_tenant_isolation ON public.campaign_company
  FOR ALL TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY company_handover_tenant_isolation ON public.company_handover
  FOR ALL TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY import_job_tenant_isolation ON public.import_job
  FOR ALL TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY user_invitation_tenant_isolation ON public.user_invitation
  FOR ALL TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY entity_change_request_tenant_isolation ON public.entity_change_request
  FOR ALL TO app_runtime
  USING (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    entity_id = nullif(current_setting('app.active_entity_id', true), '')::uuid
    AND public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY user_consent_self ON public.user_consent
  FOR ALL TO app_runtime
  USING (
    user_id = (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
  )
  WITH CHECK (
    user_id = (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
  );

CREATE POLICY self_serve_provisioning_self ON public.self_serve_provisioning
  FOR ALL TO app_runtime
  USING (
    user_id = (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
  )
  WITH CHECK (
    user_id = (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
  );

CREATE POLICY registration_request_self ON public.registration_request
  FOR ALL TO app_runtime
  USING (
    user_id = (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
  )
  WITH CHECK (
    user_id = (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
  );

CREATE POLICY user_entity_update_isolation ON public.user_entity
  FOR UPDATE TO app_runtime
  USING (
    public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  )
  WITH CHECK (
    public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );
