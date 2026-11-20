-- QA contract regression (read-only; transaction rolls back user context).
begin;
do $test$
declare eligible integer; linked integer; owner_row uuid; root record;
begin
 select count(*) into eligible from private.qa_archive_table_policy
 where relation_kind='root' and approved
 and disposition in ('private_shared','owner_private');
 if eligible<>22 then raise exception 'Eligible root inventory changed: %',eligible;end if;
 select count(*) into linked from auth.users u
 where u.deleted_at is null and not exists(
   select 1 from public.user_private_spaces ps where ps.owner_id=u.id);
 if linked<>0 then raise exception 'Authenticated account missing private scope';end if;
 if has_table_privilege('authenticated','public.user_private_spaces','INSERT') or
    has_table_privilege('authenticated','public.user_private_spaces','UPDATE') or
    has_table_privilege('authenticated','public.user_private_spaces','DELETE')
 then raise exception 'Users can tamper with private-space owners';end if;
 if has_function_privilege('anon','public.my_storage_scopes()','EXECUTE')
 then raise exception 'Anonymous can resolve private scopes';end if;
 for root in select source_table from private.qa_archive_table_policy
  where relation_kind='root' and approved
    and disposition in ('private_shared','owner_private')
 loop
  if not exists (select 1 from information_schema.columns c
     where c.table_schema='public' and c.table_name=root.source_table
       and c.column_name='private_space_id')
  then raise exception 'Missing new private-space slot for %',root.source_table;end if;
  if not exists(select 1 from pg_constraint c
    where c.conrelid=format('public.%I',root.source_table)::regclass
      and c.conname=root.source_table||'_exactly_one_space_scope')
  then raise exception 'Missing mutually exclusive scope constraint for %',root.source_table;end if;
 end loop;
end $test$;
select set_config('request.jwt.claim.sub',
 (select owner_id::text from public.user_private_spaces order by owner_id limit 1),true);
set local role authenticated;
do $owner$
declare n integer; owners integer; resolved jsonb;
begin
 select count(*),count(distinct owner_id) into n,owners
 from public.user_private_spaces;
 if n<>1 or owners<>1 then
    raise exception 'RLS leaked private scopes: % visible',n;
 end if;
 resolved:=public.my_storage_scopes();
 if resolved->>'private_space_id'<>auth.uid()::text or
    resolved->>'content_routing_enabled'<>'false'
 then raise exception 'Scope resolver did not fail closed for legacy content';end if;
end $owner$;
rollback;
