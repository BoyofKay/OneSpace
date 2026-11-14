-- Rollback-only security test with paired accounts.
begin;
select set_config('qa.space',space_id::text,true) from public.space_members
 group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true) from public.space_members
 where space_id=current_setting('qa.space')::uuid order by user_id limit 1;
select set_config('qa.b',user_id::text,true) from public.space_members
 where space_id=current_setting('qa.space')::uuid order by user_id desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.memories(space_id,created_by,title,body,memory_date,visibility,memory_type,photo_layout)
values
 (current_setting('qa.space')::uuid,auth.uid(),'QA PRIVATE MEMORY','Only me',date '2026-11-12','private','daily_selfie','polaroid'),
 (current_setting('qa.space')::uuid,auth.uid(),'QA SHARED MEMORY','Together',date '2026-11-12','shared','collage','grid');
select set_config('qa.private',(select id::text from public.memories where title='QA PRIVATE MEMORY'),true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
begin
 if (select count(*) from public.memories where title='QA PRIVATE MEMORY')<>0
 then raise exception 'Private memory leaked'; end if;
 if (select count(*) from public.memories where title='QA SHARED MEMORY')<>1
 then raise exception 'Shared memory unreadable'; end if;
 if (public.get_home_snapshot()->>'memories_count')::int<>1
 then raise exception 'Home counted someone else private memory'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.set_object_share('memory',current_setting('qa.private')::uuid,true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
begin
 if (select count(*) from public.memories where id=current_setting('qa.private')::uuid)<>1
 then raise exception 'Grant not effective'; end if;
 update public.memories set body='ILLEGAL' where id=current_setting('qa.private')::uuid;
 if found then raise exception 'Private memory viewer can edit'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.set_object_share('memory',current_setting('qa.private')::uuid,false);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
begin
 if (select count(*) from public.memories where id=current_setting('qa.private')::uuid)<>0
 then raise exception 'Revoked memory still readable'; end if;
end $$;
select 'PASS: private/shared memories, Home counts, view-only and revocation' as result;
rollback;