-- Phase 3 user lifecycle: role, deactivate/reactivate/remove, split reassignment.
-- Qualify table columns: RETURNS TABLE names become PL/pgSQL variables.

CREATE OR REPLACE FUNCTION public.app_user_entity_last_admin_guard()
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
  old_is_admin := (OLD.role = 'Entity Admin' AND OLD.status = 'active');
  IF TG_OP = 'DELETE' THEN
    new_is_admin := false;
  ELSE
    new_is_admin := (NEW.role = 'Entity Admin' AND NEW.status = 'active');
  END IF;
  IF old_is_admin AND NOT new_is_admin THEN
    PERFORM 1 FROM public.entity WHERE id = entity_key FOR UPDATE;
    SELECT count(*) INTO remaining
    FROM public.user_entity
    WHERE entity_id = entity_key
      AND status = 'active'
      AND role = 'Entity Admin'
      AND id IS DISTINCT FROM OLD.id;
    IF remaining < 1 THEN
      RAISE EXCEPTION 'must keep at least one active Entity Admin';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_require_entity_admin(p_user uuid, p_entity uuid)
RETURNS void
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
    WHERE ue.user_id = p_user AND ue.entity_id = p_entity
      AND ue.status = 'active' AND ue.role = 'Entity Admin'
  ) THEN
    RAISE EXCEPTION 'not an Entity Admin';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_allocation_to(
  p_entity uuid,
  p_target uuid,
  p_allocations jsonb,
  p_kind text,
  p_item uuid,
  p_fallback uuid
) RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  chosen uuid;
  raw text;
