-- QA 0209: actual per-record PostgreSQL JSON bytes, integrity and owner-private
-- scope. Synthetic private notes, tasks and checklist children always rollback.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid; note_id uuid; task_id uuid; item_id uuid; check_id uuid;
 p jsonb; q jsonb; bad int; n int; err text; digest_before text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b from public.spaces s
 join public.space_members m on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members sm where sm.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA paired fixture missing';end if;
 if has_function_privilege('anon','public.qa_private_vault_subset_manifest()','execute')
 or has_function_privilege('anon','private.qa_private_vault_subset_manifest()','execute') then
   raise exception 'Anonymous manifest export allowed';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA real subset manifest note',
 'Remember the plan /storage/v1/object/private/secret.png and the written ending',
 'private') returning id into note_id;
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,a,'QA real subset checklist','private') returning id into task_id;
 insert into public.task_checklist_items(task_id,created_by,title)
 values(task_id,a,'Important birthday') returning id into item_id;
 insert into public.task_checklist_checks(item_id,cycle_date,user_id,completed)
 values(item_id,current_date,a,true) returning id into check_id;
 perform set_config('request.jwt.claim.sub',b::text,true);
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,b,'QA B secret note','B private draft','private');
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 p:=public.qa_private_vault_subset_manifest();
 if p->>'owner_id'<>a::text
    or p->>'source_space_id'<>sid::text
    or (p->>'record_count')::int<>4
    or (p->>'root_record_count')::int<>2
    or (p->>'child_record_count')::int<>2
    or (p->>'root_types_in_scope')::int<>14
    or (p->>'dependent_types_in_scope')::int<>9
    or p->>'all_69_types_packaged'<>'false'
    or p->>'can_restore'<>'false'
    or p->>'safe_to_separate'<>'false'
    or p::text not like '%written ending%'
    or p::text like '%secret.png%'
    or p::text like '%B private draft%'
 then raise exception 'Bounded original private snapshot manifest incomplete or media leaked: %',left(p::text,1500);end if;
 select count(*) into bad from jsonb_array_elements(p->'records') rec
 where rec->>'snapshot_sha256'<>encode(extensions.digest(
    convert_to(rec->>'snapshot_json','UTF8'),'sha256'),'hex')
  or (rec->>'snapshot_bytes')::int<>octet_length(
     convert_to(rec->>'snapshot_json','UTF8'))
  or (rec->>'source_table' not in
    ('notes','tasks','task_checklist_items','task_checklist_checks'));
 if bad<>0 then raise exception 'Per-record digest or byte length does not match actual plaintext';end if;
 select count(*) into n from jsonb_array_elements(p->'records') rec
 where (rec->>'kind'='child' and
   (rec->>'parent_table'<>'tasks' or (rec->>'parent_id')::uuid<>task_id))
 or (rec->>'kind'='root' and rec->>'parent_id' is not null);
 if n<>0 then raise exception 'Manifest has invalid parent mapping';end if;
 digest_before:=p->>'subset_sha256';
 if digest_before<>(private.qa_private_vault_subset_fingerprint()->>'subset_sha256') then
   raise exception 'Per-row manifest digest differs from previously audited subset';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 q:=public.qa_private_vault_subset_manifest();
 if (q->>'root_record_count')::int<>1
   or (q->>'child_record_count')::int<>0
   or q::text like '%written ending%' then
     raise exception 'Partner can see owner private manifest';end if;
 perform set_config('role','postgres',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.notes set body='Edited private written content' where id=note_id;
 perform set_config('role','authenticated',true);
 p:=public.qa_private_vault_subset_manifest();
 if p->>'subset_sha256'=digest_before then
   raise exception 'Private note edit did not update verifiable snapshot manifest';end if;

 perform set_config('role','postgres',true);
 update public.personal_vault_dependents set snapshot='{}'::jsonb
 where owner_id=a and source_table='task_checklist_checks' and source_id=check_id;
 perform set_config('role','authenticated',true);
 begin
   perform public.qa_private_vault_subset_manifest();
   raise exception 'A tampered vault dependent was returned in trusted manifest';
 exception when others then
   get stacked diagnostics err=message_text;
   if err<>'Private vault subset is incomplete, stale or orphaned'
   then raise exception 'Wrong tamper denial: %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: real owner-private 23-family snapshot_json manifest, per-record SHA/bytes, roots/children lineage, no media, partner isolation, edit changes digest and corrupted vault denied; rollback' result;
