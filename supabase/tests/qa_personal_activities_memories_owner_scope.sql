-- QA only: rollback-proof Activity + Memory scope contract.
-- Requires two members of one pair and an unrelated third user.
-- This file must never run against Production.
begin;
select set_config('qa.owner',(select sm.user_id::text from public.space_members sm
  order by sm.space_id,sm.user_id limit 1),true);
select set_config('qa.space',(select sm.space_id::text from public.space_members sm
  where sm.user_id::text=current_setting('qa.owner') limit 1),true);
select set_config('qa.partner',(select sm.user_id::text from public.space_members sm
  where sm.space_id::text=current_setting('qa.space')
    and sm.user_id::text<>current_setting('qa.owner') limit 1),true);
select set_config('qa.outsider',(select sm.user_id::text from public.space_members sm
  where sm.space_id::text<>current_setting('qa.space')
  order by sm.user_id limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $contract$
declare
 owner_id uuid:=current_setting('qa.owner')::uuid;
 partner_id uuid:=current_setting('qa.partner')::uuid;
 outsider_id uuid:=current_setting('qa.outsider')::uuid;
 shared_id uuid:=current_setting('qa.space')::uuid;
 private_activity uuid;
 shared_activity uuid;
 personal_memory uuid;
 shared_memory uuid;
 child_id uuid;
 cnt int;
begin
 if owner_id is null or partner_id is null or outsider_id is null or shared_id is null then
   raise exception 'Need a paired QA owner/partner and unrelated QA user';
 end if;
 insert into public.activities(private_space_id,created_by,visibility,title,body)
 values(owner_id,owner_id,'private','QA personal activity rollback','Personal only')
 returning id into private_activity;
 insert into public.activities(space_id,created_by,visibility,title,body)
 values(shared_id,owner_id,'shared','QA shared activity rollback','Shared by pair')
 returning id into shared_activity;
 insert into public.memories(private_space_id,created_by,visibility,title,body,memory_date,memory_type)
 values(owner_id,owner_id,'private','QA personal story rollback','Personal only',current_date,'story')
 returning id into personal_memory;
 insert into public.memories(space_id,created_by,visibility,title,body,memory_date,memory_type)
 values(shared_id,owner_id,'shared','QA shared memory rollback','Shared by pair',current_date,'story')
 returning id into shared_memory;
 insert into public.activity_components(activity_id,kind,label,payload)
 values(private_activity,'step','Private check', '{"status":"open"}'::jsonb)
 returning id into child_id;
 select count(*) into cnt from public.activity_components where id=child_id;
 if cnt<>1 then raise exception 'Owner cannot create/read private Activity child';end if;
 select count(*) into cnt from public.activities where id=private_activity
   and private_space_id=owner_id and space_id is null;
 if cnt<>1 then raise exception 'Owner cannot read private Activity';end if;
 select count(*) into cnt from public.memories where id=personal_memory
   and private_space_id=owner_id and space_id is null;
 if cnt<>1 then raise exception 'Owner cannot read personal Memory';end if;
 perform set_config('request.jwt.claim.sub',partner_id::text,true);
 select count(*) into cnt from public.activities where id=private_activity;
 if cnt<>0 then raise exception 'Partner read private Activity';end if;
 select count(*) into cnt from public.activity_components where id=child_id;
 if cnt<>0 then raise exception 'Partner read private Activity component';end if;
 select count(*) into cnt from public.memories where id=personal_memory;
 if cnt<>0 then raise exception 'Partner read personal Memory';end if;
 select count(*) into cnt from public.activities where id=shared_activity;
 if cnt<>1 then raise exception 'Partner cannot read shared Activity';end if;
 select count(*) into cnt from public.memories where id=shared_memory;
 if cnt<>1 then raise exception 'Partner cannot read shared Memory';end if;
 perform set_config('request.jwt.claim.sub',outsider_id::text,true);
 select count(*) into cnt from public.activities where id in (private_activity,shared_activity);
 if cnt<>0 then raise exception 'Outsider read unauthorized Activity';end if;
 select count(*) into cnt from public.memories where id in (personal_memory,shared_memory);
 if cnt<>0 then raise exception 'Outsider read unauthorized Memory';end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 update public.activities set body='Edited only by owner' where id=private_activity;
 update public.memories set body='Edited only by owner' where id=personal_memory;
 begin
  update public.activities set visibility='shared' where id=private_activity;
  raise exception 'BUG: client changed Activity ownership';
 exception when others then
  if sqlerrm='BUG: client changed Activity ownership' then raise;end if;
 end;
 begin
  update public.memories set visibility='shared' where id=personal_memory;
  raise exception 'BUG: client changed Memory ownership';
 exception when others then
  if sqlerrm='BUG: client changed Memory ownership' then raise;end if;
 end;
end $contract$;
rollback;
select 'PASS: Activity and Memory personal/shared isolation verified; all test records rolled back' as result;
