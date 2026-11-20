-- QA regression for personal Activity children: comments, replies, mentions,
-- notifications, edit history and component history.
-- Run inside BEGIN ... ROLLBACK only. A, B: couple db24ba25-…; C: outsider.
-- Each step raises on failure, so a clean run means every check passed.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';
  c uuid:='937e362d-6457-4fe2-b8cd-abad7157a015';
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  b_name text; mine uuid; ours uuid; comp uuid; note1 uuid; n int; failed boolean;
begin
  select coalesce(nullif(btrim(display_name),''),'Partner') into b_name
   from public.profiles where id=b;

  perform set_config('request.jwt.claims',json_build_object('sub',a,'role','authenticated')::text,true);
  set local role authenticated;
  insert into public.activities(private_space_id,created_by,visibility,title)
   values(a,a,'private','Personal plan') returning id into mine;
  insert into public.activities(space_id,created_by,visibility,title)
   values(couple,a,'shared','Shared plan') returning id into ours;
  -- 1. Comments and replies on a personal Activity.
  insert into public.activity_comments(activity_id,author_id,body)
   values(mine,a,'First thought @'||b_name) returning id into note1;
  insert into public.activity_comments(activity_id,author_id,body,reply_to)
   values(mine,a,'Follow-up',note1);
  select count(*) into n from public.activity_comments where activity_id=mine;
  if n<>2 then raise exception 'FAIL 1: owner cannot see own comments (%)',n; end if;
  -- 2. Edit history of the personal Activity and its component.
  insert into public.activity_components(activity_id,created_by,kind,label)
   values(mine,a,'note','Draft') returning id into comp;
  update public.activities set title='Personal plan v2' where id=mine;
  update public.activity_components set label='Draft v2' where id=comp;
  select count(*) into n from public.activity_revisions where activity_id=mine;
  if n<1 then raise exception 'FAIL 2: owner cannot see Activity edit history'; end if;
  select count(*) into n from public.activity_component_revisions where activity_id=mine;
  if n<1 then raise exception 'FAIL 3: owner cannot see component history'; end if;
  select count(*) into n from public.record_action_history
   where record_kind='activity' and record_id=mine;
  if n<1 then raise exception 'FAIL 4: owner cannot see Activity action history'; end if;
  -- Control: a mention on the SHARED Activity does notify the partner.
  insert into public.activity_comments(activity_id,author_id,body)
   values(ours,a,'Look @'||b_name);
  reset role;

  -- Partner B.
  perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.activity_comments where activity_id=mine;
  if n<>0 then raise exception 'FAIL 5: partner sees personal comments'; end if;
  select count(*) into n from public.activity_revisions where activity_id=mine;
  if n<>0 then raise exception 'FAIL 6: partner sees personal edit history'; end if;
  select count(*) into n from public.activity_component_revisions where activity_id=mine;
  if n<>0 then raise exception 'FAIL 7: partner sees personal component history'; end if;
  select count(*) into n from public.record_action_history
   where record_kind='activity' and record_id=mine;
  if n<>0 then raise exception 'FAIL 8: partner sees personal action history'; end if;
  failed:=false;
  begin insert into public.activity_comments(activity_id,author_id,body) values(mine,b,'Intrude');
  exception when others then failed:=true; end;
  if not failed then raise exception 'FAIL 9: partner commented on personal Activity'; end if;
  reset role;

  -- 10. A mention inside a personal Activity never notifies anyone.
  select count(*) into n from public.space_notifications
   where activity_id=mine or object_id in (mine,note1);
  if n<>0 then raise exception 'FAIL 10: personal Activity produced a notification'; end if;
  -- 11. Control: the shared mention did reach the partner.
  select count(*) into n from public.space_notifications
   where recipient_id=b and activity_id=ours;
  if n<1 then raise exception 'FAIL 11: shared mention did not notify partner'; end if;

  -- Outsider C.
  perform set_config('request.jwt.claims',json_build_object('sub',c,'role','authenticated')::text,true);
  set local role authenticated;
  select count(*) into n from public.activity_comments where activity_id in (mine,ours);
  if n<>0 then raise exception 'FAIL 12: outsider sees comments'; end if;
  select count(*) into n from public.activity_revisions where activity_id in (mine,ours);
  if n<>0 then raise exception 'FAIL 13: outsider sees edit history'; end if;
  reset role;
  raise notice 'PASS: 13 personal Activity children checks';
end $t$;
