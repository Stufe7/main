-- Notes now live on public.company_note. Copy any leftover company.notes
-- that were not already migrated, then drop the unused column.

INSERT INTO public.company_note (
  entity_id, company_id, note, source, record_state,
  created_by_user_id, updated_by_user_id, created_at, updated_at
)
SELECT
  c.entity_id,
  c.id,
  btrim(c.notes),
  NULL,
  'Active',
  c.created_by_user_id,
  c.updated_by_user_id,
  c.updated_at,
  c.updated_at
FROM public.company c
WHERE c.notes IS NOT NULL
  AND btrim(c.notes) <> ''
  AND NOT EXISTS (
    SELECT 1
    FROM public.company_note n
    WHERE n.entity_id = c.entity_id
      AND n.company_id = c.id
      AND n.record_state = 'Active'
      AND lower(n.note) = lower(btrim(c.notes))
  );

ALTER TABLE public.company
  DROP COLUMN IF EXISTS notes;
