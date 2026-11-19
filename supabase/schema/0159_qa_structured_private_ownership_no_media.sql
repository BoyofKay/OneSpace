-- OneSpace QA milestone: structured/private ownership snapshots WITHOUT uploaded media.
-- Forward-only, additive to the preexisting private Personal Vault.
-- This is not final separation: archive creation, private restoration and
-- actual membership transitions remain blocked pending end-to-end verification.

create or replace function private.qa_structured_value(p_value jsonb)
returns jsonb language plpgsql immutable set search_path='' as $fn$
declare
  typ text;
  item record;
  result jsonb;
  sanitized jsonb;
  k text;
begin
  if p_value is null then return 'null'::jsonb; end if;
  typ:=jsonb_typeof(p_value);
  if typ='object' then
    result:='{}'::jsonb;
    for item in select key,value from jsonb_each(p_value) loop
      k:=lower(item.key);
      -- Exclude file/media bodies, file pointers and embedded Quill media.
      -- Ordinary written content, including text of notes and links, remains.
      if k=any(array[
        'object_path','file_path','image_path','image_url','photo_path',
        'photo_url','thumbnail_path','thumbnail_url','voice_path','voice_url',
        'audio_path','audio_url','video_path','video_url','media_path',
        'media_url','attachment_path','attachment_url','document_path',
        'document_url','mime_type','byte_size','base64','data_uri',
        'binary','blob','photo','photos','image','images','audio',
        'voice','video','videos','media','attachment','attachments',
        'file','files','document','documents','thumbnail','thumbnails'
      ]) then
        continue;
      end if;
      sanitized:=private.qa_structured_value(item.value);
      if sanitized is not null then
        result:=result||jsonb_build_object(item.key,sanitized);
      end if;
    end loop;
    return result;
  elsif typ='array' then
    result:='[]'::jsonb;
    for item in select value from jsonb_array_elements(p_value) loop
      sanitized:=private.qa_structured_value(item.value);
      -- Keep the array shape stable; a removed binary element becomes null.
      result:=result||jsonb_build_array(coalesce(sanitized,'null'::jsonb));
    end loop;
    return result;
  elsif typ='string' then
    if p_value #>> '{}' ~* '^\s*(data:(image|audio|video|application/(pdf|octet-stream))|blob:|file:|content://)' then
      return 'null'::jsonb;
    end if;
    if p_value #>> '{}' ~* '/storage/v1/object/' then
      return 'null'::jsonb;
    end if;
    return p_value;
  end if;
  return p_value;
end $fn$;
revoke all on function private.qa_structured_value(jsonb) from public,anon,authenticated;

-- Invalidate former private owners when ownership or visibility changes.
-- Existing DELETE tombstones (qa_personal_vault_delete) remain installed.
create or replace function private.mirror_personal_vault_record()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
  if tg_table_schema<>'public' or tg_table_name not in
    ('activities','daily_checkins','goals','items_to_sort','memories',
     'notes','occasion_plans','places','reminders','saved_contacts',
     'shared_trips','space_counters','space_events','tasks') then
    raise exception 'Unexpected vault source';
  end if;
  if tg_op='UPDATE' and old.visibility='private'
    and (old.created_by is distinct from new.created_by
         or new.visibility is distinct from 'private') then
    update public.personal_vault_records
       set current_visibility=case when new.visibility='private'
                                  then 'ownership_changed' else new.visibility end,
           restorable=false,snapshot='{}'::jsonb,last_mirrored_at=now()
     where owner_id=old.created_by and source_table=tg_table_name and source_id=old.id;
  end if;
  if new.visibility<>'private' or new.created_by is null then return new; end if;
  if not exists(select 1 from public.space_members sm
    where sm.space_id=new.space_id and sm.user_id=new.created_by) then
    raise exception 'Private record owner must be a space member';
  end if;
  insert into public.personal_vault_records
    (owner_id,source_table,source_id,source_space_id,
     original_visibility,current_visibility,restorable,snapshot)
  values(new.created_by,tg_table_name,new.id,new.space_id,
         'private','private',true,private.qa_structured_value(to_jsonb(new)))
  on conflict(owner_id,source_table,source_id) do update set
    source_space_id=excluded.source_space_id,
    current_visibility='private',restorable=true,
    snapshot=excluded.snapshot,last_mirrored_at=now();
  return new;
