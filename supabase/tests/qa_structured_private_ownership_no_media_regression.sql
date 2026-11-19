-- QA milestone regression: all synthetic content is rolled back.
begin;
do $t$
declare
  sid uuid;
  owner_id uuid;
  partner_id uuid;
  note_id uuid;
  contact_id uuid;
  shared_id uuid;
  snap jsonb;
  status jsonb;
  err text;
  before_members int;
begin
  select s.id,s.created_by,sm.user_id into sid,owner_id,partner_id
  from public.spaces s join public.space_members sm
    on sm.space_id=s.id and sm.user_id<>s.created_by
  where (select count(*) from public.space_members k where k.space_id=s.id)=2
  limit 1;
  if sid is null then raise exception 'No two-member QA test space'; end if;
  select count(*) into before_members from public.space_members;
  if has_function_privilege('anon','public.my_structured_ownership_status()','execute') then
    raise exception 'Anonymous caller can read user-private ownership status';
  end if;

  insert into public.notes(space_id,created_by,title,body,visibility,rich_delta)
    values(sid,owner_id,'Synthetic QA-only title','Structured note text','private',
      '[{"insert":"Hello"},{"insert":{"image":"data:image/png;base64,AABBCC"}},{"insert":{"attachment_url":"/storage/v1/object/private/pic"}},{"insert":" World"}]'::jsonb)
    returning id into note_id;
  select snapshot into snap from public.personal_vault_records
    where source_table='notes' and source_id=note_id and owner_id=owner_id;
  if snap is null or snap->>'body'<>'Structured note text'
    or snap::text like '%data:image%'
    or snap::text like '%attachment_url%'
    or snap::text like '%/storage/v1/object/%' then
    raise exception 'Private note structured snapshot leaked media: %',snap;
  end if;

  insert into public.saved_contacts(space_id,created_by,visibility,label,payload)
    values(sid,owner_id,'private','Synthetic contact',
     '{"name":"Private friend","phone":"+10000000000","photo_url":"/storage/v1/object/private/portrait","items":[{"file_path":"asset.pdf"},{"note":"Keep words"}]}'::jsonb)
    returning id into contact_id;
  select snapshot into snap from public.personal_vault_records
    where source_table='saved_contacts' and source_id=contact_id and owner_id=owner_id;
  if snap #>> '{payload,name}' <> 'Private friend'
      or snap::text like '%photo_url%'
      or snap::text like '%file_path%' then
    raise exception 'Contact snapshot did not separate structured content from media';
  end if;

  insert into public.notes(space_id,created_by,title,body,visibility)
    values(sid,owner_id,'Synthetic shared note','Visible to both','shared')
    returning id into shared_id;
  if exists(select 1 from public.personal_vault_records
       where source_table='notes' and source_id=shared_id) then
    raise exception 'Shared note was wrongly mirrored into a private vault';
  end if;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  status:=public.my_structured_ownership_status();
  if (status->>'protected_private_roots')::int<2
     or status->>'media_included'<>'false'
     or status->>'archive_ready'<>'false'
     or status ? 'snapshot' then
    raise exception 'Invalid signed-in owner coverage: %',status;
  end if;
  perform set_config('request.jwt.claim.sub',partner_id::text,true);
  status:=public.my_structured_ownership_status();
  if (status->>'protected_private_roots')::int<>0 then
    raise exception 'Partner can infer other private root count in their report: %',status;
  end if;

  perform set_config('role','postgres',true);
  update public.notes set visibility='shared' where id=note_id;
  select snapshot into snap from public.personal_vault_records
    where source_table='notes' and source_id=note_id and owner_id=owner_id;
  if snap <> '{}'::jsonb or exists(select 1 from public.personal_vault_records
     where source_table='notes' and source_id=note_id and restorable) then
    raise exception 'Private->shared transition left restorable private copy';
  end if;
  update public.notes set visibility='private' where id=note_id;
  if not exists(select 1 from public.personal_vault_records
     where source_table='notes' and source_id=note_id and restorable) then
    raise exception 'Shared->private transition did not mirror structured content';
  end if;
  delete from public.notes where id=note_id;
  if exists(select 1 from public.personal_vault_records
    where source_table='notes' and source_id=note_id
      and (restorable or snapshot<>'{}'::jsonb)) then
    raise exception 'Explicit note delete left restorable private data';
  end if;
  if (select count(*) from public.space_members)<>before_members then
    raise exception 'Synthetic test changed membership';
  end if;
end $t$;
rollback;
select 'PASS: structured data retained, nested media stripped, private isolation, ownership transitions and user deletion tombstones; all rows rolled back' as result;
