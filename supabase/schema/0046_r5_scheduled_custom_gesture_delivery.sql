-- Deployed migration 20261113094659 onespace_r5_scheduled_personal_gestures
CREATE OR REPLACE FUNCTION private.send_due_gestures(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 cfg record;
 local_now timestamp;
 target_at timestamp;
 moment_kind text;
 phrases text[];
 item text;
 pos integer;
 sent integer := 0;
 custom_kind text;
 custom_message text;
 receipt_day date;
 sleeping boolean;
 current_time_local time;
begin
 for cfg in
  select s.id,s.space_id,s.sender_id,s.recipient_id,s.moment,
   p.time_zone,p.sleep_start_local,p.sleep_end_local,
   p.work_end_local,p.work_days
  from public.gesture_schedules s
  join public.profiles p on p.id=s.recipient_id
  where s.enabled=true and p.receive_automatic_gestures=true
   and p.sleep_start_local is not null
   and p.sleep_end_local is not null
   and p.time_zone is not null
   and exists (select 1 from pg_catalog.pg_timezone_names zones
    where zones.name=p.time_zone)
   and exists(select 1 from public.space_members m
    where m.space_id=s.space_id and m.user_id=s.sender_id)
   and exists(select 1 from public.space_members m
    where m.space_id=s.space_id and m.user_id=s.recipient_id)
 loop
  local_now:=p_at at time zone cfg.time_zone;
  receipt_day:=local_now::date;
  current_time_local:=local_now::time;
  target_at:=null;
  moment_kind:=null;
  phrases:=null;
  if cfg.moment='morning' and cfg.sleep_end_local is not null then
    target_at:=receipt_day + cfg.sleep_end_local + interval '15 minutes';
    moment_kind:='morning';
    phrases:=array[
      'Good morning, my love. Wishing you a gentle day.',
      'A warm morning thought for someone very special.',
      'May today bring you a hundred little smiles.',
      'Good morning! Love is cheering you on from afar.',
      'I hope your morning starts with something beautiful.',
      'The day begins with you in my heart.',
      'Sending you sunshine and a little extra courage.',
      'Morning hugs, delivered across the distance.',
      'I hope today brings you peace and happy surprises.',
      'Another day, another reminder that you are loved.'
    ];
  elsif cfg.moment='after_work' and cfg.work_end_local is not null
     and extract(isodow from local_now)::integer=any(cfg.work_days) then
    target_at:=receipt_day + cfg.work_end_local + interval '15 minutes';
    moment_kind:='support';
    phrases:=array[
      'Work is behind you. Sending a well-earned hug.',
      'I hope you can enjoy some rest now.',
      'You did enough today. Be gentle with yourself.',
      'I hope the rest of your evening feels peaceful.',
      'Your effort never goes unnoticed. Proud of you.',
      'May your evening be softer than your workday.',
      'Take a moment for yourself. You deserve it.',
      'Thinking of you as your workday winds down.',
      'Here is a little encouragement for the evening.',
      'Sending care and comfort after a busy day.'
    ];
  elsif cfg.moment='goodnight' and cfg.sleep_start_local is not null then
    target_at:=receipt_day + cfg.sleep_start_local - interval '20 minutes';
    moment_kind:='goodnight';
    phrases:=array[
      'Sweet dreams. You are loved more than words.',
      'Before sleep, a little reminder you are in my heart.',
      'May tonight bring you rest and beautiful dreams.',
      'Goodnight, my love. Rest your busy mind.',
      'Sending peaceful thoughts as bedtime approaches.',
      'A goodnight hug from miles away.',
      'I hope you fall asleep with a smile.',
      'Rest easy. Tomorrow holds another little beginning.',
      'Wishing you a calm and comforting night.',
      'Goodnight. Thinking of you with so much affection.'
    ];
  end if;
  if target_at is null or local_now<target_at
     or local_now>=target_at+interval '10 minutes' then continue; end if;
  -- Never send inside the recipient's configured sleep window.
  sleeping:=false;
  if cfg.sleep_start_local is not null and cfg.sleep_end_local is not null then
    if cfg.sleep_start_local<=cfg.sleep_end_local then
      sleeping:=current_time_local>=cfg.sleep_start_local
        and current_time_local<cfg.sleep_end_local;
    else
      sleeping:=current_time_local>=cfg.sleep_start_local
        or current_time_local<cfg.sleep_end_local;
    end if;
  end if;
  if sleeping then continue; end if;
  pos:=1+mod(
    (pg_catalog.hashtext(cfg.id::text||receipt_day::text)::bigint
      & 2147483647)::integer,
    array_length(phrases,1)
  );
  item:=phrases[pos];
  -- Personalized alternatives take precedence when the sending partner
  -- explicitly chose this ritual trigger and enabled that ritual.
  custom_kind:=null;
  custom_message:=null;
  select t.kind,t.message into custom_kind,custom_message
   from public.gesture_templates t
   where t.space_id=cfg.space_id and t.creator_id=cfg.sender_id
     and t.recipient_id=cfg.recipient_id
     and t.scheduled_moment=cfg.moment
   order by md5(t.id::text||receipt_day::text) limit 1;
  if custom_message is not null then
    item:=custom_message;
    moment_kind:=custom_kind;
  end if;
  insert into public.partner_gestures
   (space_id,sender_id,recipient_id,kind,message,automated,
    gesture_schedule_id,recipient_local_day)
   values(cfg.space_id,cfg.sender_id,cfg.recipient_id,
     moment_kind,item,true,cfg.id,receipt_day)
   on conflict do nothing;
  if found then sent:=sent+1; end if;
 end loop;
 return sent;
end;$function$
;
revoke all on function private.send_due_gestures(timestamptz) from public,anon,authenticated;
