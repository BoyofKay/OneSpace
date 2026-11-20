-- QA regression: personal inbox text/links versus current couple, no private files.
begin;
select set_config('qa.owner',(select user_id::text from public.space_members order by space_id,user_id limit 1),true);
select set_config('qa.space',(select space_id::text from public.space_members where user_id::text=current_setting('qa.owner') limit 1),true);
select set_config('qa.partner',(select user_id::text from public.space_members
 where space_id::text=current_setting('qa.space') and user_id::text<>current_setting('qa.owner') limit 1),true);
select set_config('qa.outsider',(select user_id::text from public.space_members where space_id::text<>current_setting('qa.space') limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $tests$
declare o uuid:=current_setting('qa.owner')::uuid;
 p uuid:=current_setting('qa.partner')::uuid; x uuid:=current_setting('qa.outsider')::uuid;
 s uuid:=current_setting('qa.space')::uuid; private_item uuid; shared_item uuid; n int;
begin
 if o is null or p is null or x is null then raise exception 'QA pair and unrelated user needed';end if;
 insert into public.items_to_sort(private_space_id,created_by,visibility,title,note,link)
 values(o,o,'private','QA private text inbox rollback','A note','https://example.org')
 returning id into private_item;
 insert into public.items_to_sort(space_id,created_by,visibility,title,note)
 values(s,o,'shared','QA shared inbox rollback','Shared note')
 returning id into shared_item;
 select count(*) into n from public.record_action_history where record_id=private_item and private_space_id=o;
 if n<>1 then raise exception 'Private inbox audit missing';end if;
 perform set_config('request.jwt.claim.sub',p::text,true);
 select count(*) into n from public.items_to_sort where id=private_item;
 if n<>0 then raise exception 'Partner sees private inbox';end if;
 select count(*) into n from public.record_action_history where record_id=private_item;
 if n<>0 then raise exception 'Partner sees private inbox audit';end if;
 select count(*) into n from public.items_to_sort where id=shared_item;
 if n<>1 then raise exception 'Partner cannot see shared inbox';end if;
 perform set_config('request.jwt.claim.sub',x::text,true);
 select count(*) into n from public.items_to_sort where id in(private_item,shared_item);
 if n<>0 then raise exception 'Outsider sees scoped inbox';end if;
 perform set_config('request.jwt.claim.sub',o::text,true);
 update public.items_to_sort set note='Edited by owner' where id=private_item;
 begin
  update public.items_to_sort set visibility='shared' where id=private_item;
  raise exception 'BUG: raw UPDATE exposed private inbox';
 exception when others then
  if sqlerrm='BUG: raw UPDATE exposed private inbox' then raise;end if;
 end;
 begin
  insert into public.items_to_sort(private_space_id,created_by,visibility,title,file_path)
   values(o,o,'private','QA forbidden private file','fake/fileroute.pdf');
  raise exception 'BUG: personal file stored in unapproved bucket';
 exception when others then
  if sqlerrm='BUG: personal file stored in unapproved bucket' then raise;end if;
 end;
 begin
  insert into public.items_to_sort(space_id,created_by,visibility,title)
   values(s,o,'private','QA stale couple-private inbox');
  raise exception 'BUG: stale couple-private item allowed';
 exception when others then
  if sqlerrm='BUG: stale couple-private item allowed' then raise;end if;
 end;
end $tests$;
rollback;
select 'PASS personal text inbox, pair, outsider, audit, immutable scope and blocked file; rolled back' result;
