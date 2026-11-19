begin;
do $qa$
declare sid uuid;a uuid;b uuid;expid uuid;commentid uuid;report_a jsonb;report_b jsonb;err text;cnt int;
begin
select s.id,s.created_by,sm.user_id into sid,a,b
from public.spaces s join public.space_members sm on sm.space_id=s.id and sm.user_id<>s.created_by
where (select count(*) from public.space_members m where m.space_id=s.id)=2 limit 1;
if sid is null then raise exception 'Original QA pair unavailable';end if;
perform set_config('request.jwt.claim.sub',a::text,true);
insert into public.shared_experiences(space_id,created_by,category,title)
values(sid,a,'movie','QA archived audit comment') returning id into expid;
insert into public.shared_experience_comments(experience_id,created_by,body)
values(expid,b,'B original comment authored while A is signed in') returning id into commentid;
update public.shared_experience_comments set archived_at=now() where id=commentid;
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
report_a:=public.qa_unmirrored_private_source_census();
select (x->>'private_rows')::int into cnt
from jsonb_array_elements(report_a->'per_table') x
where x->>'source_table'='record_action_history';
if cnt<>0 then raise exception 'A was handed B archived comment audit as portable private history';end if;
perform set_config('request.jwt.claim.sub',b::text,true);
report_b:=public.qa_unmirrored_private_source_census();
select (x->>'private_rows')::int into cnt
from jsonb_array_elements(report_b->'per_table') x
where x->>'source_table'='record_action_history';
if cnt<>0 then raise exception 'B was handed an actor A audit event as portable private history';end if;
perform set_config('role','postgres',true);
insert into public.record_action_history(space_id,record_kind,record_id,actor_id,action,changed_fields)
values(sid,'experience_comment',gen_random_uuid(),a,'created',array['body']);
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
begin
 perform public.qa_unmirrored_private_source_census();
 raise exception 'Orphan comment audit event was silently skipped';
exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Private action history has orphan source' then
 raise exception 'Wrong malformed archived audit denial: %',err;end if;
end;
end $qa$;
rollback;
select 'PASS: archived B-comment action by A stays shared reference only; no private owner claims; orphan audit still blocks; rollback' result;
