-- R26: rollback-only scrapbook collaborator and cross-memory integrity test.
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
select set_config('qa.scrap',
 public.create_scrapbook(current_setting('qa.space')::uuid,
 'QA scrapbook R26','polaroid_letters','shared',current_date)::text,true);
select set_config('qa.private',
 public.create_scrapbook(current_setting('qa.space')::uuid,
 'QA private scrapbook R26','little_moments','private',current_date)::text,true);
do $t$ begin
 if (select count(*) from public.scrapbook_pages
   where memory_id=current_setting('qa.scrap')::uuid)<>1 then
  raise exception 'First page not atomically created';end if;
end $t$;
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $t$ declare rejected boolean:=false;
begin
 if exists(select 1 from public.memories
  where id=current_setting('qa.private')::uuid) then
  raise exception 'Private scrapbook leaked';end if;
 if (select count(*) from public.scrapbook_pages
  where memory_id=current_setting('qa.scrap')::uuid)<>1 then
  raise exception 'Shared scrapbook not visible';end if;
 begin
  insert into public.scrapbook_pages(memory_id,page_order,title)
   values(current_setting('qa.scrap')::uuid,1,'Forged page');
 exception when others then rejected:=true;end;
 if not rejected then raise exception 'Uninvited partner can edit';end if;
end $t$;
select set_config('request.jwt.claim.sub',current_setting('qa.a'),true);
select public.invite_scrapbook_partner(current_setting('qa.scrap')::uuid);
select set_config('request.jwt.claim.sub',current_setting('qa.b'),true);
do $t$ begin
 if (select count(*) from public.space_notifications
  where kind='scrapbook_invite' and object_id=current_setting('qa.scrap')::uuid)<>1
 then raise exception 'Collaboration invitation notification missing for recipient';end if;
end $t$;
select public.respond_scrapbook_invite(current_setting('qa.scrap')::uuid,true);
insert into public.scrapbook_pages(memory_id,page_order,template_key,title,story_text)
 values(current_setting('qa.scrap')::uuid,1,'milestone_story',
 'Partner-authored page','Our big day');
do $t$ declare rejected boolean:=false;
begin
 if (select count(*) from public.scrapbook_pages
  where memory_id=current_setting('qa.scrap')::uuid)<>2 then
 raise exception 'Accepted collaborator page missing';end if;
 begin
  insert into public.scrapbook_pages(memory_id,page_order,photo_1_id)
   values(current_setting('qa.scrap')::uuid,2,gen_random_uuid());
 exception when others then rejected:=true; end;
 if not rejected then raise exception 'Foreign photo reference accepted';end if;
end $t$;
select 'PASS: R26 scrapbook private access, invitation acceptance, page collaboration and photo enforcement' result;
rollback;