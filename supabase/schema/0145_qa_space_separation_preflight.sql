-- QA-only read-only inventory. No space, membership, media or user data
-- is modified. Summary is scoped to the signed-in member's current space.
create or replace function private.space_separation_preflight()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 me uuid := auth.uid();
 sid uuid;
 table_row record;
 current_count bigint;
 own_private_count bigint;
 shared_count bigint;
 classified_total bigint;
 total_rows bigint := 0;
 my_private_rows bigint := 0;
 shared_rows bigint := 0;
 unclassified_rows bigint := 0;
 inspected_tables integer := 0;
 has_vis boolean;
 has_creator boolean;
begin
 if me is null then raise exception 'Sign in required'; end if;
 select space_id into sid from public.space_members where user_id=me;
 if sid is null then return jsonb_build_object('has_space',false,
    'safe_to_separate',false); end if;
 for table_row in
  select c.table_name
  from information_schema.columns c
  where c.table_schema='public' and c.column_name='space_id'
  order by c.table_name
 loop
  select exists(select 1 from information_schema.columns
    where table_schema='public' and table_name=table_row.table_name
      and column_name='visibility') into has_vis;
  select exists(select 1 from information_schema.columns
    where table_schema='public' and table_name=table_row.table_name
      and column_name='created_by') into has_creator;
  execute format('select count(*) from public.%I where space_id=$1',
    table_row.table_name) into current_count using sid;
  current_count := coalesce(current_count,0);
  total_rows:=total_rows+current_count;
  inspected_tables:=inspected_tables+1;
  classified_total:=0;
  if has_vis and has_creator then
   execute format(
     'select count(*) from public.%I where space_id=$1 and visibility=''private'' and created_by=$2',
      table_row.table_name) into own_private_count using sid,me;
   execute format(
     'select count(*) from public.%I where space_id=$1 and visibility<>''private''',
      table_row.table_name) into shared_count using sid;
   my_private_rows:=my_private_rows+coalesce(own_private_count,0);
   shared_rows:=shared_rows+coalesce(shared_count,0);
   classified_total:=coalesce(own_private_count,0)+coalesce(shared_count,0);
  end if;
  unclassified_rows:=unclassified_rows+greatest(0,current_count-classified_total);
 end loop;
 return jsonb_build_object(
  'has_space',true,'safe_to_separate',false,
  'space_tables_inspected',inspected_tables,
  'space_linked_records',total_rows,
  'private_records_owned_by_me',my_private_rows,
  'nonprivate_records',shared_rows,
  'unclassified_or_other_private_records',unclassified_rows,
  'media_integrity_verified',false,
  'encrypted_exports_verified',false,
  'reason','Separate private records and validate encrypted media-inclusive archives before enabling destructive actions'
 );
end $$;
create or replace function public.space_separation_preflight()
returns jsonb language sql security invoker set search_path=''
as $$select private.space_separation_preflight()$$;
revoke all on function private.space_separation_preflight(),
 public.space_separation_preflight() from public,anon;
grant execute on function private.space_separation_preflight(),
 public.space_separation_preflight() to authenticated;
