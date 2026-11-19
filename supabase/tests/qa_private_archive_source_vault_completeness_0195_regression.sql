-- QA 0195 rollback-only: compare actual private root content to vault
-- snapshots, catch missing, corrupt and orphan mirrors; do not reveal partner.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid; aid uuid; bid uuid;
 report_a jsonb; report_b jsonb; msg text;
begin
 select s.id,s.created_by,sm.user_id into sid,a,b
 from public.spaces s join public.space_members sm
   on sm.space_id=s.id and sm.user_id<>s.created_by
 where (select count(*) from public.space_members c where c.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'Two-account QA fixture missing';end if;
 if has_function_privilege('anon',
     'public.qa_private_archive_completeness_preflight()','execute')
    or has_function_privilege('anon',
     'private.qa_private_archive_completeness_preflight()','execute')
 then raise exception 'Archive completeness preflight is anonymous-executable';end if;

 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA archive preflight note A','Private prose A','private')
 returning id into aid;
 perform set_config('request.jwt.claim.sub',b::text,true);
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,b,'QA archive preflight note B','Private prose B','private')
 returning id into bid;

 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 report_a:=public.qa_private_archive_completeness_preflight();
 if report_a->>'classification_complete'<>'true'
   or (report_a->>'classified_source_types')::int<>69
   or (report_a->>'mirrored_root_types_checked')::int<>14
   or jsonb_array_length(report_a->'private_shared_roots_not_in_current_mirror')<>4
   or jsonb_array_length(report_a->'private_shared_dependents_not_in_current_mirror')<>15
   or (report_a->>'private_source_rows_checked')::int<>1
   or report_a->>'root_snapshot_mirror_consistent'<>'true'
   or report_a->>'safe_to_archive'<>'false'
   or report_a->>'ready_to_restore'<>'false' then
   raise exception 'Owner A preflight did not detect correct verified baseline %',report_a;
 end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 report_b:=public.qa_private_archive_completeness_preflight();
 if (report_b->>'private_source_rows_checked')::int<>1
   or report_b->>'root_snapshot_mirror_consistent'<>'true'
 then raise exception 'Partner B private vault preflight failed';end if;

 perform set_config('role','postgres',true);
 update public.personal_vault_records
    set snapshot='{}'::jsonb
 where owner_id=a and source_table='notes' and source_id=aid;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 report_a:=public.qa_private_archive_completeness_preflight();
 if (report_a->>'stale_private_root_snapshots')::int<>1
   or report_a->>'root_snapshot_mirror_consistent'<>'false'
 then raise exception 'Stale mirror snapshot was not detected';end if;

 -- Reinstate the exact sanitized source snapshot before removing the vault.
 perform set_config('role','postgres',true);
 update public.personal_vault_records v
   set snapshot=private.qa_structured_value(to_jsonb(n))
 from public.notes n where n.id=aid and v.owner_id=a
    and v.source_table='notes' and v.source_id=aid;
 delete from public.personal_vault_records
 where owner_id=a and source_table='notes' and source_id=aid;
 perform set_config('role','authenticated',true);
 report_a:=public.qa_private_archive_completeness_preflight();
 if (report_a->>'missing_private_root_snapshots')::int<>1
   or report_a->>'root_snapshot_mirror_consistent'<>'false'
 then raise exception 'Missing private root mirror was not detected';end if;

 -- Reinsert only inside this rollback transaction, then transition note
 -- to shared, and simulate a stale ACTIVE vault record from the old scope.
 perform set_config('role','postgres',true);
 insert into public.personal_vault_records(owner_id,source_table,source_id,
   source_space_id,original_visibility,current_visibility,restorable,snapshot)
 select a,'notes',n.id,sid,'private','private',true,
   private.qa_structured_value(to_jsonb(n))
 from public.notes n where n.id=aid;
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.notes set visibility='shared' where id=aid;
 update public.personal_vault_records v
   set restorable=true,current_visibility='private',
       snapshot=private.qa_structured_value(to_jsonb(n))
 from public.notes n
 where n.id=aid and v.owner_id=a and v.source_table='notes'
       and v.source_id=aid;
 perform set_config('role','authenticated',true);
 report_a:=public.qa_private_archive_completeness_preflight();
 if (report_a->>'orphan_private_vault_snapshots')::int<>1
   or report_a->>'root_snapshot_mirror_consistent'<>'false'
 then raise exception 'Former private record kept in vault was not detected';end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 report_b:=public.qa_private_archive_completeness_preflight();
 if (report_b->>'private_source_rows_checked')::int<>1
   or report_b->>'root_snapshot_mirror_consistent'<>'true'
 then raise exception 'Partner preflight unexpectedly exposed A vault mismatch';end if;
end $qa$;
rollback;
select 'PASS: 69-policy catalog and exact 14-root, 4-root+15-child gaps; both partner scopes isolated, missing/stale/orphan mirror checks fail closed; fixtures rolled back' result;
