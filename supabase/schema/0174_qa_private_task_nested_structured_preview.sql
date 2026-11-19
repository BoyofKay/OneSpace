-- QA-only 0174: read-only, owner-authenticated structured checklist package.
-- NOT encrypted; NOT a downloadable archive; NOT an authorized restoration.
create or replace function private.qa_private_task_checklist_package(p_task_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  caller uuid:=auth.uid();
  root public.tasks%rowtype;
  invalid_count bigint;
  item_count bigint;
  check_count bigint;
  items jsonb;
  checks jsonb;
  payload jsonb;
begin
  if caller is null then raise exception 'Sign in required';end if;
  select t.* into root from public.tasks t
   join public.space_members sm on sm.space_id=t.space_id and sm.user_id=caller
   where t.id=p_task_id and t.visibility='private' and t.created_by=caller;
  if not found then raise exception 'Private task not found';end if;
  if (select count(*) from public.space_members sm where sm.user_id=caller)<>1 then
    raise exception 'Private task not found';
  end if;
  if (select count(*) from private.qa_archive_table_policy p
    where p.approved and p.disposition='private_shared'
      and p.source_table in ('tasks','task_checklist_items','task_checklist_checks'))<>3
  then raise exception 'Checklist archive scope not approved'; end if;
  if not exists(select 1 from public.personal_vault_records v
    where v.owner_id=caller and v.source_table='tasks' and v.source_id=root.id
      and v.source_space_id=root.space_id and v.current_visibility='private'
      and v.restorable and v.snapshot=private.qa_structured_value(to_jsonb(root)))
  then raise exception 'Private task root vault is not synchronized'; end if;

  select count(*),count(*) filter(
    where i.created_by is distinct from caller or v.source_id is null)
  into item_count,invalid_count
  from public.task_checklist_items i
  left join public.personal_vault_dependents v
    on v.owner_id=caller and v.parent_table='tasks' and v.parent_id=root.id
      and v.source_table='task_checklist_items' and v.source_id=i.id
      and v.source_space_id=root.space_id and v.restorable
      and v.snapshot=private.qa_structured_value(to_jsonb(i))
  where i.task_id=root.id;
  if invalid_count>0 then
    raise exception 'Private checklist item ownership or snapshot mismatch';end if;

  select count(*),count(*) filter(
    where c.task_id is distinct from root.id
      or c.user_id is distinct from caller or v.source_id is null)
  into check_count,invalid_count
  from public.task_checklist_checks c
  join public.task_checklist_items i on i.id=c.item_id
  left join public.personal_vault_dependents v
    on v.owner_id=caller and v.parent_table='tasks' and v.parent_id=root.id
      and v.source_table='task_checklist_checks' and v.source_id=c.id
      and v.source_space_id=root.space_id and v.restorable
      and v.snapshot=private.qa_structured_value(to_jsonb(c))
  where i.task_id=root.id;
  if invalid_count>0 then
    raise exception 'Private checklist check ownership or snapshot mismatch';end if;
  if item_count+check_count>500 then
    raise exception 'Private checklist package exceeds 500 records';end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'source_id',i.id,'structured',private.qa_structured_value(to_jsonb(i)))
    order by i.id::text),'[]'::jsonb)
  into items from public.task_checklist_items i where i.task_id=root.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_id',c.id,'structured',private.qa_structured_value(to_jsonb(c)))
    order by c.id::text),'[]'::jsonb)
  into checks
  from public.task_checklist_checks c
  join public.task_checklist_items i on i.id=c.item_id
  where i.task_id=root.id and c.task_id=root.id;
  payload:=jsonb_build_object(
    'schema','onespace.private-task-checklist-preview.v1',
    'owner_id',caller,'source_space_id',root.space_id,
    'root',jsonb_build_object('table','tasks','source_id',root.id,
          'structured',private.qa_structured_value(to_jsonb(root))),
    'children',jsonb_build_object('task_checklist_items',items,
                                   'task_checklist_checks',checks),
    'child_record_count',item_count+check_count);
  if octet_length(convert_to(payload::text,'UTF8'))>2097152 then
    raise exception 'Private checklist package exceeds 2 MiB'; end if;
  return jsonb_build_object(
    'payload',payload,
    'payload_sha256',encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex'),
    'media_included',false,'documents_included',false,
    'encrypted',false,'is_verified_archive',false,'can_restore',false,
    'safe_to_separate',false,
    'warning','Private checklist structured preview only, not an encrypted/downloadable archive or restorable copy');
end $fn$;
revoke all on function private.qa_private_task_checklist_package(uuid)
from public,anon,authenticated;
grant execute on function private.qa_private_task_checklist_package(uuid) to authenticated;
