-- R32: One reply and one optional acknowledgment, rolled back entirely.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.partner_checkin_requests(space_id,sender_id,recipient_id,note)
 values(current_setting('qa.space')::uuid,current_setting('qa.a')::uuid,
 current_setting('qa.b')::uuid,'R32 ack protection QA');
select set_config('qa.req',(select id::text from public.partner_checkin_requests
 where note='R32 ack protection QA' limit 1),true);
do $qa$
declare denied boolean:=false;
begin
 begin
  insert into public.partner_checkin_acknowledgements(request_id,kind)
   values(current_setting('qa.req')::uuid,'heart');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Acknowledged an unanswered request';end if;
end $qa$;

select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
update public.partner_checkin_requests set response_mood=4,
 response_message='I am doing well' where id=current_setting('qa.req')::uuid;
do $qa$
declare denied boolean:=false;
begin
 begin
  insert into public.partner_checkin_acknowledgements(request_id,kind)
   values(current_setting('qa.req')::uuid,'heart');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Recipient impersonated sender acknowledgment';end if;
end $qa$;

select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.partner_checkin_acknowledgements(request_id,kind)
 values(current_setting('qa.req')::uuid,'heart');
update public.partner_checkin_acknowledgements set kind='thank_you'
 where request_id=current_setting('qa.req')::uuid;

select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
declare affected integer;
begin
 if (select kind from public.partner_checkin_acknowledgements
   where request_id=current_setting('qa.req')::uuid)<>'thank_you' then
  raise exception 'Partner cannot see sender acknowledgment';end if;
 update public.partner_checkin_acknowledgements set kind='hug'
  where request_id=current_setting('qa.req')::uuid;
 get diagnostics affected=row_count;
 if affected<>0 then raise exception 'Recipient changed sender acknowledgment';end if;
end $qa$;
select 'PASS: R32 answered-only sender acknowledgments, partner visibility and protected edits' result;
rollback;