end $fn$;
revoke all on function private.mirror_personal_vault_record() from public,anon,authenticated;

-- The existing dependent registry follows explicitly supported child tables.
-- Restore snapshots contain their structured fields, not their uploaded files.
create or replace function private.mirror_personal_vault_dependent()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare owner uuid; parent_type text; parent_uuid uuid;
begin
  if tg_table_name in ('occasion_budget_items','occasion_plan_steps','occasion_proposals') then
     owner:=new.created_by; parent_type:='occasion_plans'; parent_uuid:=new.plan_id;
  elsif tg_table_name='reminder_recipients' then
     owner:=new.recipient_id; parent_type:='reminders'; parent_uuid:=new.reminder_id;
  else
     raise exception 'Unrecognized private child table';
  end if;
  if owner is null then return new; end if;
  insert into public.personal_vault_dependents(
    owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
  select owner,parent_type,parent_uuid,tg_table_name,new.id,v.source_space_id,
         private.qa_structured_value(to_jsonb(new))
    from public.personal_vault_records v
   where v.owner_id=owner and v.source_table=parent_type
     and v.source_id=parent_uuid and v.restorable
  on conflict(owner_id,source_table,source_id) do update set
    snapshot=excluded.snapshot,source_space_id=excluded.source_space_id,
    restorable=true,last_mirrored_at=now();
  return new;
end $fn$;
revoke all on function private.mirror_personal_vault_dependent() from public,anon,authenticated;

create or replace function private.mirror_personal_days_off()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
 if new.user_id is null then return new; end if;
 insert into public.personal_vault_records(
   owner_id,source_table,source_id,source_space_id,
   original_visibility,current_visibility,restorable,snapshot)
 values(new.user_id,'personal_days_off',new.id,new.space_id,
   'private','private',true,private.qa_structured_value(to_jsonb(new)))
 on conflict(owner_id,source_table,source_id) do update set
   snapshot=excluded.snapshot,source_space_id=excluded.source_space_id,
   current_visibility='private',restorable=true,last_mirrored_at=now();
 return new;
end $fn$;
revoke all on function private.mirror_personal_days_off() from public,anon,authenticated;

-- Rewrite preexisting snapshots so their JSON payloads comply immediately.
-- QA currently has zero such rows; this protects future repeatable migrations.
update public.personal_vault_records v
  set snapshot=private.qa_structured_value(v.snapshot),last_mirrored_at=now()
  where v.snapshot is distinct from private.qa_structured_value(v.snapshot);
update public.personal_vault_dependents v
  set snapshot=private.qa_structured_value(v.snapshot),last_mirrored_at=now()
  where v.snapshot is distinct from private.qa_structured_value(v.snapshot);

-- Simple authenticated coverage summary. It exposes only this user's
-- private vault counts, never their partner's private records or raw JSON.
create or replace function private.my_structured_ownership_status()
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare me uuid:=auth.uid();
begin
  if me is null then raise exception 'Sign in required'; end if;
  return jsonb_build_object(
    'policy','structured_private_shared_no_media_v1',
    'media_included',false,
    'documents_included',false,
    'private_source_types', (select count(distinct source_table)
       from public.personal_vault_records
       where owner_id=me and restorable and current_visibility='private'),
    'protected_private_roots',(select count(*) from public.personal_vault_records
       where owner_id=me and restorable and current_visibility='private'),
    'protected_related_rows',(select count(*) from public.personal_vault_dependents d
       where d.owner_id=me and d.restorable and exists(
         select 1 from public.personal_vault_records v
         where v.owner_id=me and v.source_table=d.parent_table
           and v.source_id=d.parent_id and v.restorable)),
    'archive_ready',false,'restoration_ready',false,
    'reason','User-owned structured snapshots are protected; classification, complete export and tested restoration remain pending'
  );
end $fn$;
revoke all on function private.my_structured_ownership_status() from public,anon;
grant execute on function private.my_structured_ownership_status() to authenticated;

create or replace function public.my_structured_ownership_status()
returns jsonb language sql security invoker set search_path=''
as $fn$ select private.my_structured_ownership_status() $fn$;
revoke all on function public.my_structured_ownership_status() from public,anon;
grant execute on function public.my_structured_ownership_status() to authenticated;
