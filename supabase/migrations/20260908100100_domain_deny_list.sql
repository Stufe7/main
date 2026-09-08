-- Company-email deny dataset (spec 15.21). Needed in Phase 0 so Spike 2 can gate signup.

CREATE TABLE IF NOT EXISTS public.domain_deny_list (
  domain text PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('source_deny', 'operator_block', 'operator_allow')),
  source text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.domain_deny_refresh (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  refreshed_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL CHECK (status IN ('Success', 'FailedKeptLastGood')),
  source_version text,
  entry_count integer,
  error_summary text
);

REVOKE ALL ON public.domain_deny_list FROM PUBLIC;
REVOKE ALL ON public.domain_deny_refresh FROM PUBLIC;
GRANT SELECT ON public.domain_deny_list TO supabase_auth_admin;

INSERT INTO public.domain_deny_list (domain, kind, source) VALUES
  ('gmail.com', 'operator_block', 'phase0-seed'),
  ('googlemail.com', 'operator_block', 'phase0-seed'),
  ('outlook.com', 'operator_block', 'phase0-seed'),
  ('hotmail.com', 'operator_block', 'phase0-seed'),
  ('live.com', 'operator_block', 'phase0-seed'),
  ('msn.com', 'operator_block', 'phase0-seed'),
  ('yahoo.com', 'operator_block', 'phase0-seed'),
  ('ymail.com', 'operator_block', 'phase0-seed'),
  ('icloud.com', 'operator_block', 'phase0-seed'),
  ('me.com', 'operator_block', 'phase0-seed'),
  ('mac.com', 'operator_block', 'phase0-seed'),
  ('aol.com', 'operator_block', 'phase0-seed'),
  ('proton.me', 'operator_block', 'phase0-seed'),
  ('protonmail.com', 'operator_block', 'phase0-seed'),
  ('pm.me', 'operator_block', 'phase0-seed'),
  ('gmx.com', 'operator_block', 'phase0-seed'),
  ('gmx.net', 'operator_block', 'phase0-seed'),
  ('mail.com', 'operator_block', 'phase0-seed'),
  ('zoho.com', 'operator_block', 'phase0-seed'),
  ('yandex.com', 'operator_block', 'phase0-seed'),
  ('yandex.ru', 'operator_block', 'phase0-seed'),
  ('tutanota.com', 'operator_block', 'phase0-seed'),
  ('tuta.com', 'operator_block', 'phase0-seed')
ON CONFLICT (domain) DO NOTHING;
