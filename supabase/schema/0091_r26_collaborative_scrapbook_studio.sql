-- R26 Scrapbook Studio: visual pages attached to existing Memories and protected photos.
-- A shareable scrapbook can be seen by both partners; co-editing requires
-- an invitation accepted by the recipient. No existing Memories are changed.
alter table public.memories drop constraint if exists memories_memory_type_check;
alter table public.memories add constraint memories_memory_type_check
 check(memory_type in ('story','daily_selfie','collage','scrapbook'));
create table public.scrapbook_invites (
 memory_id uuid not null references public.memories(id) on delete cascade,
 invited_user_id uuid not null references auth.users(id) on delete cascade,
 invited_by uuid not null references auth.users(id),
 status text not null default 'pending'
  check(status in ('pending','accepted','declined')),
 created_at timestamptz not null default now(),
 responded_at timestamptz,
 primary key(memory_id,invited_user_id)
);
create index scrapbook_invited_user on public.scrapbook_invites(invited_user_id,status);
alter table public.scrapbook_invites enable row level security;
create policy "Scrapbook invitations visible to participants"
 on public.scrapbook_invites for select to authenticated
 using (
  invited_user_id=(select auth.uid()) or invited_by=(select auth.uid()));
revoke all on public.scrapbook_invites from public,anon,authenticated;
grant select on public.scrapbook_invites to authenticated;

create function private.may_edit_scrapbook(p_memory uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.memories m
  where m.id=p_memory and m.memory_type='scrapbook'
   and m.archived_at is null and private.is_space_member(m.space_id)
   and (m.created_by=p_user or (
    m.visibility='shared' and exists(
      select 1 from public.scrapbook_invites i
      where i.memory_id=m.id and i.invited_user_id=p_user
        and i.status='accepted'
    )
   ))
 )
$$;
revoke all on function private.may_edit_scrapbook(uuid,uuid)
 from public,anon,authenticated;

create table public.scrapbook_pages (
 id uuid primary key default gen_random_uuid(),
 memory_id uuid not null references public.memories(id) on delete cascade,
 page_order integer not null default 0 check(page_order between 0 and 100),
 template_key text not null default 'polaroid_letters'
  check(template_key in ('polaroid_letters','our_adventures','little_moments','milestone_story')),
 title text not null default '' check(length(title)<=120),
 subtitle text not null default '' check(length(subtitle)<=180),
 story_text text not null default '' check(length(story_text)<=2200),
 highlight_text text not null default '' check(length(highlight_text)<=360),
 photo_1_id uuid references public.memory_photos(id) on delete set null,
 photo_2_id uuid references public.memory_photos(id) on delete set null,
 photo_3_id uuid references public.memory_photos(id) on delete set null,
 created_by uuid not null default auth.uid() references auth.users(id),
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 unique(memory_id,page_order)
);
create index scrapbook_pages_memory_order on public.scrapbook_pages(memory_id,page_order);
alter table public.scrapbook_pages enable row level security;
create policy "Visible scrapbook pages" on public.scrapbook_pages
 for select to authenticated using(exists(
 select 1 from public.memories m where m.id=memory_id));
create policy "Invited collaborator or creator may add pages"
 on public.scrapbook_pages for insert to authenticated with check(
 created_by=(select auth.uid()) and
 private.may_edit_scrapbook(memory_id,(select auth.uid())));
create policy "Invited collaborator or creator may edit pages"
 on public.scrapbook_pages for update to authenticated using(
 private.may_edit_scrapbook(memory_id,(select auth.uid())))
 with check(private.may_edit_scrapbook(memory_id,(select auth.uid())));
revoke all on public.scrapbook_pages from public,anon,authenticated;
grant select on public.scrapbook_pages to authenticated;
grant insert(memory_id,page_order,template_key,title,subtitle,story_text,
 highlight_text,photo_1_id,photo_2_id,photo_3_id) on public.scrapbook_pages to authenticated;
grant update(template_key,title,subtitle,story_text,highlight_text,
 photo_1_id,photo_2_id,photo_3_id,updated_by,updated_at)
 on public.scrapbook_pages to authenticated;

create function private.validate_scrapbook_page_photos()
returns trigger language plpgsql set search_path='' as $$
declare requested uuid; ok boolean;
begin
 if tg_op='UPDATE' and new.memory_id<>old.memory_id then
   raise exception 'Cannot transfer a scrapbook page to another memory';
 end if;
 for requested in select distinct unnest(array[
   new.photo_1_id,new.photo_2_id,new.photo_3_id
 ]) loop
  if requested is not null then
    select exists(select 1 from public.memory_photos p
      where p.id=requested and p.memory_id=new.memory_id and p.archived_at is null)
    into ok;
    if not ok then raise exception 'Scrapbook photo is not part of this memory';end if;
  end if;
 end loop;
 new.updated_at=now();
 new.updated_by=auth.uid();
 return new;
