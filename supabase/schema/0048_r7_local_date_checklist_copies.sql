-- Deployed 20261113103006 onespace_r7_local_day_for_reusable_checklist_copies
drop function public.create_checklist_from_template(uuid);
CREATE OR REPLACE FUNCTION public.create_checklist_from_template(p_template_id uuid, p_local_day date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid;
  source_list public.lists%rowtype;
  new_list uuid;
  total_items integer;
  local_date text;
begin
  actor := (select auth.uid());
  if actor is null then raise exception 'Sign in required'; end if;

  select * into source_list
  from public.lists
  where id=p_template_id and kind='checklist'
    and is_template=true and archived_at is null;
  if not found then raise exception 'Reusable checklist unavailable'; end if;

  if not exists(select 1 from public.space_members m
     where m.space_id=source_list.space_id and m.user_id=actor)
     or (source_list.visibility='private' and source_list.created_by<>actor)
  then
    raise exception 'Reusable checklist unavailable';
  end if;

  select count(*) into total_items from public.list_items
    where list_id=p_template_id and removed_at is null;
  if total_items>150 then
    raise exception 'Template exceeds 150 active items';
  end if;

  if p_local_day is null or
     p_local_day < (now() at time zone 'UTC')::date-1 or
     p_local_day > (now() at time zone 'UTC')::date+1 then
    raise exception 'Use your current local date';
  end if;
  local_date:=to_char(p_local_day,'YYYY-MM-DD');
  insert into public.lists
    (space_id,created_by,title,kind,visibility,is_template,source_template_id)
  values
    (source_list.space_id,actor,
      left(source_list.title,105)||' · '||local_date,
      'checklist',source_list.visibility,false,p_template_id)
  returning id into new_list;

  insert into public.list_items
    (list_id,created_by,label,quantity,unit,note,checked)
  select new_list,actor,li.label,li.quantity,li.unit,li.note,false
  from public.list_items li
  where li.list_id=p_template_id and li.removed_at is null
  order by li.created_at,li.id;

  return new_list;
end;
$function$
;
revoke all on function public.create_checklist_from_template(uuid,date)
 from public,anon,authenticated;
grant execute on function public.create_checklist_from_template(uuid,date)
 to authenticated;
