-- QA signed-in regression: no account deletion before verified archive lifecycle.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'fe29186f-8eb7-4d76-9c40-2d113f921cd7',true);
do $test$
declare err text;
begin
  if has_function_privilege('anon',
      'public.request_account_deletion()','execute') then
    raise exception 'Anonymous user gained account deletion execution';
  end if;
  if (select prosecdef from pg_proc
      where oid='public.request_account_deletion()'::regprocedure) then
    raise exception 'Blocked account deletion uses SECURITY DEFINER';
  end if;
  begin
    perform public.request_account_deletion();
    raise exception 'Account deletion unexpectedly permitted';
  exception when others then
    get stacked diagnostics err=message_text;
    if err not like 'Account deletion is temporarily unavailable in QA%' then
      raise exception 'Unexpected deletion behavior: %',err;
    end if;
  end;
end $test$;
rollback;
select 'PASS: account deletion stays unavailable and unprivileged' result;
