-- Company legal_name is unused in the app. Rename it to parent_company.
-- Entity.legal_name is unchanged.

ALTER TABLE public.company
  RENAME COLUMN legal_name TO parent_company;