BEGIN
  raw := COALESCE(p_allocations, '{}'::jsonb) -> p_kind ->> p_item::text;
  IF raw IS NOT NULL AND btrim(raw) <> '' THEN
    chosen := raw::uuid;
  ELSE
    chosen := p_fallback;
  END IF;
  IF chosen IS NULL THEN
    RAISE EXCEPTION 'replacement is required';
  END IF;
  IF chosen = p_target THEN
    RAISE EXCEPTION 'replacement cannot be the same user';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_entity ue
    WHERE ue.user_id = chosen AND ue.entity_id = p_entity AND ue.status = 'active'
  ) THEN
    RAISE EXCEPTION 'replacement must be an active member';
  END IF;
  RETURN chosen;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_touch_last_access(p_user uuid, p_entity uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RETURN;
  END IF;
  UPDATE public.user_entity
  SET last_accessed_at = now()
  WHERE user_id = p_user AND entity_id = p_entity AND status = 'active';
END;
$$;

CREATE OR REPLACE FUNCTION public.app_admin_list_members(p_user uuid, p_entity uuid)
RETURNS TABLE (
  member_user_id uuid,
  member_email text,
  member_first_name text,
  member_last_name text,
  member_role text,
  member_status text,
  member_last_accessed_at timestamptz,
  member_deactivated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  RETURN QUERY
  SELECT ue.user_id, u.email, u.first_name, u.last_name, ue.role, ue.status,
         ue.last_accessed_at, ue.deactivated_at
  FROM public.user_entity ue
  JOIN public.app_user u ON u.id = ue.user_id
  WHERE ue.entity_id = p_entity
  ORDER BY
    CASE ue.status WHEN 'active' THEN 0 WHEN 'inactive' THEN 1 ELSE 2 END,
    u.email;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_member_responsibilities(
  p_user uuid,
  p_entity uuid,
  p_target uuid
) RETURNS TABLE (
  item_kind text,
  item_id uuid,
  item_label text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  RETURN QUERY
  SELECT 'company'::text, c.id, c.company_name
  FROM public.company c
  WHERE c.entity_id = p_entity AND c.owner_user_id = p_target
  UNION ALL
  SELECT 'action'::text, x.id, COALESCE(co.company_name || ': ', '') || x.description
  FROM public.action x
  JOIN public.company co ON co.id = x.company_id AND co.entity_id = x.entity_id
  WHERE x.entity_id = p_entity AND x.owner_user_id = p_target AND x.status = 'Open'
  UNION ALL
  SELECT 'campaign'::text, cam.id, cam.name
  FROM public.campaign cam
  WHERE cam.entity_id = p_entity AND cam.owner_user_id = p_target
  UNION ALL
  SELECT 'campaign_company'::text, cc.id, cam.name || ' / ' || co.company_name
  FROM public.campaign_company cc
  JOIN public.campaign cam ON cam.id = cc.campaign_id AND cam.entity_id = cc.entity_id
  JOIN public.company co ON co.id = cc.company_id AND co.entity_id = cc.entity_id
  WHERE cc.entity_id = p_entity AND cc.owner_user_id = p_target;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_set_member_role(
  p_user uuid,
  p_entity uuid,
  p_target uuid,
  p_role text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  IF p_role NOT IN ('Entity Admin', 'Manager', 'User') THEN
    RAISE EXCEPTION 'invalid role';
  END IF;
  PERFORM 1 FROM public.entity WHERE id = p_entity FOR UPDATE;
  UPDATE public.user_entity
  SET role = p_role, updated_at = now()
  WHERE user_id = p_target AND entity_id = p_entity AND status <> 'removed';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'membership not found';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_deactivate_member(
  p_user uuid,
  p_entity uuid,
  p_target uuid,
  p_allocations jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  default_to uuid;
  rec record;
  chosen uuid;
  company_to uuid;
  notices jsonb := '[]'::jsonb;
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  PERFORM 1 FROM public.entity WHERE id = p_entity FOR UPDATE;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_entity ue
    WHERE ue.user_id = p_target AND ue.entity_id = p_entity AND ue.status = 'active'
  ) THEN
    RAISE EXCEPTION 'user is not an active member';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_entity ue
    WHERE ue.user_id = p_target AND ue.entity_id = p_entity
      AND ue.role = 'Entity Admin' AND ue.status = 'active'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.user_entity ue
      WHERE ue.entity_id = p_entity AND ue.status = 'active' AND ue.role = 'Entity Admin'
        AND ue.user_id IS DISTINCT FROM p_target
    ) THEN
      RAISE EXCEPTION 'must keep at least one active Entity Admin';
    END IF;
  END IF;

  default_to := NULLIF(COALESCE(p_allocations, '{}'::jsonb) ->> 'default_to_user_id', '')::uuid;

  FOR rec IN
    SELECT c.id, c.company_name
    FROM public.company c
    WHERE c.entity_id = p_entity AND c.owner_user_id = p_target
  LOOP
    chosen := public.app_allocation_to(
      p_entity, p_target, p_allocations, 'companies', rec.id, default_to
    );
    UPDATE public.company
    SET owner_user_id = chosen, updated_by_user_id = p_user, updated_at = now()
    WHERE id = rec.id AND entity_id = p_entity;
    INSERT INTO public.company_handover (
      entity_id, company_id, from_user_id, to_user_id, reason, status, created_by_user_id
    ) VALUES (
      p_entity, rec.id, p_target, chosen, 'User Deactivated', 'Pending Review', p_user
    );
    SELECT notices || jsonb_build_object(
      'to_user_id', chosen,
      'to_email', u.email,
      'company_name', rec.company_name
    ) INTO notices
    FROM public.app_user u WHERE u.id = chosen;
  END LOOP;

  FOR rec IN
    SELECT x.id, x.company_id
    FROM public.action x
    WHERE x.entity_id = p_entity AND x.owner_user_id = p_target AND x.status = 'Open'
  LOOP
    company_to := NULL;
    BEGIN
      company_to := public.app_allocation_to(
        p_entity, p_target, p_allocations, 'companies', rec.company_id, default_to
      );
    EXCEPTION
      WHEN OTHERS THEN
        company_to := default_to;
    END;
    chosen := public.app_allocation_to(
      p_entity, p_target, p_allocations, 'actions', rec.id, company_to
    );
    UPDATE public.action
    SET owner_user_id = chosen, updated_by_user_id = p_user, updated_at = now()
    WHERE id = rec.id AND entity_id = p_entity;
  END LOOP;

  FOR rec IN
    SELECT cam.id FROM public.campaign cam
    WHERE cam.entity_id = p_entity AND cam.owner_user_id = p_target
  LOOP
    chosen := public.app_allocation_to(
      p_entity, p_target, p_allocations, 'campaigns', rec.id, default_to
    );
    UPDATE public.campaign
    SET owner_user_id = chosen, updated_by_user_id = p_user, updated_at = now()
    WHERE id = rec.id AND entity_id = p_entity;
  END LOOP;

  FOR rec IN
    SELECT cc.id FROM public.campaign_company cc
    WHERE cc.entity_id = p_entity AND cc.owner_user_id = p_target
  LOOP
    chosen := public.app_allocation_to(
      p_entity, p_target, p_allocations, 'campaign_companies', rec.id, default_to
    );
    UPDATE public.campaign_company
    SET owner_user_id = chosen, updated_by_user_id = p_user, updated_at = now()
    WHERE id = rec.id AND entity_id = p_entity;
  END LOOP;

  UPDATE public.user_entity
  SET status = 'inactive',
      deactivated_at = now(),
      deactivated_by_user_id = p_user,
      updated_at = now()
  WHERE user_id = p_target AND entity_id = p_entity AND status = 'active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user is not an active member';
  END IF;

  RETURN notices;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_reactivate_member(
  p_user uuid,
  p_entity uuid,
  p_target uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  PERFORM 1 FROM public.entity WHERE id = p_entity FOR UPDATE;
  UPDATE public.user_entity
  SET status = 'active',
      deactivated_at = NULL,
      deactivated_by_user_id = NULL,
      updated_at = now()
  WHERE user_id = p_target AND entity_id = p_entity AND status = 'inactive';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user is not inactive';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_remove_member(
  p_user uuid,
  p_entity uuid,
  p_target uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM public.app_require_entity_admin(p_user, p_entity);
  PERFORM 1 FROM public.entity WHERE id = p_entity FOR UPDATE;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_entity ue
    WHERE ue.user_id = p_target AND ue.entity_id = p_entity AND ue.status = 'inactive'
  ) THEN
    RAISE EXCEPTION 'remove is only allowed after deactivation';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.app_member_responsibilities(p_user, p_entity, p_target)
  ) THEN
    RAISE EXCEPTION 'reassign remaining responsibilities first';
  END IF;
  UPDATE public.user_entity
  SET status = 'removed',
      removed_at = now(),
      removed_by_user_id = p_user,
      updated_at = now()
  WHERE user_id = p_target AND entity_id = p_entity AND status = 'inactive';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'remove is only allowed after deactivation';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.app_require_entity_admin(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_allocation_to(uuid, uuid, jsonb, text, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_touch_last_access(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_admin_list_members(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_member_responsibilities(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_set_member_role(uuid, uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_deactivate_member(uuid, uuid, uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_reactivate_member(uuid, uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_remove_member(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.app_touch_last_access(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_admin_list_members(uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_member_responsibilities(uuid, uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_set_member_role(uuid, uuid, uuid, text) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_deactivate_member(uuid, uuid, uuid, jsonb) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_reactivate_member(uuid, uuid, uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_remove_member(uuid, uuid, uuid) TO app_runtime;
