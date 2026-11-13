-- Deployed 20261113102913 onespace_r7_reusable_checklists_and_activity_countdowns
-- R7: reusable private/shared checklists + Activity countdown components.
alter table public.lists
  add column if not exists is_template boolean not null default false,
  add column if not exists source_template_id uuid references public.lists(id) on delete set null;

alter table public.lists
  add constraint lists_template_only_checklist
    check(not is_template or kind = 'checklist');

create index lists_templates_by_space
  on public.lists(space_id,created_at desc) where is_template;

grant update(is_template) on public.lists to authenticated;

-- Copying checklist runs under a single transaction. Both the original
-- template and its contents remain untouched; completion resets only on copy.
create or replace function public.create_checklist_from_template(p_template_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
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

  local_date:=to_char(now() at time zone 'UTC','YYYY-MM-DD');
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
$$;
revoke all on function public.create_checklist_from_template(uuid)
  from public,anon,authenticated;
grant execute on function public.create_checklist_from_template(uuid)
  to authenticated;

alter table public.activity_components
  drop constraint activity_components_kind_check;
alter table public.activity_components
  add constraint activity_components_kind_check
  check(kind in (
    'link','note','option','step','date','price','spec','reminder',
    'tag','mention','location','image','contact','voice','countdown'
  ));
