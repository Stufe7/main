-- Channel is the main customer category. Segment is one subcategory of that channel.

ALTER TABLE public.company
  ADD COLUMN IF NOT EXISTS channel text,
  ADD COLUMN IF NOT EXISTS segment text;

ALTER TABLE public.company
  DROP CONSTRAINT IF EXISTS company_segment_requires_channel;

ALTER TABLE public.company
  ADD CONSTRAINT company_segment_requires_channel
  CHECK (segment IS NULL OR channel IS NOT NULL);

CREATE INDEX IF NOT EXISTS company_channel_lower_idx
  ON public.company (entity_id, lower(channel));

CREATE INDEX IF NOT EXISTS company_segment_lower_idx
  ON public.company (entity_id, lower(segment));
