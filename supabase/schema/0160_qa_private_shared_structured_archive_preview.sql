-- QA-only structured archive PREVIEW: account-scoped, no media bytes,
-- NO destructive or restore permission, and no claim of nested completeness.
-- Preview is deliberately separate from verified archive packages.
create or replace function private.my_structured_archive_preview(p_kind text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  me uuid:=auth.uid();
  sid uuid;
  tab text;
  rows jsonb:='[]'::jsonb;
  part jsonb;
  n bigint;
  total bigint:=0;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if p_kind not in ('private','shared') or p_kind is null then
    raise exception 'Archive kind must be private or shared';
  end if;
  if (select count(*) from public.space_members where user_id=me)<>1 then
    raise exception 'Archive preview requires a single current space';
  end if;
  select sm.space_id into sid from public.space_members sm where sm.user_id=me;
  if p_kind='private' then
    select count(*) into total from public.personal_vault_records v
    where v.owner_id=me and v.source_space_id=sid and v.restorable
      and v.current_visibility='private';
    if total>2000 then raise exception 'Preview too large; batch export required'; end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'type',v.source_table,'original_id',v.source_id,
      'structured',private.qa_structured_value(v.snapshot))
      order by v.source_table,v.source_id),'[]'::jsonb)
      into rows
      from public.personal_vault_records v
      where v.owner_id=me and v.source_space_id=sid and v.restorable
        and v.current_visibility='private';
  else
    foreach tab in array array[
      'activities','daily_checkins','goals','items_to_sort','memories',
      'notes','occasion_plans','places','reminders','saved_contacts',
      'shared_trips','space_counters','space_events','tasks']
    loop
      -- Shared data may contain contributions from both current members.
      -- Reject inconsistent ownership rather than exporting it.
      execute format(
        'select count(*) from public.%I t
          where t.space_id=$1 and t.visibility=''shared''
          and not exists(select 1 from public.space_members sm
            where sm.space_id=$1 and sm.user_id=t.created_by)',tab)
        into n using sid;
      if n>0 then raise exception 'Shared content requires ownership repair'; end if;
      execute format(
        'select coalesce(jsonb_agg(jsonb_build_object(
           ''type'',%L,''original_id'',t.id,
           ''structured'',private.qa_structured_value(to_jsonb(t)))
           order by t.id),''[]''::jsonb)
         from public.%I t where t.space_id=$1 and t.visibility=''shared''',
        tab,tab)
        into part using sid;
      total:=total+jsonb_array_length(part);
      if total>2000 then raise exception 'Preview too large; batch export required'; end if;
      rows:=rows||part;
    end loop;
  end if;
  return jsonb_build_object(
    'version',1,'kind',p_kind,'source_space_id',sid,'recipient_id',me,
    'records',rows,'record_count',total,'media_included',false,
    'documents_included',false,'nested_dependents_complete',false,
    'is_verified_archive',false,'can_restore',false,
    'warning','This is a restricted structured root preview; related records and restoration require separate verified handling');
end $fn$;
revoke all on function private.my_structured_archive_preview(text) from public,anon;
grant execute on function private.my_structured_archive_preview(text) to authenticated;
create or replace function public.my_structured_archive_preview(p_kind text)
returns jsonb language sql security invoker set search_path=''
as $fn$ select private.my_structured_archive_preview(p_kind) $fn$;
revoke all on function public.my_structured_archive_preview(text) from public,anon;
grant execute on function public.my_structured_archive_preview(text) to authenticated;
