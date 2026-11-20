-- QA: run as admin; all test data is rolled back. Test both private and
-- relationship ownership and private child-check/audit isolation.
begin;
select set_config('qa.owner',(select user_id::text from public.space_members order by user_id limit 1),true);
select set_config('qa.other',(select user_id::text from public.space_members
 where user_id::text<>current_setting('qa.owner') order by user_id limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $test$
declare v_owner uuid:=current_setting('qa.owner')::uuid;
 v_other uuid:=current_setting('qa.other')::uuid;
 v_task uuid; v_item uuid; v_check uuid; n integer;
begin
 insert into public.tasks(private_space_id,created_by,visibility,title,status)
 values(v_owner,v_owner,'private','Rollback-only private checklist','open')
 returning id into v_task;
 insert into public.task_checklist_items(task_id,title)
 values(v_task,'Rollback-only child item') returning id into v_item;
 insert into public.task_checklist_checks(item_id,cycle_date,completed)
 values(v_item,current_date,true) returning id into v_check;
 select count(*) into n from public.task_checklist_items i where i.task_id=v_task;
 if n<>1 then raise exception 'Owner cannot view personal checklist item';end if;
 select count(*) into n from public.task_checklist_checks c where c.task_id=v_task;
 if n<>1 then raise exception 'Owner cannot view personal checklist check';end if;
 select count(*) into n from public.record_action_history h
 where h.record_kind='task' and h.record_id=v_task
 and h.private_space_id=v_owner;
 if n<>1 then raise exception 'Owner cannot view task audit';end if;
 perform set_config('request.jwt.claim.sub',v_other::text,true);
 select count(*) into n from public.tasks t where t.id=v_task;
 if n<>0 then raise exception 'Other user read private task';end if;
 select count(*) into n from public.task_checklist_items i where i.id=v_item;
 if n<>0 then raise exception 'Other user read private child';end if;
 select count(*) into n from public.task_checklist_checks c where c.id=v_check;
 if n<>0 then raise exception 'Other user read private check';end if;
 select count(*) into n from public.record_action_history h where h.record_id=v_task;
 if n<>0 then raise exception 'Other user read private audit';end if;
 perform set_config('request.jwt.claim.sub',v_owner::text,true);
 update public.tasks set title='Updated private checklist' where id=v_task;
 select count(*) into n from public.tasks t where t.id=v_task
 and t.title='Updated private checklist';
 if n<>1 then raise exception 'Owner could not edit private task';end if;
end $test$;
rollback;
