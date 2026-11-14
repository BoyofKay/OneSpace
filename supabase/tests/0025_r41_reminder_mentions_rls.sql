-- R41 mention delivery under both account scopes, rollback only.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;
select set_config('qa.partner_name',coalesce(
 (select display_name from public.profiles where id=
  current_setting('qa.b')::uuid),''),true);
do $qa$ begin
 if length(btrim(current_setting('qa.partner_name')))=0 then
  raise exception 'Missing partner display name for mention test';end if;
end $qa$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.reminders(space_id,title,details,due_at,
 visibility,audience)
 values(current_setting('qa.space')::uuid,'R41 mention QA',
 'Please review @'||current_setting('qa.partner_name'),now()+interval '2 days',
 'shared','both'),
 (current_setting('qa.space')::uuid,'R41 private no mention',
 'Please review @'||current_setting('qa.partner_name'),now()+interval '2 days',
 'private','me');
-- Notifications are recipient-visible only. The sender cannot SELECT
-- the recipient's notification under production RLS.
select set_config('qa.reminder',(select id::text from public.reminders
 where title='R41 mention QA' limit 1),true);
select set_config('qa.private',(select id::text from public.reminders
 where title='R41 private no mention' limit 1),true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
declare cnt int;
begin
 select count(*) into cnt from public.space_notifications
  where object_kind='reminder' and kind='mention'
   and object_id=current_setting('qa.reminder')::uuid
   and recipient_id=current_setting('qa.b')::uuid
   and actor_id=current_setting('qa.a')::uuid;
 if cnt<>1 then raise exception 'Shared mention notification missing, found %',cnt;end if;
 if exists(select 1 from public.space_notifications
  where object_id=current_setting('qa.private')::uuid and kind='mention')then
   raise exception 'Private reminder accidentally pinged partner';end if;
 if exists(select 1 from public.reminders
  where title='R41 private no mention')then
   raise exception 'Partner sees private reminder';end if;
end $qa$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
update public.reminders set details='No mention here'
 where id=current_setting('qa.reminder')::uuid;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
declare cnt int;
begin
 select count(*) into cnt from public.space_notifications
 where object_id=current_setting('qa.reminder')::uuid and kind='mention';
 if cnt<>1 then raise exception 'Unrelated edit duplicated notification';end if;
end $qa$;
select 'PASS: R41 shared authorized @partner triggers one alert; private remains invisible' result;
rollback;
