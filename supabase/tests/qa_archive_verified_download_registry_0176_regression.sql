-- QA 0176: fail closed if a ready archive is not independently verified.
-- Both negative and positive registry cases are rolled back.
begin;
do $qa$
declare
  user_id uuid; sid uuid; ready_time timestamptz:=now();
  test_id uuid; err text;
begin
  select sm.user_id,sm.space_id into user_id,sid
   from public.space_members sm limit 1;
  if user_id is null then raise exception 'QA membership fixture missing';end if;
  begin
    insert into public.space_archives(
       old_space_id,recipient_id,archive_kind,status,
       ready_at,expires_at,encrypted_object_path,
       ciphertext_sha256,byte_length,encrypted_bytes_verified)
    values(sid,user_id,'private','ready',ready_time,
       ready_time+interval '30 days',
       user_id::text||'/qa-unverified-archive-test.onespace',
       repeat('a',64),120,false);
    raise exception 'Unverified ready archive was accepted';
  exception when check_violation then
    get stacked diagnostics err=constraint_name;
    if err<>'ready_archives_complete' then
      raise exception 'Unexpected archive constraint: %',err;
    end if;
  end;
  insert into public.space_archives(
       old_space_id,recipient_id,archive_kind,status,
       ready_at,expires_at,encrypted_object_path,
       ciphertext_sha256,byte_length,encrypted_bytes_verified)
  values(sid,user_id,'private','ready',ready_time,
       ready_time+interval '30 days',
       user_id::text||'/qa-verified-archive-test.onespace',
       repeat('b',64),120,true)
  returning id into test_id;
  if not exists(select 1 from public.space_archives a
    where a.id=test_id and a.status='ready'
      and a.encrypted_bytes_verified) then
    raise exception 'Verified archive registry test row did not persist';end if;
end $qa$;
rollback;
select 'PASS: unverified ready archive rejected by database, verified metadata allowed; synthetic rows rolled back' result;
