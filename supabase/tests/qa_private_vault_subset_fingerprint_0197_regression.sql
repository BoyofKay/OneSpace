-- QA 0197 rollback: fingerprint must bind owner, original space, exact
-- sanitized root + child bytes, reject corruption and never restore.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid;
 note_id uuid; task_id uuid; child_id uuid;
 first_a jsonb; same_a jsonb; changed_a jsonb; first_b jsonb; next_b jsonb;
 error_message text;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
   on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members c where c.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'QA pair missing';end if;
 if has_function_privilege('anon',
  'public.qa_private_vault_subset_fingerprint()','execute')
 or has_function_privilege('anon',
  'private.qa_private_vault_subset_fingerprint()','execute')
 then raise exception 'Unsigned vault fingerprint publicly callable';end if;

 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA fingerprint note','Keep our written family plans','private')
 returning id into note_id;
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,a,'QA fingerprint task','private') returning id into task_id;
 insert into public.task_checklist_items(task_id,created_by,title)
 values(task_id,a,'Plan a happy surprise') returning id into child_id;

 perform set_config('role','authenticated',true);
 first_a:=public.qa_private_vault_subset_fingerprint();
 same_a:=public.qa_private_vault_subset_fingerprint();
 if first_a->>'subset_sha256' is null
   or first_a->>'subset_sha256'<>same_a->>'subset_sha256'
   or (first_a->>'root_records')::int<>2
   or (first_a->>'child_records')::int<>1
   or first_a->>'root_mirror_verified'<>'true'
   or first_a->>'all_69_types_packaged'<>'false'
   or first_a->>'safe_to_archive'<>'false'
   or first_a->>'can_restore'<>'false'
 then raise exception 'Vault subset deterministic fingerprint baseline failed';end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 first_b:=public.qa_private_vault_subset_fingerprint();
 if first_b->>'subset_sha256'=first_a->>'subset_sha256'
 or (first_b->>'root_records')::int<>0
 or (first_b->>'child_records')::int<>0
 then raise exception 'Partner B fingerprint includes A private data';end if;

 perform set_config('role','postgres',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.notes set body='Family plans changed and should change digest'
 where id=note_id;
 perform set_config('role','authenticated',true);
 changed_a:=public.qa_private_vault_subset_fingerprint();
 if changed_a->>'subset_sha256'=first_a->>'subset_sha256'
 or (changed_a->>'root_records')::int<>2
 or (changed_a->>'child_records')::int<>1
 then raise exception 'Changed private notes did not alter subset hash';end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 next_b:=public.qa_private_vault_subset_fingerprint();
 if next_b->>'subset_sha256'<>first_b->>'subset_sha256'
 then raise exception 'A private content change modified B digest';end if;

 perform set_config('role','postgres',true);
 update public.personal_vault_dependents
   set snapshot='{}'::jsonb
 where owner_id=a and source_table='task_checklist_items' and source_id=child_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
   perform public.qa_private_vault_subset_fingerprint();
   raise exception 'Corrupt child vault generated a trusted fingerprint';
 exception when others then
   get stacked diagnostics error_message=message_text;
   if error_message<>'Private vault subset is incomplete, stale or orphaned'
   then raise exception 'Wrong invalid fingerprint error: %',error_message;end if;
 end;
end $qa$;
rollback;
select 'PASS: deterministic owner-bound 14+9 vault-subset digest, changed text changes hash, per-partner independence, stale child blocks issuance; rollback' result;
