-- QA 0196 rollback: nested written content must not be silently
-- omitted from the encrypted archive manifest even if root snapshots exist.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid;
 task_a uuid; task_b uuid; item_a uuid; item_b uuid; check_a uuid;
 report_a jsonb; report_b jsonb; child_a jsonb; child_b jsonb;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
 on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members sm where sm.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'QA paired accounts fixture missing';end if;
 if has_function_privilege('anon','private.qa_private_archive_child_mirror_preflight()','execute')
 then raise exception 'Child coverage function grants anonymous access';end if;

 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,a,'QA private source task A','private') returning id into task_a;
 insert into public.task_checklist_items(task_id,created_by,title)
 values(task_a,a,'Preserve my written checklist item') returning id into item_a;
 insert into public.task_checklist_checks(item_id,cycle_date,user_id,completed)
 values(item_a,current_date,a,true) returning id into check_a;

 perform set_config('request.jwt.claim.sub',b::text,true);
 insert into public.tasks(space_id,created_by,title,visibility)
 values(sid,b,'QA private source task B','private') returning id into task_b;
 insert into public.task_checklist_items(task_id,created_by,title)
 values(task_b,b,'Partner B private item') returning id into item_b;

 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 report_a:=public.qa_private_archive_completeness_preflight();
 child_a:=report_a->'mirrored_children';
 if (child_a->>'mirrored_child_types_checked')::int<>9
    or (child_a->>'child_source_rows_checked')::int<>2
    or child_a->>'supported_child_mirrors_consistent'<>'true'
    or child_a->>'safe_to_archive'<>'false'
    or report_a->>'root_snapshot_mirror_consistent'<>'true'
 then raise exception 'Owner A valid nested snapshots incorrectly measured: %',child_a;end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 report_b:=public.qa_private_archive_completeness_preflight();
 child_b:=report_b->'mirrored_children';
 if (child_b->>'child_source_rows_checked')::int<>1
    or child_b->>'supported_child_mirrors_consistent'<>'true'
 then raise exception 'Owner B nested snapshots exposed A private rows';end if;

 perform set_config('role','postgres',true);
 update public.personal_vault_dependents set snapshot='{}'::jsonb
 where owner_id=a and source_table='task_checklist_checks' and source_id=check_a;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 child_a:=public.qa_private_archive_completeness_preflight()->'mirrored_children';
 if (child_a->>'stale_child_vault_snapshots')::int<>1
   or child_a->>'supported_child_mirrors_consistent'<>'false'
 then raise exception 'Corrupt private checklist check not detected';end if;

 perform set_config('role','postgres',true);
 update public.personal_vault_dependents v
 set snapshot=private.qa_structured_value(to_jsonb(c))
 from public.task_checklist_checks c
 where c.id=check_a and v.owner_id=a
   and v.source_table='task_checklist_checks' and v.source_id=check_a;
 delete from public.personal_vault_dependents
 where owner_id=a and source_table='task_checklist_items' and source_id=item_a;
 perform set_config('role','authenticated',true);
 child_a:=public.qa_private_archive_completeness_preflight()->'mirrored_children';
 if (child_a->>'missing_child_vault_snapshots')::int<>1
   or child_a->>'supported_child_mirrors_consistent'<>'false'
 then raise exception 'Missing private checklist item not detected';end if;

 -- Restore mirror only inside transaction and make root shared;
 -- a previously active child vault must not remain restorable.
 perform set_config('role','postgres',true);
 insert into public.personal_vault_dependents(
    owner_id,parent_table,parent_id,source_table,source_id,source_space_id,snapshot)
 select a,'tasks',task_a,'task_checklist_items',i.id,sid,
    private.qa_structured_value(to_jsonb(i))
 from public.task_checklist_items i where i.id=item_a;
 perform set_config('request.jwt.claim.sub',a::text,true);
 update public.tasks set visibility='shared' where id=task_a;
 update public.personal_vault_dependents
 set restorable=true where owner_id=a and source_table='task_checklist_items'
    and source_id=item_a;
 perform set_config('role','authenticated',true);
 child_a:=public.qa_private_archive_completeness_preflight()->'mirrored_children';
 if (child_a->>'orphan_child_vault_snapshots')::int<1
   or child_a->>'supported_child_mirrors_consistent'<>'false'
 then raise exception 'Former private child vault survived shared transition';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 child_b:=public.qa_private_archive_completeness_preflight()->'mirrored_children';
 if (child_b->>'supported_child_mirrors_consistent')<>'true'
 then raise exception 'Partner saw mismatched child vault from owner A';end if;
end $qa$;
rollback;
select 'PASS: 9 audited child families; private checklist complete, per-owner isolation, stale/missing/orphan detection, no archival readiness, rollback' result;
