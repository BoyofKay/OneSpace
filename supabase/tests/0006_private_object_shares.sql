-- Transactional authorization regression: tests rollback, preserving live data.
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
insert into public.tasks(space_id,created_by,title,visibility)
 values(current_setting('qa.space')::uuid,auth.uid(),'QA SHARED VIEW TASK','private');
insert into public.lists(space_id,created_by,title,visibility)
 values(current_setting('qa.space')::uuid,auth.uid(),'QA SHARED VIEW LIST','private');
insert into public.list_items(list_id,created_by,label)
 select id,auth.uid(),'QA VIEW CHILD' from public.lists where title='QA SHARED VIEW LIST';
insert into public.notes(space_id,created_by,title,body,visibility)
 values(current_setting('qa.space')::uuid,auth.uid(),'QA SHARED VIEW NOTE','private body','private');
select set_config('qa.task',(select id::text from public.tasks where title='QA SHARED VIEW TASK'),true);
select set_config('qa.list',(select id::text from public.lists where title='QA SHARED VIEW LIST'),true);
select set_config('qa.note',(select id::text from public.notes where title='QA SHARED VIEW NOTE'),true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
declare rejected boolean:=false;
begin
 if (select count(*) from public.tasks where id=current_setting('qa.task')::uuid)<>0 then raise exception 'Private task leaked before share'; end if;
 if (select count(*) from public.notes where id=current_setting('qa.note')::uuid)<>0 then raise exception 'Private note leaked before share'; end if;
 if (select count(*) from public.list_items where label='QA VIEW CHILD')<>0 then raise exception 'Private list child leaked before share'; end if;
 begin
   perform public.set_object_share('task',current_setting('qa.task')::uuid,true);
 exception when others then rejected:=true;
 end;
 if not rejected then raise exception 'Recipient granted themselves access'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.set_object_share('task',current_setting('qa.task')::uuid,true);
select public.set_object_share('list',current_setting('qa.list')::uuid,true);
select public.set_object_share('note',current_setting('qa.note')::uuid,true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
declare rejected boolean:=false;
begin
 if (select count(*) from public.tasks where id=current_setting('qa.task')::uuid)<>1 then raise exception 'Shared view-only task hidden'; end if;
 if (select count(*) from public.notes where id=current_setting('qa.note')::uuid)<>1 then raise exception 'Shared view-only note hidden'; end if;
 if (select count(*) from public.lists where id=current_setting('qa.list')::uuid)<>1 then raise exception 'Shared view-only list hidden'; end if;
 if (select count(*) from public.list_items where label='QA VIEW CHILD')<>1 then raise exception 'Shared view-only list item hidden'; end if;
 update public.tasks set title='QA INVALID EDIT' where id=current_setting('qa.task')::uuid;
 if found then raise exception 'Recipient edited view-only task'; end if;
 update public.notes set title='QA INVALID NOTE' where id=current_setting('qa.note')::uuid;
 if found then raise exception 'Recipient edited view-only note'; end if;
 update public.list_items set checked=true where list_id=current_setting('qa.list')::uuid;
 if found then raise exception 'Recipient edited view-only list item'; end if;
 begin
  insert into public.list_items(list_id,created_by,label)
    values(current_setting('qa.list')::uuid,auth.uid(),'QA ILLEGAL CHILD');
 exception when others then rejected:=true;
 end;
 if not rejected then raise exception 'Recipient added to view-only list'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.set_object_share('task',current_setting('qa.task')::uuid,false);
select public.set_object_share('list',current_setting('qa.list')::uuid,false);
select public.set_object_share('note',current_setting('qa.note')::uuid,false);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
begin
 if (select count(*) from public.tasks where id=current_setting('qa.task')::uuid)<>0 then raise exception 'Revoked task still visible'; end if;
 if (select count(*) from public.notes where id=current_setting('qa.note')::uuid)<>0 then raise exception 'Revoked note still visible'; end if;
 if (select count(*) from public.lists where id=current_setting('qa.list')::uuid)<>0 then raise exception 'Revoked list still visible'; end if;
 if (select count(*) from public.list_items where label='QA VIEW CHILD')<>0 then raise exception 'Revoked child still visible'; end if;
end $$;
select 'PASS: owner-controlled sharing, recipient read only, no child writes and immediate RLS revocation' as result;
rollback;
