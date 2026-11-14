-- R23 Notes 2.0: structured Quill Delta alongside plain searchable text.
-- No destructive migration or attachment changes. Previous notes remain legible.
alter table public.notes add column if not exists rich_delta jsonb;
alter table public.notes add constraint notes_rich_delta_is_array
 check(rich_delta is null or jsonb_typeof(rich_delta)='array');
grant insert(rich_delta) on public.notes to authenticated;
grant update(rich_delta) on public.notes to authenticated;
