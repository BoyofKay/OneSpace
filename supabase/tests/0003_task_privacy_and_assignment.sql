-- Transactional regression test; all task inserts/changes are rolled back.
begin;
-- Use existing paired account IDs; all test task modifications are rolled back.
select set_config('qa.space', space_id::text, true)
from public.space_members group by space_id having count(*) = 2 limit 1;
select set_config('qa.first',user_id::text,true)
from public.space_members where space_id=current_setting('qa.space')::uuid
order by joined_at asc,user_id limit 1;
select set_config('qa.second',user_id::text,true)
from public.space_members where space_id=current_setting('qa.space')::uuid
order by joined_at desc,user_id desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.first'),true);
insert into public.tasks (space_id,created_by,title,visibility,priority,status)
values (current_setting('qa.space')::uuid,auth.uid(),'QA PRIVATE - rollback','private','low','open');
insert into public.tasks (space_id,created_by,title,visibility,priority,status,assigned_to)
values (current_setting('qa.space')::uuid,auth.uid(),'QA SHARED - rollback','shared','normal','open',current_setting('qa.second')::uuid);
do $$
begin
  if (select count(*) from public.tasks where title='QA PRIVATE - rollback')<>1 then
    raise exception 'Owner cannot read private task';
  end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.second'),true);
do $$
declare blocked boolean := false;
begin
  if (select count(*) from public.tasks where title='QA PRIVATE - rollback')<>0 then
    raise exception 'PRIVATE TASK LEAK: partner can see owner-only task';
  end if;
  if (select count(*) from public.tasks where title='QA SHARED - rollback')<>1 then
    raise exception 'Partner cannot read assigned shared task';
  end if;
  update public.tasks set status='completed' where title='QA SHARED - rollback';
  if not found then raise exception 'Partner cannot complete shared task'; end if;
  begin
    update public.tasks set assigned_to='cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid
    where title='QA SHARED - rollback';
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'OUTSIDER ASSIGNMENT WAS ACCEPTED'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.first'),true);
do $$
declare blocked boolean := false;
begin
  begin
    update public.tasks set visibility='shared' where title='QA PRIVATE - rollback';
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'PRIVATE VISIBILITY COULD BE MUTATED'; end if;
end $$;
select 'PASS: partner shared assignment, private task isolation, fixed privacy, invalid assignment rejected' as result;
rollback;
