-- Company notes as a list (note + source), like campaigns and contacts.

CREATE TABLE public.company_note (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id uuid NOT NULL REFERENCES public.entity (id),
  company_id uuid NOT NULL,
  note text NOT NULL,
  source text,
  record_state text NOT NULL CHECK (record_state IN ('Active', 'Archived')),
  created_by_user_id uuid,
  updated_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT company_note_id_entity_key UNIQUE (id, entity_id),
  CONSTRAINT company_note_company_same_tenant
    FOREIGN KEY (company_id, entity_id)
    REFERENCES public.company (id, entity_id),
  CONSTRAINT company_note_created_by_membership_fk
    FOREIGN KEY (created_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id),
  CONSTRAINT company_note_updated_by_membership_fk
    FOREIGN KEY (updated_by_user_id, entity_id)
    REFERENCES public.user_entity (user_id, entity_id)
);

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
WHERE c.notes IS NOT NULL AND btrim(c.notes) <> '';

CREATE INDEX company_note_company_idx
  ON public.company_note (entity_id, company_id, record_state);

REVOKE ALL ON public.company_note FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE ON public.company_note TO app_runtime;

ALTER TABLE public.company_note ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_note FORCE ROW LEVEL SECURITY;

CREATE POLICY company_note_tenant_isolation ON public.company_note
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
