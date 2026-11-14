-- R25 rollback-only regression: new PostgREST JSON JWT claim format.
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
do $test$
declare denied boolean:=false;
begin
 begin
  perform public.claim_push_outbox(1);
 exception when others then denied:=true;
 end;
 if not denied then
  raise exception 'Authenticated app role could claim server push queue';
 end if;
end $test$;
reset role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
-- Only report the count, never tokens or device IDs.
select count(*) as service_claim_supported from public.claim_push_outbox(1);
select 'PASS: client denied, service JWT supported' result;
rollback;
