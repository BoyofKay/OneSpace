begin;
do $qa$
declare me uuid; report jsonb; err text;
begin
 select user_id into me from public.space_members limit 1;
 if me is null then raise exception 'QA signed-in account fixture missing';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',me::text,true);
 report:=public.qa_private_vault_subset_manifest();
 if report->>'can_restore'<>'false'
 or report->>'all_69_types_packaged'<>'false'
 or report->>'archive_issued'<>'false'
 or report->>'is_verified_archive'<>'false'
 then raise exception 'Partial manifest has accidentally been promoted to real archive';end if;
 perform set_config('role','postgres',true);
 create table public.qa_new_private_archive_source_0209(
   id uuid primary key default gen_random_uuid(),
   space_id uuid not null references public.spaces(id),
   created_by uuid not null references auth.users(id),
   private_written_text text
 );
 alter table public.qa_new_private_archive_source_0209 enable row level security;
 perform set_config('role','authenticated',true);
 begin
   perform public.qa_private_vault_subset_manifest();
   raise exception 'New unreviewed private table permitted subset snapshot manifest';
 exception when others then
   get stacked diagnostics err=message_text;
   if err<>'Archive table catalog drift blocks vault subset fingerprint' then
     raise exception 'Unexpected future-table denial: %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: QA 0209 per-record manifest rejects future table drift and never declares a complete/restorable archive; schema fixture rolled back' result;
