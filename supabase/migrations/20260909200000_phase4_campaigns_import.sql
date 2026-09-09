-- Phase 4: campaign membership helpers and stricter date-horizon on new open actions.

CREATE OR REPLACE FUNCTION public.app_action_campaign_horizon_ok()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
  camp public.campaign%ROWTYPE;
  tz text;
  today date;
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
  IF NEW.status = 'Open' THEN
    SELECT e.reference_timezone INTO tz
    FROM public.entity e WHERE e.id = NEW.entity_id;
    today := (timezone(COALESCE(tz, 'UTC'), now()))::date;
    IF today > camp.end_date THEN
      RAISE EXCEPTION 'campaign has ended';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_campaign_assert_end_date(
  p_entity uuid,
  p_campaign uuid,
  p_end date
) RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.action x
    WHERE x.entity_id = p_entity
      AND x.campaign_id = p_campaign
      AND x.status = 'Open'
      AND x.due_date > p_end
  ) THEN
    RAISE EXCEPTION 'reschedule or cancel open actions after the new end date';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.app_campaign_add_companies(
  p_user uuid,
  p_entity uuid,
  p_campaign uuid,
  p_company_ids uuid[]
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  company_key uuid;
  added integer := 0;
BEGIN
  IF public.app_claim_sub() IS DISTINCT FROM p_user THEN
    RAISE EXCEPTION 'user mismatch';
  END IF;
  IF NOT public.app_has_active_membership(p_user, p_entity) THEN
    RAISE EXCEPTION 'no access to this entity';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.campaign cam
    WHERE cam.id = p_campaign AND cam.entity_id = p_entity
  ) THEN
    RAISE EXCEPTION 'campaign not found';
  END IF;
  IF p_company_ids IS NULL THEN
    RETURN 0;
  END IF;
  FOREACH company_key IN ARRAY p_company_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.company c
      WHERE c.id = company_key AND c.entity_id = p_entity AND c.record_state = 'Active'
    ) THEN
      RAISE EXCEPTION 'company not found';
    END IF;
    INSERT INTO public.campaign_company (
      entity_id, campaign_id, company_id, status, record_state,
      created_by_user_id, updated_by_user_id
    ) VALUES (
      p_entity, p_campaign, company_key, 'Not Started', 'Active', p_user, p_user
    )
    ON CONFLICT (entity_id, campaign_id, company_id) DO UPDATE
      SET record_state = 'Active',
          removed_at = NULL,
          updated_by_user_id = p_user,
          updated_at = now();
    added := added + 1;
  END LOOP;
  RETURN added;
END;
$$;

REVOKE ALL ON FUNCTION public.app_campaign_assert_end_date(uuid, uuid, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.app_campaign_add_companies(uuid, uuid, uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_campaign_assert_end_date(uuid, uuid, date) TO app_runtime;
GRANT EXECUTE ON FUNCTION public.app_campaign_add_companies(uuid, uuid, uuid, uuid[]) TO app_runtime;
