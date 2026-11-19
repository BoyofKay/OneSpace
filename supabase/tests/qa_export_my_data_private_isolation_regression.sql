-- QA-only rollback regression: export_my_data is caller scoped, and
-- anonymous callers cannot execute the privileged JSON export.
begin;
do $qa$
declare
 sid uuid; a uuid; b uuid; payload jsonb;
begin
 select s.id,s.created_by,m.user_id into sid,a,b
 from public.spaces s join public.space_members m
 on m.space_id=s.id and m.user_id<>s.created_by
 where (select count(*) from public.space_members x where x.space_id=s.id)=2
 limit 1;
 if sid is null then raise exception 'Paired QA fixture unavailable'; end if;
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,a,'QA OWNER SECRET EXPORT CHECK','Only A private','private');
 insert into public.notes(space_id,created_by,title,body,visibility)
 values(sid,b,'QA PARTNER SECRET EXPORT CHECK','Only B private','private');
 if has_function_privilege('anon','public.export_my_data()','execute') then
  raise exception 'Anonymous export privilege must be denied';end if;
 perform set_config('role','authenticated',true);
 perform set_config('request.jwt.claim.sub',a::text,true);
 payload:=public.export_my_data();
 if payload::text not like '%QA OWNER SECRET EXPORT CHECK%'
 or payload::text like '%QA PARTNER SECRET EXPORT CHECK%' then
  raise exception 'Account A export improperly scoped';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 payload:=public.export_my_data();
 if payload::text not like '%QA PARTNER SECRET EXPORT CHECK%'
 or payload::text like '%QA OWNER SECRET EXPORT CHECK%' then
  raise exception 'Account B export improperly scoped';end if;
end $qa$;
rollback;
select 'PASS: export_my_data private-note isolation for both partners and anon denial; rollback complete' result;
