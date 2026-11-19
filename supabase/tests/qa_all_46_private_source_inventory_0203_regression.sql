begin;
do $qa$
declare
 sid uuid; a uuid; b uuid;
 note_id uuid; task_id uuid;
 before_a jsonb; after_a jsonb; first_b jsonb; second_b jsonb;
 earlier_hash text; err text;
begin
 select s.id,s.created_by,sm.user_id into sid,a,b
 from public.spaces s join public.space_members sm on sm.space_id=s.id and sm.user_id<>s.created_by
 where (select count(*) from public.space_members m where m.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA pair fixture unavailable';end if;
 if has_function_privilege('anon','public.qa_private_source_inventory()','execute')
 or has_function_privilege('anon','private.qa_private_source_inventory()','execute') then
  raise exception 'Owner private inventory callable by anon';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA complete census note','Remember this handwritten note','private')
 returning id into note_id;
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,a,'QA complete census task','private') returning id into task_id;
 insert into public.note_references(note_id,target_kind,target_id,created_by)
 values(note_id,'task',task_id,a);
 insert into public.gesture_templates(space_id,creator_id,recipient_id,kind,title,message)
 values(sid,a,b,'thinking','QA complete census gesture','Keep this private');
 perform set_config('role','authenticated',true);
 before_a:=public.qa_private_source_inventory();
 if before_a->>'all_private_eligible_types_censused'<>'true'
 or (before_a->>'private_eligible_table_types')::int<>46
 or (before_a->>'private_source_rows_counted')::int<>4
 or (before_a->>'mirrored_root_types_verified')::int<>14
 or (before_a->>'mirrored_child_types_verified')::int<>9
 or (before_a->>'unmirrored_private_shared_types_counted')::int<>19
 or (before_a->>'owner_private_types_counted')::int<>4
 or before_a->>'all_private_content_persistently_snapshotted'<>'false'
 or before_a->>'complete_archive_manifest_created'<>'false'
 or before_a->>'safe_to_separate'<>'false'
 then raise exception 'Owner private source inventory incorrectly claimed completeness: %',left(before_a::text,900);end if;
 if before_a::text like '%Keep this private%'
    or before_a::text like '%Remember this handwritten note%'
 then raise exception 'Private source plaintext leaked from census';end if;
 earlier_hash:=before_a->>'source_inventory_sha256';
 if earlier_hash is null or length(earlier_hash)<>64
 then raise exception 'Owner inventory fingerprint missing';end if;
 after_a:=public.qa_private_source_inventory();
 if after_a->>'source_inventory_sha256'<>earlier_hash
 then raise exception 'Unchanged owner inventory digest not deterministic';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 first_b:=public.qa_private_source_inventory();
 if (first_b->>'private_source_rows_counted')::int<>0
 or first_b->>'owner_id'<>b::text then
 raise exception 'Partner inventory included first owner's private data';end if;
 perform set_config('role','postgres',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.notes set body='This written private note changed'
 where id=note_id;
 perform set_config('role','authenticated',true);
 after_a:=public.qa_private_source_inventory();
 if after_a->>'source_inventory_sha256'=earlier_hash
 then raise exception 'Live note changed but owner private digest stayed fixed';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 second_b:=public.qa_private_source_inventory();
 if second_b->>'source_inventory_sha256'<>first_b->>'source_inventory_sha256'
 then raise exception 'Owner A note edit changed partner B inventory fingerprint';end if;
 perform set_config('role','postgres',true);
 update public.personal_vault_records set snapshot='{}'::jsonb
 where owner_id=a and source_table='notes' and source_id=note_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
  perform public.qa_private_source_inventory();
  raise exception 'Corrupt mirror did not block private inventory';
 exception when others then
  get stacked diagnostics err=message_text;
  if err<>'Private vault subset is incomplete, stale or orphaned' then
    raise exception 'Wrong incomplete inventory denial: %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: all 46 private-eligible families counted, stable and changed hashes, owner isolation, no plaintext, no restore readiness and stale vault denial; rollback' result;
