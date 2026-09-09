-- RETURNS TABLE (user_id ...) makes user_id a PL/pgSQL variable.
-- Unqualified user_id / status in the membership check was ambiguous and 500'd GET /v1/members.

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
