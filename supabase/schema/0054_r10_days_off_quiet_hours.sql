-- Deployed 20261113120429 onespace_r10_respect_days_off_in_scheduled_gestures
do $migration$
declare source_sql text;
declare rest text;
declare marker text := ' loop
  local_now:=p_at at time zone cfg.time_zone;';
begin
 source_sql:=pg_get_functiondef('private.send_due_gestures(timestamptz)'::regprocedure);
 if strpos(source_sql,'p.work_end_local,p.work_days')=0 then
   raise exception 'Unexpected gesture function source';
 end if;
 source_sql:=replace(source_sql,
   'p.work_end_local,p.work_days',
   'p.work_end_local,p.work_days,
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
        and d.off_date=(p_at at time zone p.time_zone)::date) as is_day_off');
 if strpos(source_sql,marker)=0 then
  raise exception 'Gesture function loop not found';
 end if;
 rest:=substring(source_sql from strpos(source_sql,marker));
 rest:=replace(rest,'cfg.sleep_end_local','cfg.effective_wake');
 rest:=replace(rest,'cfg.sleep_start_local','cfg.effective_sleep');
 if strpos(rest,'and extract(isodow from local_now)::integer=any(cfg.work_days) then')=0 then
  raise exception 'Workday schedule guard not found';
 end if;
 rest:=replace(rest,'and extract(isodow from local_now)::integer=any(cfg.work_days) then',
   'and extract(isodow from local_now)::integer=any(cfg.work_days)
     and not cfg.is_day_off then');
 source_sql:=substring(source_sql from 1 for strpos(source_sql,marker)-1)||rest;
 execute source_sql;
end;$migration$;
