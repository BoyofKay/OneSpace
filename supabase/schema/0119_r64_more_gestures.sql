-- R64: eight new love-gesture types.
do $$ declare c text; begin
  select conname into c from pg_constraint where conrelid='public.partner_gestures'::regclass and pg_get_constraintdef(oid) ilike '%miss_pets%';
  if c is not null then execute format('alter table public.partner_gestures drop constraint %I', c); end if;
end $$;
alter table public.partner_gestures add constraint partner_gestures_kind_check check (kind = any (array['hug','thinking','smile','morning','goodnight','proud','support','thanks','lucky','miss_you','miss_together','miss_home','miss_kids','miss_pets','love_you','kiss','sorry','celebrate','get_well','safe_travels','call_me','date_night']));
do $$ declare c text; begin
  select conname into c from pg_constraint where conrelid='public.gesture_templates'::regclass and pg_get_constraintdef(oid) ilike '%miss_pets%';
  if c is not null then execute format('alter table public.gesture_templates drop constraint %I', c); end if;
end $$;
alter table public.gesture_templates add constraint gesture_templates_kind_check check (kind = any (array['hug','thinking','smile','morning','goodnight','proud','support','thanks','lucky','miss_you','miss_together','miss_home','miss_kids','miss_pets','love_you','kiss','sorry','celebrate','get_well','safe_travels','call_me','date_night']));
do $$ declare c text; begin
  select conname into c from pg_constraint where conrelid='public.gesture_message_overrides'::regclass and pg_get_constraintdef(oid) ilike '%miss_pets%';
  if c is not null then execute format('alter table public.gesture_message_overrides drop constraint %I', c); end if;
end $$;
alter table public.gesture_message_overrides add constraint gesture_message_overrides_kind_check check (kind = any (array['hug','thinking','smile','morning','goodnight','proud','support','thanks','lucky','miss_you','miss_together','miss_home','miss_kids','miss_pets','love_you','kiss','sorry','celebrate','get_well','safe_travels','call_me','date_night']));
do $$ declare c text; begin
  select conname into c from pg_constraint where conrelid='public.reminders'::regclass and pg_get_constraintdef(oid) ilike '%miss_pets%';
  if c is not null then execute format('alter table public.reminders drop constraint %I', c); end if;
end $$;
alter table public.reminders add constraint reminders_reminder_gesture_kind_check check (reminder_gesture_kind = any (array['any','hug','thinking','smile','morning','goodnight','proud','support','thanks','lucky','miss_you','miss_together','miss_home','miss_kids','miss_pets','love_you','kiss','sorry','celebrate','get_well','safe_travels','call_me','date_night']));
do $m$
declare d text;
begin
  select pg_get_functiondef('private.compose_notification_text'::regproc) into d;
  if position('''love_you''' in d)=0 then
    d:=replace(d, $x$when 'miss_pets' then 'يشتاق للحيوانات الأليفة'$x$, $x$when 'miss_pets' then 'يشتاق للحيوانات الأليفة'
       when 'love_you' then 'يقول أحبك'
       when 'kiss' then 'أرسل لك قبلة'
       when 'sorry' then 'يعتذر لك'
       when 'celebrate' then 'يحتفل بك'
       when 'get_well' then 'يتمنى لك الشفاء'
       when 'safe_travels' then 'يتمنى لك رحلة آمنة'
       when 'call_me' then 'يتمنى مكالمة منك'
       when 'date_night' then 'متحمس لموعدكما'$x$);
    d:=replace(d, $x$when 'miss_pets' then 'misses the pets'$x$, $x$when 'miss_pets' then 'misses the pets'
       when 'love_you' then 'says I love you'
       when 'kiss' then 'sent you a kiss'
       when 'sorry' then 'says sorry'
       when 'celebrate' then 'is celebrating you'
       when 'get_well' then 'hopes you feel better'
       when 'safe_travels' then 'wishes you safe travels'
       when 'call_me' then 'would love a call'
       when 'date_night' then 'is excited for your date'$x$);
    execute d;
  end if;
end $m$;
