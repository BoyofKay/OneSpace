-- R73: the experience conversation works like an Activity's (reply to a message).
alter table public.shared_experience_comments
  add column if not exists reply_to uuid references public.shared_experience_comments(id) on delete set null;
grant insert (reply_to) on public.shared_experience_comments to authenticated;
