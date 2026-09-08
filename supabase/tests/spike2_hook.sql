-- Spike 2: Before User Created rejection contract (run in SQL Editor).
-- Gmail must return http 400 and the company-email message. A company domain must pass.

DO $$
DECLARE
  denied jsonb;
  allowed jsonb;
BEGIN
  denied := public.hook_before_user_created(
    jsonb_build_object('user', jsonb_build_object('email', 'a@gmail.com'))
  );
  IF denied #>> '{error,http_code}' IS DISTINCT FROM '400' THEN
    RAISE EXCEPTION 'gmail should return http_code 400, got %', denied;
  END IF;
  IF denied #>> '{error,message}' IS DISTINCT FROM
    'Use a company email address. Personal or disposable providers are not accepted.'
  THEN
    RAISE EXCEPTION 'unexpected gmail reject message: %', denied;
  END IF;

  allowed := public.hook_before_user_created(
    jsonb_build_object('user', jsonb_build_object('email', 'marc@mmlogistix.com'))
  );
  IF allowed <> '{}'::jsonb THEN
    RAISE EXCEPTION 'company email should pass, got %', allowed;
  END IF;
END
$$;
