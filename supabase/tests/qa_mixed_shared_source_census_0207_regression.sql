begin;
do $qa$
declare sid uuid;a uuid;b uuid;outsider uuid;
 activity_id uuid; task_id uuid;task_item_id uuid;
 note_id uuid;private_note uuid;trip_id uuid; letter_id uuid;
 place_id uuid;occasion_id uuid;item_id uuid;proposal_id uuid;
 comment_id uuid; report_a jsonb;report_b jsonb; hash_a text;hash_b text;err text;
 n int;
begin
select s.id,s.created_by,sm.user_id into sid,a,b
from public.spaces s join public.space_members sm on sm.space_id=s.id and sm.user_id<>s.created_by
where (select count(*) from public.space_members m where m.space_id=s.id)=2 limit 1;
if sid is null then raise exception 'Paired QA fixture missing';end if;
select id into outsider from auth.users u
 where not exists(select 1 from public.space_members sm where sm.space_id=sid and sm.user_id=u.id)
 limit 1;
if has_function_privilege('anon','public.qa_mixed_shared_source_census()','execute')
 or has_function_privilege('anon','private.qa_mixed_shared_source_census()','execute')
then raise exception 'Mixed-shared census callable anonymously';end if;
perform set_config('request.jwt.claim.sub',a::text,true);
insert into public.activities(space_id,created_by,title,visibility)
 values(sid,a,'QA MIXED SHARED ACTIVITY','shared') returning id into activity_id;
insert into public.activity_comments(activity_id,author_id,body)
 values(activity_id,b,'Written shared activity comment') returning id into comment_id;
insert into public.activity_components(activity_id,created_by,kind,label,payload)
 values(activity_id,a,'note','Our option','{"description":"Shared idea"}');
insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,a,'QA MIXED SHARED TASK','shared') returning id into task_id;
insert into public.task_checklist_items(task_id,created_by,title)
 values(task_id,b,'Remember our appointment') returning id into task_item_id;
insert into public.task_checklist_checks(item_id,cycle_date,user_id,completed)
 values(task_item_id,current_date,b,true);
insert into public.notes(space_id,created_by,title,visibility)
 values(sid,a,'QA MIXED SHARED NOTE','shared') returning id into note_id;
insert into public.note_references(note_id,target_kind,target_id,created_by)
 values(note_id,'task',task_id,b);
insert into public.shared_trips(space_id,created_by,title,visibility)
 values(sid,a,'QA SHARED TRAVEL PLAN','shared') returning id into trip_id;
insert into public.trip_messages(trip_id,created_by,body)
 values(trip_id,b,'Looking forward to seeing you');
insert into public.couple_letters(space_id,author_id,title,body,status,open_on)
 values(sid,a,'QA SHARED OPEN LETTER','You mean a lot to me','sent',current_date)
 returning id into letter_id;
insert into public.couple_letter_reads(letter_id,reader_id)
 values(letter_id,b);
insert into public.places(space_id,created_by,name,visibility)
 values(sid,b,'QA SHARED PLACE','shared') returning id into place_id;
insert into public.place_visits(place_id,space_id,created_by,visited_on,caption)
 values(place_id,sid,a,current_date,'We took a shared walk');
insert into public.occasion_plans(space_id,created_by,title,occasion_on,visibility)
 values(sid,a,'QA SHARED GIFT PLAN',current_date+14,'shared') returning id into occasion_id;
insert into public.occasion_budget_items(plan_id,created_by,title,notes)
 values(occasion_id,b,'Shared gift choice','We both liked the idea') returning id into item_id;
insert into public.occasion_proposals(plan_id,created_by,title)
 values(occasion_id,b,'Our jointly proposed gifts') returning id into proposal_id;
insert into public.occasion_proposal_items(proposal_id,item_id) values(proposal_id,item_id);
insert into public.notes(space_id,created_by,title,visibility)
 values(sid,a,'QA PRIVATE NOT IN SHARED CENSUS','private') returning id into private_note;
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
report_a:=public.qa_mixed_shared_source_census();
if (report_a->>'mixed_visibility_table_types_checked')::int<>42
 or (report_a->>'visible_shared_rows_counted')::int<12
 or report_a->>'can_restore'<>'false'
 or report_a->>'safe_to_archive'<>'false'
 or report_a::text like '%Looking forward to seeing you%'
 or report_a::text like '%You mean a lot to me%'
 or report_a::text like '%QA PRIVATE NOT IN SHARED CENSUS%'
then raise exception 'A shared census incomplete or leaks text: %',left(report_a::text,1500);end if;
select count(*) into n from (values
 ('activities'),('activity_comments'),('activity_components'),
 ('tasks'),('task_checklist_items'),('task_checklist_checks'),
 ('notes'),('note_references'),('shared_trips'),('trip_messages'),
 ('couple_letters'),('couple_letter_reads'),('places'),('place_visits'),
 ('occasion_plans'),('occasion_budget_items'),('occasion_proposals'),
 ('occasion_proposal_items')) t(tab)
where not exists(select 1 from jsonb_array_elements(report_a->'per_table') j
 where j->>'source_table'=t.tab and (j->>'visible_shared_rows')::int>=1);
if n<>0 then raise exception 'Missing shared family fixtures: %',n;end if;
select j->>'source_sha256' into hash_a from jsonb_array_elements(report_a->'per_table') j
 where j->>'source_table'='activity_comments';
perform set_config('request.jwt.claim.sub',b::text,true);
report_b:=public.qa_mixed_shared_source_census();
select j->>'source_sha256' into hash_b from jsonb_array_elements(report_b->'per_table') j
 where j->>'source_table'='activity_comments';
if hash_a<>hash_b then raise exception 'Original partners have different visible shared comments';end if;
perform set_config('role','postgres',true);
update public.activity_comments set body='Updated shared message'
 where id=comment_id;
perform set_config('role','authenticated',true);
perform set_config('request.jwt.claim.sub',a::text,true);
report_a:=public.qa_mixed_shared_source_census();
if (select j->>'source_sha256' from jsonb_array_elements(report_a->'per_table') j
 where j->>'source_table'='activity_comments')=hash_a
then raise exception 'Shared written comment update did not change census hash';end if;
if outsider is not null then
 perform set_config('role','postgres',true);
 insert into public.activity_comments(activity_id,author_id,body)
 values(activity_id,outsider,'Invalid foreign shared author');
 perform set_config('role','authenticated',true);
 begin
 perform public.qa_mixed_shared_source_census();
 raise exception 'Foreign participant shared comment was accepted';
 exception when others then
 get stacked diagnostics err=message_text;
 if err<>'Mixed shared child ownership or link mismatch: activity_comments'
 then raise exception 'Unexpected outsider denial: %',err;end if;
 end;
end if;
end $qa$;
rollback;
select 'PASS: 42 mixed-shared table families, 18 nonempty shared fixtures, original pair equal hashes, prose changes hash, outsider denied, private notes excluded, rollback' result;