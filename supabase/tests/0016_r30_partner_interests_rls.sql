-- Run in one transaction; never persist QA rows, notices or interest votes.
begin;
select set_config('qa.space',space_id::text,true)
 from public.space_members group by space_id having count(*)=2 limit 1;
select set_config('qa.a',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at limit 1;
select set_config('qa.b',user_id::text,true)
 from public.space_members where space_id=current_setting('qa.space')::uuid
 order by joined_at desc limit 1;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
insert into public.shared_experiences(space_id,category,title)
 values(current_setting('qa.space')::uuid,'movie','QA R30 interest permissions');
select set_config('qa.experience',(select id::text from public.shared_experiences
 where title='QA R30 interest permissions' limit 1),true);
insert into public.shared_experience_interests(experience_id,choice)
 values(current_setting('qa.experience')::uuid,'yes');

select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $qa$
declare denied boolean:=false; affected int;
begin
 if (select count(*) from public.shared_experience_interests
  where experience_id=current_setting('qa.experience')::uuid
   and choice='yes')<>1 then
  raise exception 'Partner cannot read first member interest';end if;
 update public.shared_experience_interests set choice='not_now'
 where experience_id=current_setting('qa.experience')::uuid
  and user_id=current_setting('qa.a')::uuid;
 get diagnostics affected=row_count;
 if affected<>0 then raise exception 'Partner edited other member choice';end if;
 begin
  insert into public.shared_experience_interests(experience_id,user_id,choice)
   values(current_setting('qa.experience')::uuid,
    current_setting('qa.a')::uuid,'maybe');
 exception when others then denied:=true;end;
 if not denied then raise exception 'Forged user_id was inserted';end if;
 insert into public.shared_experience_interests(experience_id,choice)
 values(current_setting('qa.experience')::uuid,'maybe');
 update public.shared_experience_interests set choice='yes'
 where experience_id=current_setting('qa.experience')::uuid
  and user_id=current_setting('qa.b')::uuid;
 get diagnostics affected=row_count;
 if affected<>1 then raise exception 'Own choice cannot be updated';end if;
 if (select count(*) from public.shared_experience_interests
  where experience_id=current_setting('qa.experience')::uuid
   and choice='yes')<>2 then
  raise exception 'Both partner interests not visible';end if;
end $qa$;
select 'PASS: R30 partner interest visibility, ownership and edit controls' result;
rollback;