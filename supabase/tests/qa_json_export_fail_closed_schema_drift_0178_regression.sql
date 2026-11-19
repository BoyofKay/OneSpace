-- QA rollback-only regression: new user_id table and added recipient_id
-- on existing notes must NOT expand the SECURITY DEFINER JSON export.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid;
 exported jsonb;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
   on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'Paired QA fixture required';end if;

 create table public.qa_export_untracked_trial(
   id uuid primary key default gen_random_uuid(),
   user_id uuid not null references auth.users(id),
   secret text not null
 );
 alter table public.qa_export_untracked_trial enable row level security;
 insert into public.qa_export_untracked_trial(user_id,secret)
 values(a,'QA_UNTRACKED_FUTURE_SECRET_NOT_EXPORTED');
 -- Adding a new recipient field to an allowlisted source must not alter
 -- its fixed created_by predicate. This DDL is never committed.
 alter table public.notes add column recipient_id uuid;
 insert into public.notes(space_id,created_by,recipient_id,title,body,visibility)
 values(sid,b,a,'QA_NEW_RECIPIENT_FIELD_NOT_EXPORTED','Private B note','private');
 insert into public.notes(space_id,created_by,recipient_id,title,body,visibility)
 values(sid,a,b,'QA_OWNER_CREATED_NOTE_STILL_EXPORTS','Private A note','private');

 if has_function_privilege('anon','public.export_my_data()','execute') then
   raise exception 'Anonymous export execution must be blocked';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 exported:=public.export_my_data();
 if exported ? 'qa_export_untracked_trial'
  or exported::text like '%QA_UNTRACKED_FUTURE_SECRET_NOT_EXPORTED%'
  or exported::text like '%QA_NEW_RECIPIENT_FIELD_NOT_EXPORTED%'
  or exported::text not like '%QA_OWNER_CREATED_NOTE_STILL_EXPORTS%' then
   raise exception 'JSON export leaked unreviewed ownership column or lost owner note';
 end if;
end $qa$;
rollback;
select 'PASS: new user_id tables and added recipient_id columns cannot broaden reviewed JSON export; owner data preserved, fixtures rolled back' result;
