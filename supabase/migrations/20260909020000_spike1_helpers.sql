-- Spike 1: app_runtime LOGIN (password out of band) and allow-listed helpers.
-- Helpers read spike1_membership only. Phase 1A replaces that with USER_ENTITY
-- and drops this table. Do not create kernel tables here.

ALTER ROLE app_runtime LOGIN;

CREATE TABLE public.spike1_membership (
  user_id uuid NOT NULL,
  entity_id uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('active', 'inactive')),
  PRIMARY KEY (user_id, entity_id)
);

ALTER TABLE public.spike1_membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spike1_membership FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.spike1_membership FROM PUBLIC;
GRANT SELECT ON public.spike1_membership TO app_authz;
GRANT SELECT ON public.spike1_membership TO app_runtime;
GRANT USAGE ON SCHEMA public TO app_authz;

CREATE FUNCTION public.app_has_active_membership(p_user uuid, p_entity uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.spike1_membership membership
    WHERE membership.user_id = p_user
      AND membership.entity_id = p_entity
      AND membership.status = 'active'
  );
$$;

CREATE FUNCTION public.app_authorize_membership(p_user uuid, p_entity uuid)
RETURNS TABLE(authorized boolean, membership_status text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    membership.status = 'active',
    membership.status
  FROM public.spike1_membership membership
  WHERE membership.user_id = p_user
    AND membership.entity_id = p_entity;
$$;

ALTER FUNCTION public.app_has_active_membership(uuid, uuid) OWNER TO app_authz;
ALTER FUNCTION public.app_authorize_membership(uuid, uuid) OWNER TO app_authz;

REVOKE ALL ON FUNCTION public.app_has_active_membership(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_authorize_membership(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_has_active_membership(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_authorize_membership(uuid, uuid) TO app_runtime;

CREATE POLICY spike1_membership_isolation
  ON public.spike1_membership
  FOR ALL
  TO app_runtime
  USING (public.app_has_active_membership(auth.uid(), entity_id))
  WITH CHECK (public.app_has_active_membership(auth.uid(), entity_id));
