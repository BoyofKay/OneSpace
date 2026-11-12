-- ROLLBACK-only live paired-user privacy checks. Never writes lasting test data.
begin;
-- Test existing paired accounts with rolled-back records; no live data persists.
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
insert into public.lists(space_id,created_by,title,kind,visibility)
values
(current_setting('qa.space')::uuid,auth.uid(),'QA SHARED SHOPPING','shopping','shared'),
(current_setting('qa.space')::uuid,auth.uid(),'QA PRIVATE LIST','checklist','private');
insert into public.list_items(list_id,created_by,label,quantity,unit)
select id,auth.uid(),'QA milk',2,'litres' from public.lists
where title='QA SHARED SHOPPING';
insert into public.list_items(list_id,created_by,label)
select id,auth.uid(),'QA secret entry' from public.lists
where title='QA PRIVATE LIST';
insert into public.notes(space_id,created_by,title,body,visibility)
values
(current_setting('qa.space')::uuid,auth.uid(),'QA PRIVATE NOTE','secret draft','private'),
(current_setting('qa.space')::uuid,auth.uid(),'QA SHARED NOTE','shared text','shared');
select set_config('qa.shared_list',(select id::text from public.lists where title='QA SHARED SHOPPING'),true);
select set_config('qa.private_list',(select id::text from public.lists where title='QA PRIVATE LIST'),true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
declare denied boolean:=false;
begin
 if (select count(*) from public.lists where title='QA SHARED SHOPPING') <> 1
   then raise exception 'Partner cannot see shared shopping list'; end if;
 if (select count(*) from public.list_items where label='QA milk') <> 1
   then raise exception 'Partner cannot see shared shopping item'; end if;
 if (select count(*) from public.notes where title='QA SHARED NOTE') <> 1
   then raise exception 'Partner cannot see shared note'; end if;
 if (select count(*) from public.lists where title='QA PRIVATE LIST') <> 0
   then raise exception 'Partner can read private list'; end if;
 if (select count(*) from public.list_items where label='QA secret entry') <> 0
   then raise exception 'Partner can read private list item'; end if;
 if (select count(*) from public.notes where title='QA PRIVATE NOTE') <> 0
   then raise exception 'Partner can read private note'; end if;
 update public.list_items set checked=true where label='QA milk';
 if not found then raise exception 'Partner cannot check shared shopping item'; end if;
 update public.notes set body='QA partner edit' where title='QA SHARED NOTE';
 if not found then raise exception 'Partner cannot edit shared note'; end if;
 begin
  insert into public.list_items(list_id,created_by,label)
  values (current_setting('qa.private_list')::uuid,auth.uid(),'QA illicit');
 exception when others then denied:=true;
 end;
 if not denied then raise exception 'Partner inserted private list item'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
do $$
declare denied boolean := false;
begin
 begin
  update public.notes set visibility='shared' where title='QA PRIVATE NOTE';
 exception when others then denied := true;
 end;
 if not denied then raise exception 'Note visibility is mutable'; end if;
end $$;
select 'PASS: shared item CRUD, note collaboration, private parent and child RLS, immutable visibility' as result;
rollback;
