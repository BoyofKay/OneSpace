-- Give collaborative notes monotonic timestamps to detect overlapping edits.
-- now() is constant within a Postgres transaction; clock_timestamp() is not.
create or replace function private.touch_note_updated_at()
returns trigger language plpgsql set search_path = ''
as $$
begin
  new.updated_at := greatest(
    clock_timestamp(),
    old.updated_at + interval '1 microsecond'
  );
  return new;
end;
$$;

drop trigger notes_updated_at on public.notes;
create trigger notes_updated_at before update on public.notes
for each row execute function private.touch_note_updated_at();
