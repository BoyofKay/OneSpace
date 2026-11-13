-- Deployed Supabase migration 20261113090014 (onespace_shared_note_mentions_notification_routing).
-- Exact SQL captured from Supabase migration history.
-- R3 shared Note mention alerts. Never notify for private or archived notes.
alter table public.space_notifications
  drop constraint if exists space_notifications_object_kind_check;
alter table public.space_notifications
  add constraint space_notifications_object_kind_check
    check(object_kind in ('activity','letter','calendar','gesture','note'));

create function private.notify_shared_note_mention()
returns trigger
language plpgsql security definer set search_path='' as $$
declare partner record; actor uuid;
begin
  actor := auth.uid();
  if actor is null or new.visibility <> 'shared' or new.archived_at is not null
    then return new; end if;
  if tg_op='UPDATE' and new.body is not distinct from old.body
    and new.title is not distinct from old.title then return new; end if;
  -- Prevent privileged trigger misuse: editing actor must be in same space.
  if not exists(select 1 from public.space_members m
    where m.space_id=new.space_id and m.user_id=actor)
    then return new; end if;
  for partner in
    select m.user_id,p.display_name
    from public.space_members m join public.profiles p on p.id=m.user_id
    where m.space_id=new.space_id and m.user_id<>actor
  loop
    if length(btrim(partner.display_name))>0 and (
      position(lower('@'||partner.display_name) in lower(new.body))>0
      or position(lower('@'||partner.display_name) in lower(new.title))>0
    ) then
      insert into public.space_notifications
        (space_id,recipient_id,actor_id,kind,object_kind,object_id,headline)
      values(new.space_id,partner.user_id,actor,'mention','note',new.id,
        left(new.title,180))
      on conflict (recipient_id,kind,object_id)
        do update set actor_id=excluded.actor_id,
          created_at=now(), read_at=null, headline=excluded.headline;
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function private.notify_shared_note_mention() from public,anon,authenticated;
drop trigger if exists notes_mention_partner on public.notes;
create trigger notes_mention_partner
  after insert or update of body,title on public.notes
  for each row execute function private.notify_shared_note_mention();
