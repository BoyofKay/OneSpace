begin;
do $qa$
declare
 sid uuid;a uuid;b uuid; outsider uuid; future_id uuid; today_id uuid;
 n int; val record;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
 on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2 limit 1;
 if sid is null then raise exception 'QA two-member fixture missing';end if;
 if (select p.prosecdef from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='sealed_letters') then
  raise exception 'Legacy letter RPC still bypasses RLS';
 end if;
 if has_function_privilege('anon','public.sealed_letters()','execute')
 then raise exception 'Anonymous can call sealed letter metadata RPC';end if;
 select id into outsider from auth.users where id not in
 (select user_id from public.space_members where space_id=sid) limit 1;
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into public.couple_letters(
 space_id,author_id,title,body,status,open_on)
 values(sid,a,'QA SEALED SECRET','SHOULD_NOT_REVEAL_BEFORE_OPEN','sent',current_date+7)
 returning id into future_id;
 insert into public.couple_letters(
 space_id,author_id,title,body,status,open_on)
 values(sid,a,'QA OPENED LETTER','VISIBLE_AFTER_OPEN','sent',current_date)
 returning id into today_id;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',b::text,true);
 select count(*) into n from public.sealed_letters();
 if n<>0 then raise exception 'Partner learned future letter metadata';end if;
 select count(*) into n from public.couple_letters where id=future_id;
 if n<>0 then raise exception 'Partner RLS exposed future letter';end if;
 select count(*) into n from public.couple_letters where id=today_id;
 if n<>1 then raise exception 'Partner cannot read opened letter';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 select count(*) into n from public.couple_letters where id=future_id;
 if n<>1 then raise exception 'Author lost author-private letter';end if;
 select count(*) into n from public.sealed_letters();
 if n<>0 then raise exception 'Legacy placeholder RPC unexpectedly returns scheduled letters';end if;
 if outsider is not null then
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  select count(*) into n from public.sealed_letters();
  if n<>0 then raise exception 'Outsider received sealed letter metadata';end if;
  select count(*) into n from public.couple_letters where id=today_id;
  if n<>0 then raise exception 'Outsider saw opened couple letter';end if;
 end if;
end $qa$;
rollback;
select 'PASS: legacy sealed letter metadata now returns no rows for owner, partner or outsider; future letters remain author-private, eligible opened letters visible, security INVOKER and no anonymous EXECUTE; rollback' result;