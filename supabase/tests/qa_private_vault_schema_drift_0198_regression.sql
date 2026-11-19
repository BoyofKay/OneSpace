begin;
do $qa$
declare owner_id uuid; report jsonb; err text;
begin
 select m.user_id into owner_id from public.space_members m limit 1;
 if owner_id is null then raise exception 'QA paired user missing';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 report:=public.qa_private_vault_subset_fingerprint();
 if report->>'all_69_types_packaged'<>'false'
    or report->>'safe_to_archive'<>'false' then
   raise exception 'Partial hash mistakenly claims a ready archive';end if;
 perform set_config('role','postgres',true);
 create table public.qa_archive_new_relation_drift_0198(
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id),
 created_by uuid not null references auth.users(id),
 private_written_title text not null
 );
 alter table public.qa_archive_new_relation_drift_0198 enable row level security;
 perform set_config('role','authenticated',true);
 report:=public.qa_private_archive_completeness_preflight();
 if report->>'classification_complete'<>'false' then
   raise exception 'Unregistered table did not unset catalog classification';end if;
 begin
   perform public.qa_private_vault_subset_fingerprint();
   raise exception 'Unregistered table allowed a misleading vault fingerprint';
 exception when others then
   get stacked diagnostics err=message_text;
   if err<>'Archive table catalog drift blocks vault subset fingerprint'
   then raise exception 'Unexpected future schema safety failure %',err;end if;
 end;
end $qa$;
rollback;
select 'PASS: new unclassified private table prevents owner subset fingerprint despite old vault being complete; synthetic schema rolled back' result;
