-- QA ONLY. Discover and count FK-linked dependent records that do not carry
-- space_id themselves. No content is returned or changed.
-- This is an inventory, NOT proof of private/shared export completeness.
create or replace function private.space_archive_dependency_inventory()
returns jsonb language plpgsql security definer set search_path to ''
as $func$
declare
  me uuid := auth.uid();
  sid uuid;
  route record;
  edge jsonb;
  pair jsonb;
  route_steps jsonb;
  idx int;
  depth_idx int;
  join_sql text;
  predicate text;
  root_alias text;
  cnt bigint;
  total_count bigint := 0;
  table_count int := 0;
  linked jsonb := '[]'::jsonb;
  ambiguity int;
begin
  if me is null then raise exception 'Sign in required'; end if;
  if (select count(*) from public.space_members where user_id=me)<>1 then
    return jsonb_build_object('has_space',false,'safe_to_export',false,
      'reason','Exactly one active space is required');
  end if;
  select sm.space_id into sid from public.space_members sm where sm.user_id=me;
  for route in
    with recursive roots as (
      select c.oid as table_oid,c.relname
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relkind in ('r','p')
        and c.relname <> 'space_members'
        and exists(select 1 from pg_catalog.pg_attribute a
          where a.attrelid=c.oid and a.attname='space_id' and a.attnum>0
            and not a.attisdropped)
    ), edges as (
      select co.conrelid child,co.confrelid parent,
        (select jsonb_agg(
          jsonb_build_object('child',ca.attname,'parent',pa.attname)
          order by k.ordinality)
         from unnest(co.conkey,co.confkey) with ordinality
            as k(child_attno,parent_attno,ordinality)
         join pg_catalog.pg_attribute ca on ca.attrelid=co.conrelid
            and ca.attnum=k.child_attno
         join pg_catalog.pg_attribute pa on pa.attrelid=co.confrelid
            and pa.attnum=k.parent_attno) pairs
      from pg_catalog.pg_constraint co
      join pg_catalog.pg_class cc on cc.oid=co.conrelid
      join pg_catalog.pg_class pc on pc.oid=co.confrelid
      join pg_catalog.pg_namespace cn on cn.oid=cc.relnamespace
      join pg_catalog.pg_namespace pn on pn.oid=pc.relnamespace
      where co.contype='f' and cn.nspname='public' and pn.nspname='public'
        and co.conrelid <> co.confrelid
    ), walk as (
      select r.table_oid current_oid, r.table_oid root_oid, 0 depth,
        array[r.table_oid] visited, '[]'::jsonb steps
      from roots r
      union all
      select e.child,w.root_oid,w.depth+1,w.visited||e.child,
        w.steps||jsonb_build_object(
          'child',c.relname,'parent',p.relname,'pairs',e.pairs)
      from walk w join edges e on e.parent=w.current_oid
      join pg_catalog.pg_class c on c.oid=e.child
      join pg_catalog.pg_class p on p.oid=e.parent
      where w.depth<5 and not e.child=any(w.visited)
    ), matches as (
      select w.*, c.relname child_name,r.relname root_name
      from walk w
      join pg_catalog.pg_class c on c.oid=w.current_oid
      join roots r on r.table_oid=w.root_oid
      where w.depth>0
        and not exists(select 1 from roots direct
          where direct.table_oid=w.current_oid)
    )
    select distinct on (child_name)
      child_name,root_name,steps,
      (select count(distinct m2.root_oid)
       from matches m2 where m2.current_oid=m.current_oid) as root_routes
    from matches m
    order by child_name,
      -- Never attribute an occasion budget item to its OPTIONAL source
      -- activity: plan_id is its actual owner, and is NOT NULL.
      case
        when child_name='occasion_budget_items'
          and steps->0->'pairs'->0->>'child'='plan_id' then 0
        when child_name='occasion_budget_log'
          and steps->0->'pairs'->0->>'child'='plan_id' then 0
        when child_name='occasion_proposal_items'
          and steps->0->>'child'='occasion_proposals' then 0
        when child_name='task_checklist_items'
          and steps->0->'pairs'->0->>'child'='task_id' then 0
        when child_name='task_checklist_checks'
          and steps->0->'pairs'->0->>'child'='task_id' then 0
        else 1
      end,depth,root_name
  loop
    route_steps:=route.steps;
    depth_idx:=0;
    idx:=jsonb_array_length(route_steps)-1;
    edge:=route_steps->idx;
    join_sql:=format('public.%I t0',edge->>'child');
    while idx>=0 loop
      edge:=route_steps->idx;
      depth_idx:=depth_idx+1;
      predicate:='';
      for pair in select value from jsonb_array_elements(edge->'pairs') loop
        if predicate<>'' then predicate:=predicate||' and '; end if;
        predicate:=predicate||format('t%s.%I=t%s.%I',
          depth_idx-1,pair->>'child',depth_idx,pair->>'parent');
      end loop;
      if predicate='' then raise exception 'Missing FK mapping for %',route.child_name; end if;
      join_sql:=join_sql||format(' join public.%I t%s on %s',
        edge->>'parent',depth_idx,predicate);
      idx:=idx-1;
    end loop;
    root_alias:=format('t%s',depth_idx);
    execute format('select count(*) from %s where %s.space_id=$1',
      join_sql,root_alias)
      into cnt using sid;
    total_count:=total_count+cnt;
    table_count:=table_count+1;
    linked:=linked||jsonb_build_object('table',route.child_name,
      'via_root',route.root_name,'records',cnt,
      'relationship_ambiguous',route.root_routes>1);
  end loop;

  select count(*) into ambiguity from jsonb_array_elements(linked) r
    where (r->>'relationship_ambiguous')::boolean;
  return jsonb_build_object('has_space',true,'safe_to_export',false,
    'dependent_tables_inspected',table_count,'linked_dependents',total_count,
    'multi_root_tables',ambiguity,'details',linked,
    'reason','Dependent record counts are an inventory only; classification, media-inclusive encrypted export and restoration require separate verification');
end $func$;
revoke all on function private.space_archive_dependency_inventory() from public,anon;
grant execute on function private.space_archive_dependency_inventory() to authenticated;

create or replace function public.space_archive_dependency_inventory()
returns jsonb language sql security invoker set search_path to ''
as $func$ select private.space_archive_dependency_inventory() $func$;
revoke all on function public.space_archive_dependency_inventory() from public,anon;
grant execute on function public.space_archive_dependency_inventory() to authenticated;
