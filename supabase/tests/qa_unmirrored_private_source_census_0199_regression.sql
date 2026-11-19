-- QA 0199–0201 source census regression: 19 formerly unmirrored
-- table families, owner scope, actual written content fingerprints and faults.
begin;
do $qa$
declare
 sid uuid;a uuid;b uuid;
 note_id uuid; task_id uuid;activity_id uuid; trip_id uuid; place_id uuid;
 memory_id uuid; occasion_id uuid; comment_id uuid;
 before_a jsonb; after_a jsonb; partner_b jsonb;
 oldhash text;newhash text; err text; missing_family int;
begin
 select s.id,s.created_by,sm.user_id into sid,a,b
 from public.spaces s join public.space_members sm
 on sm.space_id=s.id and sm.user_id<>s.created_by
 where (select count(*) from public.space_members m where m.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA original couple fixture missing';end if;
 if has_function_privilege('anon','public.qa_unmirrored_private_source_census()','execute')
 or has_function_privilege('anon','private.qa_unmirrored_private_source_census()','execute')
 then raise exception 'Unmirrored private source census callable without account';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA census note','Private source written memo','private') returning id into note_id;
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,a,'QA census task','private') returning id into task_id;
 insert into public.activities(space_id,created_by,title,visibility)
 values(sid,a,'QA census activity','private') returning id into activity_id;
 insert into public.activity_comments(activity_id,author_id,body)
 values(activity_id,a,'Written archived discussion') returning id into comment_id;
 insert into public.note_references(note_id,target_kind,target_id,created_by)
 values(note_id,'task',task_id,a);
 insert into public.item_links(space_id,created_by,from_kind,from_id,to_kind,to_id)
 values(sid,a,'note',note_id,'task',task_id);
 insert into public.shared_trips(space_id,created_by,title,visibility)
 values(sid,a,'QA census trip','private') returning id into trip_id;
 insert into public.trip_revisions(trip_id,record_kind,record_id,changed_by,
    before_snapshot,after_snapshot)
 values(trip_id,'trip',trip_id,a,'{"notes":"Before our trip"}',
    '{"notes":"After our trip","voice_path":"secret.wav"}');
 insert into public.couple_letters(space_id,author_id,title,body,status)
 values(sid,a,'QA own draft','A secret message for later','draft');
 insert into public.places(space_id,created_by,name,visibility)
 values(sid,a,'QA our private location','private') returning id into place_id;
 insert into public.place_visits(place_id,space_id,created_by,visited_on,caption)
 values(place_id,sid,a,current_date,'Walked past our favorite cafe');
 insert into public.memories(space_id,created_by,title,memory_date,visibility)
 values(sid,a,'QA scrapbook narrative',current_date,'private') returning id into memory_id;
 insert into public.scrapbook_pages(memory_id,created_by,page_order,title,story_text)
 values(memory_id,a,0,'A lovely page','Private written scrapbook story');
 insert into public.occasion_plans(space_id,created_by,title,occasion_on,visibility)
 values(sid,a,'QA census occasion',current_date+20,'private') returning id into occasion_id;
 insert into public.occasion_budget_log(plan_id,event_kind,actor_id,
    before_item,after_item)
 values(occasion_id,'revised',a,'{"notes":"Old budget message"}',
   '{"notes":"New budget message","photo_1_id":"88888888-2222-4333-8444-555555555555"}');
 insert into public.record_action_history(space_id,record_kind,record_id,actor_id,action,changed_fields)
 values(sid,'note',note_id,a,'edited',array['body']);

 perform set_config('role','authenticated',true);
 before_a:=public.qa_unmirrored_private_source_census();
 if before_a->>'owner_id'<>a::text
 or (before_a->>'table_families_checked')::int<>19
 or (before_a->>'private_source_rows_checked')::int<9
 or before_a->>'can_restore'<>'false'
 or before_a->>'safe_to_archive'<>'false'
 or before_a::text like '%A secret message for later%'
 then raise exception 'A unmirrored census missing source counts or privacy: %',left(before_a::text,1800);end if;
 select count(*) into missing_family
 from (values('couple_letters'),('item_links'),('place_visits'),('record_action_history'),
 ('activity_comments'),('note_references'),('trip_revisions'),('scrapbook_pages'),('occasion_budget_log')) required(table_name)
 where not exists (
  select 1 from jsonb_array_elements(before_a->'per_table') t
  where t->>'source_table'=required.table_name
    and (t->>'private_rows')::int>0
 );
 if missing_family<>0 then raise exception 'Nine expected actual private source families omitted: %',missing_family;end if;
 select t->>'source_sha256' into oldhash from jsonb_array_elements(before_a->'per_table') t
 where t->>'source_table'='activity_comments';

 perform set_config('request.jwt.claim.sub',b::text,true);
 partner_b:=public.qa_unmirrored_private_source_census();
 if (partner_b->>'private_source_rows_checked')::int<>0
 or partner_b->>'owner_id'<>b::text
 then raise exception 'B census included A private sources: %',partner_b;end if;

 perform set_config('role','postgres',true);
 update public.activity_comments set body='Changed written activity conversation'
 where id=comment_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 after_a:=public.qa_unmirrored_private_source_census();
 select t->>'source_sha256' into newhash
 from jsonb_array_elements(after_a->'per_table') t
 where t->>'source_table'='activity_comments';
 if oldhash=newhash then
 raise exception 'Source comment edit did not update family hash';end if;

 perform set_config('role','postgres',true);
 insert into public.activity_comments(activity_id,author_id,body)
 values(activity_id,b,'Forbidden partner private comment');
 perform set_config('role','authenticated',true);
 begin
  perform public.qa_unmirrored_private_source_census();
  raise exception 'Foreign private activity author silently counted';
 exception when others then
  get stacked diagnostics err=message_text;
  if err<>'Unmirrored private child scope mismatch: activity_comments'
  then raise exception 'Unexpected author collision: %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: 19 unmirrored families, 9 nonempty owner-private types, original-owner privacy, per-table SHA changed with prose, foreign private child denied; rollback' result;
