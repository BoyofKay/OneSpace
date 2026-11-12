begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true) from public.space_members
 where space_id=current_setting('qa.space')::uuid order by joined_at,user_id limit 1;
select set_config('qa.b',user_id::text,true) from public.space_members
 where space_id=current_setting('qa.space')::uuid order by joined_at desc,user_id desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.goals(space_id,created_by,title,visibility)
values(current_setting('qa.space')::uuid,auth.uid(),'QA PRIVATE GOAL','private');
insert into public.goals(space_id,created_by,title,visibility)
values(current_setting('qa.space')::uuid,auth.uid(),'QA SHARED GOAL','shared');
insert into public.daily_checkins(space_id,created_by,checkin_date,mood,message,visibility)
values(current_setting('qa.space')::uuid,auth.uid(),date '2024-03-15',4,'QA PRIVATE CHECKIN','private');
select set_config('qa.goal',(select id::text from public.goals where title='QA PRIVATE GOAL'),true);
select set_config('qa.checkin',(select id::text from public.daily_checkins where message='QA PRIVATE CHECKIN'),true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
declare rejected boolean:=false;
begin
 if (select count(*) from public.goals where title='QA PRIVATE GOAL')<>0 then raise exception 'private goal leak'; end if;
 if (select count(*) from public.daily_checkins where message='QA PRIVATE CHECKIN')<>0 then raise exception 'private checkin leak'; end if;
 update public.goals set progress=40 where title='QA SHARED GOAL';
 if not found then raise exception 'partner cannot update shared goal'; end if;
 begin
  perform public.set_object_share('goal',current_setting('qa.goal')::uuid,true);
 exception when others then rejected:=true;
 end;
 if not rejected then raise exception 'partner could forge grant'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.set_object_share('goal',current_setting('qa.goal')::uuid,true);
select public.set_object_share('checkin',current_setting('qa.checkin')::uuid,true);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
begin
 if (select count(*) from public.goals where id=current_setting('qa.goal')::uuid)<>1 then raise exception 'goal share inaccessible'; end if;
 if (select count(*) from public.daily_checkins where id=current_setting('qa.checkin')::uuid)<>1 then raise exception 'checkin share inaccessible'; end if;
 update public.goals set progress=85 where id=current_setting('qa.goal')::uuid;
 if found then raise exception 'read-only goal changed'; end if;
 update public.daily_checkins set mood=2 where id=current_setting('qa.checkin')::uuid;
 if found then raise exception 'read-only checkin changed'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.set_object_share('goal',current_setting('qa.goal')::uuid,false);
select public.set_object_share('checkin',current_setting('qa.checkin')::uuid,false);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $$
begin
 if (select count(*) from public.goals where id=current_setting('qa.goal')::uuid)<>0 then raise exception 'goal revoke failed'; end if;
 if (select count(*) from public.daily_checkins where id=current_setting('qa.checkin')::uuid)<>0 then raise exception 'checkin revoke failed'; end if;
end $$;
select 'PASS: collaborative goals + creator-only check-ins, private view grant and revoke' as verification;
rollback;