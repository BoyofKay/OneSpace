-- QA rollback-only checks for 0315. Each scenario runs in its own
-- sub-transaction and is undone at its end.
do $t$
declare
  a uuid:='db1ac811-6fb0-4f31-8e6c-4e37b5d3a70d';   -- owner of couple
  b uuid:='77b679f8-1a70-4347-a95e-9a39d3ea6977';   -- invited partner
  couple uuid:='db24ba25-8f22-4565-85df-b1e9edab8e00';
  n int; act text; who uuid;
begin
  if (select created_by from public.spaces where id=couple) is distinct from a
     or (select count(*) from public.space_members where space_id=couple)<>2 then
    raise exception 'SETUP: test couple is not A(owner)+B';
  end if;
  delete from public.account_notices where user_id in (a,b);

  foreach act in array array['leave_space','remove_partner','delete_space'] loop
   begin
    who:=case when act='leave_space' then b else a end;
    perform set_config('request.jwt.claims',json_build_object('sub',who,'role','authenticated')::text,true);
    perform set_config('request.jwt.claim.sub',who::text,true);
    set local role authenticated;
    perform public.qa_end_current_relationship(couple,act,'DELETE SHARED CONTENT');
    -- Each person sees only their own notice.
    select count(*) into n from public.account_notices;
    if n<>1 then raise exception 'FAIL %: actor sees % notices (want 1)',act,n; end if;
    reset role;

    if exists(select 1 from public.spaces where id=couple) then
      raise exception 'FAIL %: old shared space still exists',act; end if;
    if exists(select 1 from public.space_members m join public.spaces s on s.id=m.space_id
              where m.user_id=b and s.personal_owner is null) then
      raise exception 'FAIL %: partner B still has a shared space',act; end if;
    select count(*) into n from public.space_members m join public.spaces s on s.id=m.space_id
      where m.user_id=a and s.personal_owner is null and s.created_by=a;
    if act in ('leave_space','remove_partner') and n<>1 then
      raise exception 'FAIL %: owner A did not keep a space',act; end if;
    if act='delete_space' and n<>0 then
      raise exception 'FAIL %: owner A kept a space after deleting it',act; end if;
    if (select count(*) from public.account_notices where user_id=a and dismissed_at is null)<>1
       or (select count(*) from public.account_notices where user_id=b and dismissed_at is null)<>1 then
      raise exception 'FAIL %: both partners need exactly one notice',act; end if;
    if exists(select 1 from public.space_notifications x join public.spaces s on s.id=x.space_id
              where x.recipient_id=a and x.kind='joined' and s.created_by=a) then
      raise exception 'FAIL %: owner got a false "partner joined"',act; end if;

    -- B dismisses their notice; B cannot touch A's.
    perform set_config('request.jwt.claims',json_build_object('sub',b,'role','authenticated')::text,true);
    perform set_config('request.jwt.claim.sub',b::text,true);
    set local role authenticated;
    update public.account_notices set dismissed_at=now() where user_id=b;
    get diagnostics n=row_count;
    if n<>1 then raise exception 'FAIL %: B cannot dismiss own notice',act; end if;
    update public.account_notices set dismissed_at=now() where user_id=a;
    get diagnostics n=row_count;
    if n<>0 then raise exception 'FAIL %: B dismissed A''s notice',act; end if;
    reset role;
    raise notice '% OK', act;
    raise exception 'qa_undo';
   exception when others then
    if sqlerrm<>'qa_undo' then raise; end if;
   end;
  end loop;
  raise notice 'ALL 0315 CHECKS PASSED';
end $t$;
