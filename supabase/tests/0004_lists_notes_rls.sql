-- R21: the retired shopping-list module is replaced by task-based checklists.
-- ROLLBACK-only tests: never persist the synthetic paired-user records.
begin;
select set_config('qa.space',space_id::text,true)
from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
from public.space_members where space_id=current_setting('qa.space')::uuid
order by joined_at,user_id limit 1;
select set_config('qa.b',user_id::text,true)
from public.space_members where space_id=current_setting('qa.space')::uuid
order by joined_at desc,user_id desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);

insert into public.tasks(space_id,created_by,title,visibility,priority,status,recurrence)
values
 (current_setting('qa.space')::uuid,auth.uid(),'QA CHECKLIST SHARED','shared','normal','open','daily'),
 (current_setting('qa.space')::uuid,auth.uid(),'QA CHECKLIST PRIVATE','private','normal','open','none');
insert into public.task_checklist_items(task_id,title)
select id,'QA shared item' from public.tasks where title='QA CHECKLIST SHARED';
insert into public.task_checklist_items(task_id,title)
select id,'QA secret item' from public.tasks where title='QA CHECKLIST PRIVATE';
insert into public.notes(space_id,created_by,title,body,visibility)
values
 (current_setting('qa.space')::uuid,auth.uid(),'QA PRIVATE NOTE','secret draft','private'),
 (current_setting('qa.space')::uuid,auth.uid(),'QA SHARED NOTE','shared text','shared');

select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
declare denied boolean:=false;
begin
 if (select count(*) from public.task_checklist_items where title='QA shared item')<>1
 then raise exception 'Shared checklist item not readable'; end if;
 if (select count(*) from public.task_checklist_items where title='QA secret item')<>0
 then raise exception 'Private checklist item leaked'; end if;
 if (select count(*) from public.notes where title='QA SHARED NOTE')<>1
 then raise exception 'Shared note missing'; end if;
 if (select count(*) from public.notes where title='QA PRIVATE NOTE')<>0
 then raise exception 'Private note leaked'; end if;
 insert into public.task_checklist_checks(item_id,cycle_date,completed)
 select id,date '2026-11-14',true from public.task_checklist_items
 where title='QA shared item';
 update public.notes set body='QA partner edit' where title='QA SHARED NOTE';
 if not found then raise exception 'Partner cannot edit shared note'; end if;
 begin
  insert into public.task_checklist_items(task_id,title)
   select id,'Unauthorized' from public.tasks where title='QA CHECKLIST PRIVATE';
  if found then denied:=true; end if;
 exception when others then denied:=true;
 end;
 if not denied then raise exception 'Unexpected visibility of private checklist'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.task_checklist_checks(item_id,cycle_date,completed)
 select id,date '2026-11-14',true from public.task_checklist_items
 where title='QA shared item';
do $$
begin
 if (select count(*) from public.task_checklist_checks c
 join public.task_checklist_items i on i.id=c.item_id
 where i.title='QA shared item' and c.cycle_date=date '2026-11-14')<>2
 then raise exception 'Two partners must have independent checkmarks'; end if;
end $$;
select 'PASS: new shared/private checklists, per-partner checks, notes privacy' as result;
rollback;