end $$;
create trigger scrapbook_validate_photos before insert or update
 on public.scrapbook_pages for each row
 execute function private.validate_scrapbook_page_photos();
revoke all on function private.validate_scrapbook_page_photos()
 from public,anon,authenticated;

create function public.create_scrapbook(
 p_space_id uuid,p_title text,p_template_key text,
 p_visibility text default 'shared',p_memory_date date default current_date
) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; who uuid:=auth.uid();
begin
 if who is null or p_space_id is null or not private.is_space_member(p_space_id)
    or char_length(btrim(coalesce(p_title,''))) not between 1 and 120
    or p_template_key not in
     ('polaroid_letters','our_adventures','little_moments','milestone_story')
    or p_visibility not in ('shared','private')
    or p_memory_date not between date '1900-01-01' and date '2100-12-31' then
   raise exception 'Invalid scrapbook request';
 end if;
 insert into public.memories(space_id,created_by,title,body,memory_date,
  visibility,memory_type,photo_layout)
 values(p_space_id,who,btrim(p_title),'',p_memory_date,p_visibility,
  'scrapbook','grid')
 returning id into result;
 insert into public.scrapbook_pages(memory_id,page_order,template_key,created_by,
  title)values(result,0,p_template_key,who,btrim(p_title));
 return result;
end $$;
revoke all on function public.create_scrapbook(uuid,text,text,text,date)
 from public,anon,authenticated;
grant execute on function public.create_scrapbook(uuid,text,text,text,date)
 to authenticated;

create function public.invite_scrapbook_partner(p_memory_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare m record; partner uuid; me uuid:=auth.uid();
begin
 select id,space_id,created_by,visibility,memory_type,archived_at
 into m from public.memories where id=p_memory_id;
 if me is null or not found or m.created_by<>me or m.memory_type<>'scrapbook'
 or m.visibility<>'shared' or m.archived_at is not null then
  raise exception 'Only the owner of an active shared scrapbook can invite';
 end if;
 select user_id into partner from public.space_members
 where space_id=m.space_id and user_id<>me order by joined_at limit 1;
 if partner is null then raise exception 'Partner not connected';end if;
 insert into public.scrapbook_invites(memory_id,invited_user_id,invited_by,status)
 values(p_memory_id,partner,me,'pending')
 on conflict(memory_id,invited_user_id)
 do update set status='pending',responded_at=null,created_at=now()
 where public.scrapbook_invites.status='declined';
 insert into public.space_notifications(
 space_id,recipient_id,actor_id,kind,object_kind,object_id,
 headline,generated_automatically)
 values(m.space_id,partner,me,'scrapbook_invite','scrapbook',
  p_memory_id,'Your partner invited you to a scrapbook',true)
 on conflict(recipient_id,kind,object_id)
 do update set headline=excluded.headline,created_at=now(),read_at=null;
end $$;
revoke all on function public.invite_scrapbook_partner(uuid)
 from public,anon,authenticated;
grant execute on function public.invite_scrapbook_partner(uuid) to authenticated;

create function public.respond_scrapbook_invite(p_memory_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Login required';end if;
 update public.scrapbook_invites i set
 status=case when p_accept then 'accepted' else 'declined' end,
 responded_at=now()
 where i.memory_id=p_memory_id and i.invited_user_id=auth.uid()
 and i.status='pending' and exists(select 1 from public.memories m
  where m.id=i.memory_id and m.visibility='shared'
  and m.memory_type='scrapbook' and m.archived_at is null
  and private.is_space_member(m.space_id));
 if not found then raise exception 'Invitation is not available';end if;
end $$;
revoke all on function public.respond_scrapbook_invite(uuid,boolean)
 from public,anon,authenticated;
grant execute on function public.respond_scrapbook_invite(uuid,boolean)
 to authenticated;
alter table public.space_notifications drop constraint space_notifications_kind_check;
alter table public.space_notifications add constraint space_notifications_kind_check
 check(kind in ('mention','reply','letter','event','gesture','reminder',
 'checkin_request','checkin_response','checkin_shared','experience_suggestion',
 'experience_comment','trip_suggestion','trip_message','trip_document',
 'occasion_shared','scrapbook_invite'));
alter table public.space_notifications drop constraint space_notifications_object_kind_check;
alter table public.space_notifications add constraint space_notifications_object_kind_check
 check(object_kind in ('activity','letter','calendar','gesture','note',
 'checkin','checkin_request','experience','trip','occasion','task','reminder','scrapbook'));
alter publication supabase_realtime add table public.scrapbook_pages;
alter publication supabase_realtime add table public.scrapbook_invites;
