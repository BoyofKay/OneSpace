-- QA-only rollback simulation: a private user-owned snapshot survives the
-- old shared-space cascade during an explicitly marked retirement transaction.
-- Does NOT authorize any actual space deletion or completed restoration.
begin;
do $test$
declare
  v_space uuid;
  v_owner uuid;
  v_note uuid;
  v_orig_spaces bigint;
  v_orig_members bigint;
  v_snapshot jsonb;
begin
  select s.id,s.created_by into v_space,v_owner
  from public.spaces s
  where (select count(*) from public.space_members sm where sm.space_id=s.id)=1
    and exists(select 1 from public.space_members sm where sm.space_id=s.id
      and sm.user_id=s.created_by)
  limit 1;
  if v_space is null then raise exception 'No sole-owner QA space for simulation'; end if;
  select count(*) into v_orig_spaces from public.spaces;
  select count(*) into v_orig_members from public.space_members;

  insert into public.notes(space_id,created_by,title,body,visibility)
  values(v_space,v_owner,'Rollback-only owner note',
    'This structured personal note must outlive old-space retirement','private')
  returning id into v_note;
  if not exists(select 1 from public.personal_vault_records v
    where v.owner_id=v_owner and v.source_table='notes' and v.source_id=v_note
      and v.restorable) then
    raise exception 'Pre-retirement private snapshot missing';
  end if;
  perform set_config('onespace.retiring_space','on',true);
  delete from public.spaces where id=v_space;
  if exists(select 1 from public.notes where id=v_note) then
    raise exception 'Old source note unexpectedly survived space deletion';
  end if;
  select snapshot into v_snapshot from public.personal_vault_records v
   where v.owner_id=v_owner and v.source_table='notes'
     and v.source_id=v_note and v.restorable;
  if v_snapshot is null or
     v_snapshot->>'body'<>'This structured personal note must outlive old-space retirement' then
    raise exception 'Private data did not survive marked retirement cascade';
  end if;
  if (select count(*) from public.spaces)<>v_orig_spaces-1 or
     (select count(*) from public.space_members)<>v_orig_members-1 then
    raise exception 'Unexpected side effects from simulated old-space retirement';
  end if;
end $test$;
rollback;
select 'PASS: private structured vault survives marked old-space cascade; entire retirement and synthetic records rolled back' result;
