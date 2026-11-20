-- QA-only privileged RPC hardening: never disclose partner-private trip checklist IDs.
-- Existing private template may block a new one via unique index; fail closed on conflict.
-- Never mutates existing task rows, invitations, accounts or Production.
CREATE OR REPLACE FUNCTION public.create_trip_preparation_checklist(p_trip_id uuid, p_template text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t record; existing uuid; created uuid;
 title_text text; task_titles text[];
begin
 if auth.uid() is null or p_template not in
  ('travel_basics','leaving_home','with_baby','with_pets') then
  raise exception 'Invalid trip checklist template';
 end if;
 select id,space_id,title,visibility,created_by,start_on
 into t from public.shared_trips where id=p_trip_id;
 if not found or not private.is_space_member(t.space_id) or
  (t.visibility='private' and t.created_by<>auth.uid()) then
  raise exception 'Trip unavailable';
 end if;
 select id into existing from public.tasks where trip_id=p_trip_id
 and trip_template_key=p_template
 and space_id=t.space_id and (visibility='shared' or created_by=auth.uid()) limit 1;
 if existing is not null then return existing;end if;
 if p_template='travel_basics' then
  title_text='Travel essentials';
  task_titles:=array[
   'Verify passport, visa and identification',
   'Review baggage limits and seat reservations',
   'Download offline maps for destination',
   'Download music, shows and movies for the journey',
   'Save tickets and reservations for offline access',
   'Review departure and arrival local times',
   'Check travel insurance and emergency contacts',
   'Charge phone, headphones and power bank'];
 elsif p_template='leaving_home' then
  title_text='Leaving home';
  task_titles:=array[
   'Check flight status and check-in requirements',
   'Keep boarding pass and ID within easy reach',
   'Check baggage, keys and important documents',
   'Confirm airport ride and leave-home time',
   'Turn off appliances and secure the home',
   'Check doors, windows and pets before leaving'];
 elsif p_template='with_baby' then
  title_text='Traveling with our little one';
  task_titles:=array[
   'Pack diapers, wipes and spare clothes',
   'Prepare snacks, milk and travel essentials',
   'Keep baby travel documents handy',
   'Download favorite shows and soothing music',
   'Check stroller and child-seat airline policies',
   'Pack comfort item and baby medication as needed'];
 else
  title_text='Traveling with pets';
  task_titles:=array[
   'Confirm airline pet reservation and carrier rules',
   'Prepare vaccination and health certificates',
   'Check import permits and destination requirements',
   'Pack pet food, water, carrier and comfort items',
   'Confirm pet-friendly transfer and accommodation',
   'Keep veterinarian and emergency contacts available'];
 end if;
 insert into public.tasks(space_id,created_by,title,priority,status,
  target_date,visibility,recurrence,trip_id,trip_template_key)
 values(t.space_id,auth.uid(),left(title_text||' · '||t.title,120),
  'normal','open',t.start_on,t.visibility,'none',p_trip_id,p_template)
 on conflict(trip_id,trip_template_key)
 where trip_id is not null and trip_template_key is not null
 do nothing
 returning id into created;
 if created is null then
  select id into created from public.tasks where trip_id=p_trip_id
  and trip_template_key=p_template and space_id=t.space_id
  and (visibility='shared' or created_by=auth.uid());
  if created is null then
    raise exception 'Trip checklist unavailable' using errcode='42501';
  end if;
  return created;
 end if;
 insert into public.task_checklist_items(task_id,created_by,title,position)
 select created,auth.uid(),x.item,(x.n-1)::integer
 from unnest(task_titles) with ordinality as x(item,n);
 return created;
end $function$
