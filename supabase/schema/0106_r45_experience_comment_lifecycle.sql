-- R45: Author-owned shared-experience comment edit/retract/restore.
-- Preserve existing comments, prevent retracted-text disclosure, capture field
-- names only in server-owned history, and never re-notify on edits/restores.
alter table public.shared_experience_comments
 add column if not exists updated_at timestamptz not null default now();

-- An existing R13 policy already restricts UPDATE to the original author.
-- Keep ownership / identity fields immutable through column grants.
grant update (body) on public.shared_experience_comments to authenticated;

drop policy "Couple reads conversation"
 on public.shared_experience_comments;
create policy "Couple reads active and author sees retracted comments"
 on public.shared_experience_comments for select to authenticated
 using (
  (archived_at is null or created_by=(select auth.uid())) and
  exists (select 1 from public.shared_experiences x
   where x.id=experience_id and private.is_space_member(x.space_id))
 );

create or replace function private.r45_comment_touch()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.body is distinct from old.body or
    new.archived_at is distinct from old.archived_at then
  new.updated_at:=clock_timestamp();
 end if;
 return new;
end; $$;
revoke all on function private.r45_comment_touch()
 from public,anon,authenticated;
create trigger r45_experience_comment_touch
 before update of body, archived_at on public.shared_experience_comments
 for each row execute function private.r45_comment_touch();

alter table public.record_action_history
 drop constraint record_action_history_record_kind_check;
alter table public.record_action_history
 add constraint record_action_history_record_kind_check
 check(record_kind in ('note','task','goal','memory','event','reminder',
  'occasion','experience','trip','contact','checkin','checkin_request',
  'experience_comment'));

-- Separate permissive SELECT policy: original source-row RLS still decides.
-- Once the author retracts a comment, their partner cannot view its history
-- until restoration either; history contains no comment body or old text.
create policy "Read history of visible experience comments"
 on public.record_action_history for select to authenticated
 using (
  record_kind='experience_comment' and exists (
   select 1 from public.shared_experience_comments c
   join public.shared_experiences x on x.id=c.experience_id
   where c.id=record_id and x.space_id=record_action_history.space_id
  )
 );

create or replace function private.r45_audit_experience_comment()
returns trigger language plpgsql security definer
set search_path='' as $$
declare
 target_space uuid;
 names text[]:='{}'::text[];
 action_name text;
begin
 select x.space_id into target_space from public.shared_experiences x
  where x.id=new.experience_id;
 if target_space is null then return new; end if;
 if tg_op='INSERT' then
  action_name:='created';
  names:=array['body'];
 else
  if old.body is distinct from new.body then
   names:=array_append(names,'body');
  end if;
  if old.archived_at is distinct from new.archived_at then
   names:=array_append(names,'archived_at');
  end if;
  if cardinality(names)=0 then return new; end if;
  action_name:=case
   when old.archived_at is null and new.archived_at is not null
    then 'archived'
   when old.archived_at is not null and new.archived_at is null
    then 'restored'
   else 'edited' end;
 end if;
 insert into public.record_action_history
  (space_id,record_kind,record_id,actor_id,action,changed_fields)
 values (target_space,'experience_comment',new.id,auth.uid(),action_name,names);
 return new;
end; $$;
revoke all on function private.r45_audit_experience_comment()
 from public,anon,authenticated;
create trigger r45_experience_comment_audit
 after insert or update of body, archived_at
 on public.shared_experience_comments for each row
 execute function private.r45_audit_experience_comment();
