begin;
do $qa$
declare
 sid uuid;a uuid;b uuid;experience_id uuid;comment_id uuid;
 ack_id uuid; first_a jsonb;first_b jsonb;after_a jsonb;after_b jsonb;
 hash_a text;hash_b text;err text;
begin
 select s.id,s.created_by,sm.user_id into sid,a,b
 from public.spaces s join public.space_members sm on sm.space_id=s.id and sm.user_id<>s.created_by
 where (select count(*) from public.space_members m where m.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'Original couple fixture missing';end if;
 if has_function_privilege('anon','public.qa_shared_only_source_census()','execute')
 or has_function_privilege('anon','private.qa_shared_only_source_census()','execute')
 then raise exception 'Unauthenticated shared census accessible';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.shared_experiences(space_id,created_by,category,title,description)
 values(sid,a,'movie','QA shared experienced film','A movie we remember together') returning id into experience_id;
 insert into public.shared_experience_comments(experience_id,created_by,body)
 values(experience_id,a,'A visible written memory');
 insert into public.shared_experience_comments(experience_id,created_by,body)
 values(experience_id,b,'B hidden archived letter') returning id into comment_id;
 insert into public.shared_experience_interests(experience_id,user_id,choice)
 values(experience_id,a,'yes');
 insert into public.shared_experience_reviews(experience_id,user_id,rating,review)
 values(experience_id,b,5,'Wonderful shared experience');
 insert into public.shared_experience_revisions(experience_id,changed_by,before_snapshot,after_snapshot)
 values(experience_id,a,'{"description":"Before"}','{"description":"After","photo_1_id":"88888888-2222-4333-8444-555555555555"}');
 insert into public.partner_gestures(space_id,sender_id,recipient_id,kind,message)
 values(sid,a,b,'hug','Hope you have a lovely day');
 insert into public.partner_checkin_requests(space_id,sender_id,recipient_id,note,responded_at,response_mood,response_message)
 values(sid,a,b,'How are you today?',now(),4,'Feeling happy')
 returning id into ack_id;
 insert into public.partner_checkin_acknowledgements(request_id,user_id,kind)
 values(ack_id,a,'heart');
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 first_a:=public.qa_shared_only_source_census();
 if (first_a->>'shared_only_table_types_checked')::int<>12
  or first_a->>'can_restore'<>'false'
  or first_a->>'safe_to_separate'<>'false'
  or first_a::text like '%Wonderful shared experience%'
  or first_a::text like '%B hidden archived letter%'
 then raise exception 'Shared-only census leaks raw member text';end if;
 select x->>'source_sha256' into hash_a from jsonb_array_elements(first_a->'per_table') x
 where x->>'source_table'='shared_experience_comments';
 perform set_config('request.jwt.claim.sub',b::text,true);
 first_b:=public.qa_shared_only_source_census();
 select x->>'source_sha256' into hash_b from jsonb_array_elements(first_b->'per_table') x
 where x->>'source_table'='shared_experience_comments';
 if hash_a<>hash_b then
 raise exception 'Shared comments should match before archive transition';end if;
 perform set_config('role','postgres',true);
 update public.shared_experience_comments set archived_at=now()
 where id=comment_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 after_a:=public.qa_shared_only_source_census();
 select x->>'source_sha256' into hash_a from jsonb_array_elements(after_a->'per_table') x
 where x->>'source_table'='shared_experience_comments';
 perform set_config('request.jwt.claim.sub',b::text,true);
 after_b:=public.qa_shared_only_source_census();
 select x->>'source_sha256' into hash_b from jsonb_array_elements(after_b->'per_table') x
 where x->>'source_table'='shared_experience_comments';
 if hash_a=hash_b then
 raise exception 'Partner A fingerprint includes B archived comment';end if;
 if (select (x->>'visible_shared_rows')::int
 from jsonb_array_elements(after_a->'per_table') x
 where x->>'source_table'='shared_experience_comments')<>1
 or (select (x->>'visible_shared_rows')::int
 from jsonb_array_elements(after_b->'per_table') x
 where x->>'source_table'='shared_experience_comments')<>2
 then raise exception 'Archived comment recipient author-only counts incorrect';end if;
 perform set_config('role','postgres',true);
 update public.partner_checkin_requests set responded_at=null,response_mood=null
 where id=ack_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
  perform public.qa_shared_only_source_census();
  raise exception 'Shared check-in receipt on unanswered request accepted';
 exception when others then
  get stacked diagnostics err=message_text;
  if err<>'Shared-only dependent privacy or response mismatch: partner_checkin_acknowledgements'
  then raise exception 'Unexpected unanswered receipt denial: %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: 12 shared-only families, author-only archived comment hashes, both partners see live content, malformed check-in receipt blocks shared manifest; rollback' result;
