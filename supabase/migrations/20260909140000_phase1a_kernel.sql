-- Phase 1A tenancy kernel (spec 15.1–15.2a, 15.3–15.4 slim, 15.17, 17).
-- Paste this entire file in Supabase SQL Editor and Run. Do not add SET ROLE.
-- Policies use the spec 17 claim-read. Do not call auth.uid().
-- public.app_user is spec 15.2 USER (user is reserved in PostgreSQL).

CREATE TABLE public.app_user (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  first_name text,
  last_name text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  last_login timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT app_user_email_key UNIQUE (email)
);

CREATE TABLE public.entity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_name text NOT NULL,
  legal_name text,
  country text NOT NULL,
  reference_timezone text NOT NULL,
  digest_send_local_time time NOT NULL DEFAULT '08:00:00',
  address text,
  telephone text,
  website text,
  status text NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Suspended')),
  plan_code text NOT NULL DEFAULT 'mvp',
  plan_status text NOT NULL DEFAULT 'Active' CHECK (plan_status IN ('Active', 'Inactive')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT entity_digest_whole_hour CHECK (
    EXTRACT(MINUTE FROM digest_send_local_time) = 0
    AND EXTRACT(SECOND FROM digest_send_local_time) = 0
  )
);

CREATE TABLE public.user_entity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.app_user (id),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  role text NOT NULL CHECK (role IN ('Entity Admin', 'Manager', 'User')),
  status text NOT NULL CHECK (status IN ('active', 'inactive', 'removed')),
  invited_by_user_id uuid,
  digest_frequency text NOT NULL DEFAULT 'Daily'
    CHECK (digest_frequency IN ('Off', 'Daily', 'Weekly', 'Monthly')),
  digest_last_sent_date date,
  last_accessed_at timestamptz,
  deactivated_at timestamptz,
  deactivated_by_user_id uuid,
  removed_at timestamptz,
  removed_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_entity_user_entity_key UNIQUE (user_id, entity_id),
  CONSTRAINT user_entity_status_audit CHECK (
    (
      status = 'active'
      AND deactivated_at IS NULL
      AND deactivated_by_user_id IS NULL
      AND removed_at IS NULL
      AND removed_by_user_id IS NULL
    )
    OR (
      status = 'inactive'
      AND deactivated_at IS NOT NULL
      AND deactivated_by_user_id IS NOT NULL
      AND removed_at IS NULL
      AND removed_by_user_id IS NULL
    )
    OR (
      status = 'removed'
      AND removed_at IS NOT NULL
      AND removed_by_user_id IS NOT NULL
    )
  ),
  CONSTRAINT user_entity_invited_by_fk
    FOREIGN KEY (invited_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT user_entity_deactivated_by_fk
    FOREIGN KEY (deactivated_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT user_entity_removed_by_fk
    FOREIGN KEY (removed_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE TABLE public.entity_domain (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id) ON DELETE CASCADE,
  domain text NOT NULL,
  status text NOT NULL CHECK (status IN ('Approved', 'Revoked')),
  is_primary boolean NOT NULL DEFAULT false,
  added_via text NOT NULL
    CHECK (added_via IN ('Signup', 'Registration Approval', 'Domain Addition Request')),
  approved_by_platform_admin_id uuid,
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT entity_domain_entity_domain_key UNIQUE (entity_id, domain),
  CONSTRAINT entity_domain_id_entity_key UNIQUE (id, entity_id),
  CONSTRAINT entity_domain_normalized CHECK (
    domain = lower(domain)
    AND domain NOT LIKE '%@%'
    AND domain <> ''
  ),
  CONSTRAINT entity_domain_primary_approved CHECK (
    NOT is_primary OR status = 'Approved'
  )
);

CREATE TABLE public.company (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  company_name text NOT NULL,
  status text NOT NULL CHECK (
    status IN ('Prospect', 'Customer', 'Former Customer', 'Inactive')
  ),
  record_state text NOT NULL CHECK (record_state IN ('Active', 'Archived')),
  owner_user_id uuid,
  created_by_user_id uuid,
  updated_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT company_id_entity_key UNIQUE (id, entity_id),
  CONSTRAINT company_owner_membership_fk
    FOREIGN KEY (owner_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT company_created_by_membership_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT company_updated_by_membership_fk
    FOREIGN KEY (updated_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE TABLE public.contact (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  company_id uuid NOT NULL,
  first_name text NOT NULL,
  last_name text NOT NULL,
  record_state text NOT NULL CHECK (record_state IN ('Active', 'Archived')),
  created_by_user_id uuid,
  updated_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contact_id_entity_key UNIQUE (id, entity_id),
  CONSTRAINT contact_company_same_tenant
    FOREIGN KEY (company_id, entity_id)
    REFERENCES public.company (id, entity_id),
  CONSTRAINT contact_created_by_membership_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT contact_updated_by_membership_fk
    FOREIGN KEY (updated_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

CREATE INDEX user_entity_authz_idx
  ON public.user_entity (user_id, entity_id, status);
CREATE INDEX company_entity_id_idx ON public.company (entity_id);
CREATE INDEX contact_entity_id_idx ON public.contact (entity_id);
CREATE INDEX contact_company_id_idx ON public.contact (company_id);
CREATE INDEX entity_domain_entity_id_idx ON public.entity_domain (entity_id);

CREATE FUNCTION public.app_entity_primary_domain_ok(p_entity uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.entity WHERE id = p_entity) THEN
    RETURN;
  END IF;
  IF (
    SELECT COUNT(*)
    FROM public.entity_domain domain_row
    WHERE domain_row.entity_id = p_entity
      AND domain_row.status = 'Approved'
      AND domain_row.is_primary
  ) <> 1 THEN
    RAISE EXCEPTION
      'entity % must have exactly one Approved primary domain',
      p_entity;
  END IF;
END;
$$;

CREATE FUNCTION public.app_entity_primary_domain_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'entity' THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    PERFORM public.app_entity_primary_domain_ok(NEW.id);
    RETURN NEW;
  END IF;
  IF TG_OP = 'DELETE' THEN
    PERFORM public.app_entity_primary_domain_ok(OLD.entity_id);
    RETURN OLD;
  END IF;
  PERFORM public.app_entity_primary_domain_ok(NEW.entity_id);
  IF TG_OP = 'UPDATE' AND NEW.entity_id IS DISTINCT FROM OLD.entity_id THEN
    PERFORM public.app_entity_primary_domain_ok(OLD.entity_id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER entity_one_approved_primary
AFTER INSERT OR UPDATE ON public.entity
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.app_entity_primary_domain_guard();

CREATE CONSTRAINT TRIGGER entity_domain_one_approved_primary
AFTER INSERT OR UPDATE OR DELETE ON public.entity_domain
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.app_entity_primary_domain_guard();

CREATE FUNCTION public.app_contact_company_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.company_id IS DISTINCT FROM OLD.company_id
     OR NEW.entity_id IS DISTINCT FROM OLD.entity_id THEN
    RAISE EXCEPTION 'CONTACT.company_id is immutable';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER contact_company_immutable
BEFORE UPDATE ON public.contact
FOR EACH ROW
EXECUTE FUNCTION public.app_contact_company_immutable();

CREATE OR REPLACE FUNCTION public.app_has_active_membership(p_user uuid, p_entity uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_entity membership
    JOIN public.app_user account ON account.id = membership.user_id
    JOIN public.entity tenant ON tenant.id = membership.entity_id
    WHERE membership.user_id = p_user
      AND membership.entity_id = p_entity
      AND membership.status = 'active'
      AND account.status = 'active'
      AND tenant.status = 'Active'
  );
$$;

CREATE OR REPLACE FUNCTION public.app_authorize_membership(p_user uuid, p_entity uuid)
RETURNS TABLE(authorized boolean, membership_status text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    membership.status = 'active'
      AND account.status = 'active'
      AND tenant.status = 'Active',
    membership.status
  FROM public.user_entity membership
  JOIN public.app_user account ON account.id = membership.user_id
  JOIN public.entity tenant ON tenant.id = membership.entity_id
  WHERE membership.user_id = p_user
    AND membership.entity_id = p_entity;
$$;

DO $$
BEGIN
  BEGIN
    ALTER FUNCTION public.app_has_active_membership(uuid, uuid) OWNER TO app_authz;
    ALTER FUNCTION public.app_authorize_membership(uuid, uuid) OWNER TO app_authz;
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'hosted limitation: helpers remain owned by %', current_user;
  END;
END
$$;

REVOKE ALL ON FUNCTION public.app_has_active_membership(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_authorize_membership(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_has_active_membership(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_authorize_membership(uuid, uuid) TO app_runtime;

REVOKE ALL ON public.app_user FROM PUBLIC;
REVOKE ALL ON public.entity FROM PUBLIC;
REVOKE ALL ON public.user_entity FROM PUBLIC;
REVOKE ALL ON public.entity_domain FROM PUBLIC;
REVOKE ALL ON public.company FROM PUBLIC;
REVOKE ALL ON public.contact FROM PUBLIC;

DO $$
BEGIN
  BEGIN
    GRANT SELECT ON public.app_user TO app_authz;
    GRANT SELECT ON public.entity TO app_authz;
    GRANT SELECT ON public.user_entity TO app_authz;
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'hosted limitation: could not GRANT helper tables to app_authz';
  END;
END
$$;

GRANT SELECT ON public.app_user TO app_runtime;
GRANT SELECT ON public.entity TO app_runtime;
GRANT SELECT ON public.user_entity TO app_runtime;
GRANT SELECT ON public.entity_domain TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.company TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact TO app_runtime;

ALTER TABLE public.app_user ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_user FORCE ROW LEVEL SECURITY;
ALTER TABLE public.entity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entity FORCE ROW LEVEL SECURITY;
ALTER TABLE public.user_entity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_entity FORCE ROW LEVEL SECURITY;
ALTER TABLE public.entity_domain ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entity_domain FORCE ROW LEVEL SECURITY;
ALTER TABLE public.company ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company FORCE ROW LEVEL SECURITY;
ALTER TABLE public.contact ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact FORCE ROW LEVEL SECURITY;

-- Spec 17 claim-read. Never auth.uid().
CREATE POLICY app_user_self
  ON public.app_user
  FOR SELECT
  TO app_runtime
  USING (
    id = (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid
  );

CREATE POLICY entity_membership
  ON public.entity
  FOR SELECT
  TO app_runtime
  USING (
    public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      id
    )
  );

CREATE POLICY user_entity_isolation
  ON public.user_entity
  FOR SELECT
  TO app_runtime
  USING (
    public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY entity_domain_isolation
  ON public.entity_domain
  FOR SELECT
  TO app_runtime
  USING (
    public.app_has_active_membership(
      (nullif(current_setting('request.jwt.claims', true), '')::json ->> 'sub')::uuid,
      entity_id
    )
  );

CREATE POLICY company_tenant_isolation
  ON public.company
  FOR ALL
  TO app_runtime
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

CREATE POLICY contact_tenant_isolation
  ON public.contact
  FOR ALL
  TO app_runtime
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

DROP POLICY IF EXISTS spike1_membership_isolation ON public.spike1_membership;
DROP TABLE IF EXISTS public.spike1_membership;
