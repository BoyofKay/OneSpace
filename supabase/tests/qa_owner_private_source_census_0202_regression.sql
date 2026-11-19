begin;
do $qa$
declare sid uuid; a uuid;b uuid; ownerreport jsonb; partnerreport jsonb; initialhash text; revisedhash text;
begin
select s.id,s.created_by,sm.user_id into sid,a,b
from public.spaces s join public.space_members sm on sm.space_id=s.id and sm.user_id<>s.created_by
where (select count(*) from public.space_members m where m.space_id=s.id)=2 limit 1;
if sid is null then raise exception 'QA paired fixture required';end if;
if has_function_privilege('anon','public.qa_owner_private_source_census()','execute')
or has_function_privilege('anon','private.qa_owner_private_source_census()','execute')
then raise exception 'Owner private source census exposed anonymously';end if;
perform set_config('request.jwt.claim.sub',a::text,true);
insert into public.gesture_templates(space_id,creator_id,recipient_id,kind,title,message,scheduled_moment)
values(sid,a,b,'hug','QA private draft','A family-only private message','morning');
insert into public.gesture_schedules(space_id,sender_id,recipient_id,moment,enabled)
values(sid,a,b,'after_work',true);
insert into public.gesture_message_overrides(space_id,owner_id,kind,message_index,message)
values(sid,a,'thinking',0,'A private gesture setting');
insert into public.personal_days_off(space_id,user_id,off_date,label)
values(sid,a,date '2026-12-24','QA quiet family holiday');
perform set_config('request.jwt.claim.sub',b::text,true);
insert into public.gesture_templates(space_id,creator_id,recipient_id,kind,title,message)
values(sid,b,a,'hug','B SECRET DRAFT','B private content');
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
ownerreport:=public.qa_owner_private_source_census();
if (ownerreport->>'owner_private_families_checked')::int<>4
 or (ownerreport->>'private_source_rows_checked')::int<>4
 or ownerreport->>'safe_to_archive'<>'false'
 or ownerreport::text like '%B SECRET DRAFT%'
 or jsonb_array_length(ownerreport->'per_table')<>4
then raise exception 'A private-only source scope violated: %',ownerreport;end if;
select x->>'source_sha256' into initialhash
from jsonb_array_elements(ownerreport->'per_table') x
where x->>'source_table'='gesture_templates';
perform set_config('request.jwt.claim.sub',b::text,true);
partnerreport:=public.qa_owner_private_source_census();
if (partnerreport->>'private_source_rows_checked')::int<>1
 or partnerreport->>'owner_id'<>b::text then
 raise exception 'Partner B cannot separately inspect own drafts';end if;
perform set_config('role','postgres',true);
update public.gesture_templates set message='QA new private message'
where creator_id=a and space_id=sid and title='QA private draft';
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
ownerreport:=public.qa_owner_private_source_census();
select x->>'source_sha256' into revisedhash
from jsonb_array_elements(ownerreport->'per_table') x
where x->>'source_table'='gesture_templates';
if revisedhash=initialhash then
 raise exception 'Changed private draft did not change owner-bound source fingerprint';end if;
perform set_config('request.jwt.claim.sub',b::text,true);
partnerreport:=public.qa_owner_private_source_census();
if (partnerreport->>'private_source_rows_checked')::int<>1 then
 raise exception 'A changed draft modified B content count';end if;
end $qa$;
rollback;
select 'PASS: 4 owner-private source families, both-partner draft isolation, stable scoped counts and changed-text SHA-256; rolled back' result;