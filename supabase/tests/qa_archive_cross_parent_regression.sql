-- QA-only crossed-parent archive isolation check. Synthetic rows ALWAYS rollback.
begin;
do $test$
declare
  target_plan uuid;
  other_activity uuid;
  conflict_allowed boolean := false;
  raw jsonb;
  public_report jsonb;
begin
  insert into public.occasion_plans(space_id,created_by,title,occasion_on,visibility)
  values('7f26214b-0716-4c4f-9130-83905f1492c1',
    'fe29186f-8eb7-4d76-9c40-2d113f921cd7',
    'Temporary boundary plan',current_date+30,'private')
  returning id into target_plan;
  insert into public.activities(space_id,created_by,title,visibility)
  values('b2519767-1a69-4f14-956a-a3af4de527d7',
    '937e362d-6457-4fe2-b8cd-abad7157a015',
    'Temporary other relationship activity','private')
  returning id into other_activity;
  begin
    insert into public.occasion_budget_items(plan_id,created_by,title,source_activity_id)
    values(target_plan,'fe29186f-8eb7-4d76-9c40-2d113f921cd7',
      'Temporary cross-space item',other_activity);
    conflict_allowed:=true;
  exception when others then
    -- Database integrity rejection is also a safe outcome.
    conflict_allowed:=false;
  end;
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claim.sub',
    'fe29186f-8eb7-4d76-9c40-2d113f921cd7',true);
  raw:=private.space_archive_dependency_inventory();
  public_report:=public.space_archive_dependency_inventory();
  if conflict_allowed and (raw->>'cross_parent_conflicts')::int < 1 then
    raise exception 'Cross-space foreign key was permitted and NOT detected';
  end if;
  if public_report ? 'cross_parent_conflicts' or
     public_report ? 'details' or
     public_report ? 'linked_dependents' then
    raise exception 'Internal relationship data disclosed by public inventory';
  end if;
  if raw->>'safe_to_export'<>'false' or
     public_report->>'safe_to_export'<>'false' then
    raise exception 'Unsafe archive export approved';
  end if;
end $test$;
rollback;
select 'PASS: crossed-parent reference rejected or flagged, public counts withheld, synthetic rows rolled back' as result;
