-- Phase 8: job heartbeat and list-sort indexes (spec 17 performance baseline).

CREATE TABLE public.job_run (
  job_name text PRIMARY KEY,
  status text NOT NULL CHECK (status IN ('ok', 'partial', 'failed')),
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz NOT NULL,
  finished_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.job_run ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.job_run FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.job_run FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.app_job_record_run(
  p_job text,
  p_status text,
  p_detail jsonb,
  p_started timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_status NOT IN ('ok', 'partial', 'failed') THEN
    RAISE EXCEPTION 'invalid job status';
  END IF;
  INSERT INTO public.job_run (job_name, status, detail, started_at, finished_at)
  VALUES (p_job, p_status, COALESCE(p_detail, '{}'::jsonb), p_started, now())
  ON CONFLICT (job_name) DO UPDATE
    SET status = excluded.status,
        detail = excluded.detail,
        started_at = excluded.started_at,
        finished_at = excluded.finished_at;
END;
$$;

REVOKE ALL ON FUNCTION public.app_job_record_run(text, text, jsonb, timestamptz) FROM PUBLIC;

CREATE INDEX IF NOT EXISTS company_entity_state_name_idx
  ON public.company (entity_id, record_state, lower(company_name));
CREATE INDEX IF NOT EXISTS contact_entity_state_name_idx
  ON public.contact (entity_id, record_state, lower(last_name), lower(first_name));
CREATE INDEX IF NOT EXISTS campaign_entity_status_idx
  ON public.campaign (entity_id, status);
