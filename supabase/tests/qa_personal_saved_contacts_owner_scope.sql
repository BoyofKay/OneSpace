-- QA contact scope regression. Always rolled back. No real user data changed.
begin;
select set_config('qa.owner',(select sm.user_id::text from public.space_members sm
 order by sm.space_id,sm.user_id limit 1),true);
select set_config('qa.space',(select sm.space_id::text from public.space_members sm
 where sm.user_id::text=current_setting('qa.owner') limit 1),true);
select set_config('qa.partner',(select sm.user_id::text from public.space_members sm
 where sm.space_id::text=current_setting('qa.space') and
 sm.user_id::text<>current_setting('qa.owner') limit 1),true);
select set_config('qa.stranger',(select sm.user_id::text from public.space_members sm
 where sm.space_id::text<>current_setting('qa.space') order by sm.user_id limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
set local role authenticated;
do $checks$
declare
 own uuid:=current_setting('qa.owner')::uuid;
 partner uuid:=current_setting('qa.partner')::uuid;
 outsider uuid:=current_setting('qa.stranger')::uuid;
 couple uuid:=current_setting('qa.space')::uuid;
 personal_id uuid;
 shared_id uuid;
 num integer;
begin
 if own is null or partner is null or outsider is null then
   raise exception 'Need QA paired users and an outsider';
 end if;
 insert into public.saved_contacts(private_space_id,created_by,visibility,label,payload)
 values(own,own,'private','QA private contact',jsonb_build_object('phone','+10000000001'))
 returning id into personal_id;
 insert into public.saved_contacts(space_id,created_by,visibility,label,payload)
 values(couple,own,'shared','QA shared contact','{}'::jsonb)
 returning id into shared_id;
 select count(*) into num from public.saved_contacts where id=personal_id
   and private_space_id=own and space_id is null;
 if num<>1 then raise exception 'Owner cannot read their private contact';end if;
 update public.saved_contacts set label='QA edited personal contact' where id=personal_id;
 select count(*) into num from public.saved_contact_revisions where contact_id=personal_id;
 if num<1 then raise exception 'Personal contact edit history missing';end if;
 perform set_config('request.jwt.claim.sub',partner::text,true);
 select count(*) into num from public.saved_contacts where id=personal_id;
 if num<>0 then raise exception 'Partner read a private contact';end if;
 select count(*) into num from public.saved_contact_revisions where contact_id=personal_id;
 if num<>0 then raise exception 'Partner read private contact history';end if;
 select count(*) into num from public.saved_contacts where id=shared_id;
 if num<>1 then raise exception 'Partner cannot read shared contact';end if;
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 select count(*) into num from public.saved_contacts where id in (personal_id,shared_id);
 if num<>0 then raise exception 'Outsider read a scoped contact';end if;
 perform set_config('request.jwt.claim.sub',own::text,true);
 begin
  update public.saved_contacts set visibility='shared' where id=personal_id;
  raise exception 'BUG: client can expose personal contact';
 exception when others then
  if sqlerrm='BUG: client can expose personal contact' then raise;end if;
 end;
 begin
  update public.saved_contacts set visibility='private' where id=shared_id;
  raise exception 'BUG: client can appropriate shared contact';
 exception when others then
  if sqlerrm='BUG: client can appropriate shared contact' then raise;end if;
 end;
end $checks$;
rollback;
select 'PASS: private and shared contact read, edit, history and immutability; rolled back' result;
