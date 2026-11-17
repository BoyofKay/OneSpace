-- 17 Nov 2026: an explicit "Complaint" category in the app and website support forms,
-- so complaints are counted separately from questions, ideas and technical issues.
alter table public.support_requests drop constraint if exists support_requests_kind_check;
alter table public.support_requests add constraint support_requests_kind_check
  check (kind in ('contact','issue','idea','complaint'));
alter table public.public_support_requests drop constraint if exists public_support_requests_kind_check;
alter table public.public_support_requests add constraint public_support_requests_kind_check
  check (kind in ('contact','issue','account','complaint'));
