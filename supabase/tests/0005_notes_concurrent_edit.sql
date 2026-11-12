-- All records rolled back, test only.
begin;
select set_config('qa.space',space_id::text,true)
from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
from public.space_members where space_id=current_setting('qa.space')::uuid
order by joined_at,user_id limit 1;
select set_config('qa.b',user_id::text,true)
from public.space_members where space_id=current_setting('qa.space')::uuid
order by joined_at desc,user_id desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.notes(space_id,created_by,title,body,visibility)
values(current_setting('qa.space')::uuid,auth.uid(),
'QA COLLISION NOTE','Original content','shared');
select set_config('qa.note_id',(select id::text from public.notes where title='QA COLLISION NOTE'),true);
select set_config('qa.original',(select updated_at::text from public.notes
where id=current_setting('qa.note_id')::uuid),true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
update public.notes set body='Partner B updated note'
where id=current_setting('qa.note_id')::uuid;
do $$
begin
 if (select updated_at from public.notes where id=current_setting('qa.note_id')::uuid)
      <= current_setting('qa.original')::timestamptz then
   raise exception 'Timestamps are not monotonic';
 end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
do $$
begin
 update public.notes set body='Stale overwrite' where id=current_setting('qa.note_id')::uuid
  and updated_at=current_setting('qa.original')::timestamptz;
 if found then raise exception 'Stale edit overwrote partner update'; end if;
 if (select body from public.notes where id=current_setting('qa.note_id')::uuid)
   <> 'Partner B updated note' then raise exception 'Partner update was lost'; end if;
end $$;
select 'PASS: newer partner note protected from stale edits' as test_result;
rollback;
