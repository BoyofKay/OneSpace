-- R12: unify ten legacy automatic ritual phrases with editable manual gesture pools.
-- Preserves consent, quiet hours, days off, one send per day and cross-type scheduled customs.
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
 manual_phrases text[];
 baseline_phrases text[];
 custom_phrases text[];
 receipt_day date;
 sleeping boolean;
 current_time_local time;
begin
 for cfg in
  select s.id,s.space_id,s.sender_id,s.recipient_id,s.moment,
   p.time_zone,p.sleep_start_local,p.sleep_end_local,
   p.work_end_local,p.work_days,
    coalesce((select d.off_day_wake_at from public.personal_days_off d
      where d.user_id=s.recipient_id
        and d.off_date=(p_at at time zone p.time_zone)::date),
       p.sleep_end_local) as effective_wake,
    coalesce((select d.night_before_sleep_at from public.personal_days_off d
      where d.user_id=s.recipient_id
        and d.off_date=(p_at at time zone p.time_zone)::date+1),
       p.sleep_start_local) as effective_sleep,
    exists(select 1 from public.personal_days_off d
      where d.user_id=s.recipient_id
        and d.off_date=(p_at at time zone p.time_zone)::date) as is_day_off
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
  if cfg.moment='morning' and cfg.effective_wake is not null then
    target_at:=receipt_day + cfg.effective_wake + interval '15 minutes';
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
     and extract(isodow from local_now)::integer=any(cfg.work_days)
     and not cfg.is_day_off then
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
  elsif cfg.moment='goodnight' and cfg.effective_sleep is not null then
    target_at:=receipt_day + cfg.effective_sleep - interval '20 minutes';
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
  if cfg.effective_sleep is not null and cfg.effective_wake is not null then
    if cfg.effective_sleep<=cfg.effective_wake then
      sleeping:=current_time_local>=cfg.effective_sleep
        and current_time_local<cfg.effective_wake;
    else
      sleeping:=current_time_local>=cfg.effective_sleep
        or current_time_local<cfg.effective_wake;
    end if;
  end if;
  if sleeping then continue; end if;
  -- R12: use exactly the same per-sender gesture pool as the manual UI.
  -- The first three positions are manual presets; positions 3..12 are
  -- the ten original server-side ritual phrases (in original order).
  manual_phrases:=case moment_kind
    when 'morning' then array[
      'Good morning, my love. I hope your day is kind to you.',
      'Wishing you a gentle and beautiful morning.',
      'A morning kiss and a whole lot of love for you.'
    ]
    when 'support' then array[
      'I am here for you, even from far away.',
      'You do not have to carry today alone.',
      'You have got this. I believe in you.'
    ]
    when 'goodnight' then array[
      'Sweet dreams. I am holding you in my heart.',
      'Goodnight, my love. Rest well.',
      'The day is ending, but my love for you never does.'
    ]
    else array[]::text[] end;
  baseline_phrases:=manual_phrases || phrases;
  select array_agg(coalesce(o.message,baseline_phrases[s.idx]) order by s.idx)
   into phrases
  from generate_subscripts(baseline_phrases,1) as s(idx)
  left join public.gesture_message_overrides o
    on o.space_id=cfg.space_id and o.owner_id=cfg.sender_id
   and o.kind=moment_kind and o.message_index=s.idx-1
  where coalesce(o.disabled,false)=false;
  -- Only explicitly scheduled personal messages may be sent automatically.
  -- Same-type personal messages participate in the common randomized pool.
  select array_agg(t.message order by t.created_at,t.id)
   into custom_phrases from public.gesture_templates t
   where t.space_id=cfg.space_id and t.creator_id=cfg.sender_id
     and t.recipient_id=cfg.recipient_id
     and t.kind=moment_kind and t.scheduled_moment=cfg.moment;
  phrases:=coalesce(phrases,array[]::text[])
    ||coalesce(custom_phrases,array[]::text[]);
  if coalesce(array_length(phrases,1),0)=0 then continue; end if;
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
     and t.kind<>moment_kind
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
