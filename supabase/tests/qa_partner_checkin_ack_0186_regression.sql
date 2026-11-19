-- QA 0186 rollback: sender/recipient-only acknowledgement, resolved
-- check-in requirement and original pair RLS.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid; outsider uuid; check_id uuid;
 p jsonb; msg text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b from public.spaces s
 join public.space_members m on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'Paired QA fixture unavailable';end if;
 select id into outsider from auth.users u where u.id not in
 (select user_id from public.space_members where space_id=sid) limit 1;

 insert into public.partner_checkin_requests(
   space_id,sender_id,recipient_id,note,responded_at,
   response_mood,response_message)
 values(sid,a,b,'QA checking on you',now(),4,'Thank you for checking in')
 returning id into check_id;
 insert into public.partner_checkin_acknowledgements(
   request_id,user_id,kind)
 values(check_id,a,'heart');
 if has_function_privilege('anon',
   'private.qa_checkin_ack_history_preview(uuid)','execute') then
   raise exception 'Anon allowed to fetch couple check-in history';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=private.qa_checkin_ack_history_preview(check_id);
 if p#>>'{payload,kind}'<>'shared_reference_only'
   or p#>>'{payload,acknowledgement,kind}'<>'heart'
   or p::text not like '%Thank you for checking in%'
   or p->>'can_restore'<>'false'
 then raise exception 'Sender check-in acknowledgement incomplete';end if;
 if p->>'payload_sha256'<>
    encode(extensions.digest(convert_to((p->'payload')::text,'UTF8'),'sha256'),'hex')
 then raise exception 'Checkin checksum mismatch';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 p:=private.qa_checkin_ack_history_preview(check_id);
 if p#>>'{payload,acknowledgement,user_id}'<>a::text
 then raise exception 'Recipient lost old shared acknowledgement';end if;
 if outsider is not null then
   perform set_config('request.jwt.claim.sub',outsider::text,true);
   begin
     perform private.qa_checkin_ack_history_preview(check_id);
     raise exception 'Outsider accessed check-in history';
   exception when others then
     get stacked diagnostics msg=message_text;
     if msg<>'Check-in history not found' then
       raise exception 'Wrong outsider result: %',msg;end if;
   end;
 end if;

 perform set_config('role','postgres',true);
 update public.partner_checkin_acknowledgements
   set user_id=b where request_id=check_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
   perform private.qa_checkin_ack_history_preview(check_id);
   raise exception 'Foreign member acknowledged sender-only receipt';
 exception when others then
   get stacked diagnostics msg=message_text;
   if msg<>'Check-in acknowledgement lineage or response mismatch' then
      raise exception 'Wrong sender receipt guard: %',msg;end if;
 end;
 perform set_config('role','postgres',true);
 update public.partner_checkin_acknowledgements
  set user_id=a where request_id=check_id;
 -- Create an unanswered request with an inconsistent receipt, rather
 -- than violating the app rule that prevents unanswering completed requests.
 insert into public.partner_checkin_requests(
    space_id,sender_id,recipient_id,note)
 values(sid,a,b,'QA pending check-in with illicit receipt')
 returning id into check_id;
 insert into public.partner_checkin_acknowledgements(
    request_id,user_id,kind) values(check_id,a,'hug');
 perform set_config('role','authenticated',true);
 begin
   perform private.qa_checkin_ack_history_preview(check_id);
   raise exception 'Acknowledgement attached to unanswered check-in';
 exception when others then
   get stacked diagnostics msg=message_text;
   if msg<>'Check-in acknowledgement lineage or response mismatch' then
     raise exception 'Wrong unfinished check-in guard: %',msg;end if;
 end;
end $qa$;
rollback;
select 'PASS: original pair shared check-in acknowledgements, SHA-256, outsider denial, author-only receipt and answered-only proof; rolled back' result;
