-- R25: PostgREST stores JWT role in claim JSON on modern gateways.
-- Use the canonical auth.role() helper, which supports both legacy and
-- structured request JWT claims. The function remains SERVICE_ROLE-ONLY.
CREATE OR REPLACE FUNCTION public.claim_push_outbox(p_limit integer DEFAULT 25)
 RETURNS TABLE(delivery_id uuid, registration_token text, notification_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.role() is distinct from 'service_role'
 then raise exception 'Backend service authorization required';end if;
 return query
 with candidates as(
   select o.id from private.push_outbox o
   join public.push_devices d on d.id=o.device_record_id
   join public.space_notifications n on n.id=o.notification_id
   where o.state in ('pending','leased')
     and (o.state='pending' or o.lease_until<now())
     and o.next_attempt_at<=now() and o.attempts<8
     and d.enabled and n.recipient_id=d.user_id
     and exists(select 1 from public.space_members m
       where m.space_id=n.space_id and m.user_id=n.recipient_id)
   order by o.next_attempt_at,o.created_at
   limit least(greatest(coalesce(p_limit,25),1),50)
   for update of o skip locked
 ),
 claimed as(
   update private.push_outbox o set state='leased',
      lease_until=now()+interval '3 minutes',attempts=o.attempts+1
   from candidates c where o.id=c.id
   returning o.id,o.device_record_id,o.notification_id
 )
 select c.id,d.fcm_token,c.notification_id from claimed c
 join public.push_devices d on d.id=c.device_record_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.complete_push_delivery(p_delivery uuid, p_result text, p_error text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.role() is distinct from 'service_role'
 then raise exception 'Backend service authorization required';end if;
 if p_result not in ('sent','retry','invalid') then
   raise exception 'Unknown push result';end if;
 if p_result='invalid' then
   update public.push_devices d set enabled=false
   from private.push_outbox o
   where o.id=p_delivery and d.id=o.device_record_id;
 end if;
 update private.push_outbox set
 state=case
   when p_result='sent' then 'sent'
   when p_result='invalid' or attempts>=8 then 'dead'
   else 'pending' end,
 lease_until=null,
 sent_at=case when p_result='sent' then now() else sent_at end,
 next_attempt_at=case when p_result='retry'
   then now()+make_interval(secs=>least(3600,60*power(2,least(attempts,5))::int))
   else next_attempt_at end,
 last_error=left(coalesce(p_error,''),320)
 where id=p_delivery and state='leased';
end $function$
;

revoke all on function public.claim_push_outbox(integer) from public,anon,authenticated;
grant execute on function public.claim_push_outbox(integer) to service_role;
revoke all on function public.complete_push_delivery(uuid,text,text) from public,anon,authenticated;
grant execute on function public.complete_push_delivery(uuid,text,text) to service_role;
