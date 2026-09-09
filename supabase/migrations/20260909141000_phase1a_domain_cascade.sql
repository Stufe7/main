-- Phase 1A: entity delete may cascade domains. A missing entity is not a
-- primary-domain violation. Paste this entire file in SQL Editor. No SET ROLE.

CREATE OR REPLACE FUNCTION public.app_entity_primary_domain_ok(p_entity uuid)
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

ALTER TABLE public.entity_domain
  DROP CONSTRAINT entity_domain_entity_id_fkey;

ALTER TABLE public.entity_domain
  ADD CONSTRAINT entity_domain_entity_id_fkey
  FOREIGN KEY (entity_id) REFERENCES public.entity (id) ON DELETE CASCADE;
