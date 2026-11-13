-- R13 Shared Experiences. Additive: preserve every account, pairing and existing row.
-- Couples can discover, plan, enjoy, review and discuss media or shared games.
create table public.shared_experiences (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.spaces(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id),
  category text not null check (category in ('movie','show','music','book','game','other')),
  title text not null check (char_length(btrim(title)) between 1 and 160),
  description text not null default '' check (char_length(description) <= 5000),
  source_url text not null default '' check (char_length(source_url) <= 1800),
  platform text not null default '' check (char_length(platform) <= 100),
  status text not null default 'suggested' check (status in ('suggested','planned','enjoyed')),
  planned_on date,
  enjoyed_on date,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index shared_experiences_space_updated
  on public.shared_experiences (space_id,updated_at desc);
alter table public.shared_experiences enable row level security;
create policy "Couple sees shared experiences" on public.shared_experiences
  for select to authenticated
  using (private.is_space_member(space_id));
create policy "Member suggests experience under own identity" on public.shared_experiences
  for insert to authenticated
  with check (created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy "Members collaborate on shared experiences" on public.shared_experiences
  for update to authenticated
  using (private.is_space_member(space_id))
  with check (private.is_space_member(space_id));
revoke all on public.shared_experiences from public,anon,authenticated;
grant select on public.shared_experiences to authenticated;
grant insert (space_id,category,title,description,source_url,platform,status,planned_on,enjoyed_on)
  on public.shared_experiences to authenticated;
grant update (category,title,description,source_url,platform,status,planned_on,enjoyed_on,archived_at)
  on public.shared_experiences to authenticated;

create table public.shared_experience_reviews (
  experience_id uuid not null references public.shared_experiences(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id),
  rating smallint check (rating between 1 and 5),
  review text not null default '' check (char_length(review)<=2000),
  updated_at timestamptz not null default now(),
  primary key (experience_id,user_id),
  check (rating is not null or char_length(btrim(review))>0)
);
alter table public.shared_experience_reviews enable row level security;
create policy "Couple reads both reviews" on public.shared_experience_reviews
  for select to authenticated using (
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id))
  );
create policy "Member authors only own review" on public.shared_experience_reviews
  for insert to authenticated with check (
    user_id=(select auth.uid()) and
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id))
  );
create policy "Member edits only own review" on public.shared_experience_reviews
  for update to authenticated
  using (user_id=(select auth.uid()) and
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id)))
  with check (user_id=(select auth.uid()) and
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id)));
revoke all on public.shared_experience_reviews from public,anon,authenticated;
grant select on public.shared_experience_reviews to authenticated;
grant insert (experience_id,user_id,rating,review)
  on public.shared_experience_reviews to authenticated;
grant update (rating,review) on public.shared_experience_reviews to authenticated;

create table public.shared_experience_comments (
  id uuid primary key default gen_random_uuid(),
  experience_id uuid not null references public.shared_experiences(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);
create index shared_experience_comments_order
  on public.shared_experience_comments (experience_id,created_at,id);
alter table public.shared_experience_comments enable row level security;
create policy "Couple reads conversation" on public.shared_experience_comments
  for select to authenticated using (
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id))
  );
create policy "Member writes own contribution" on public.shared_experience_comments
  for insert to authenticated with check (
    created_by=(select auth.uid()) and
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id))
  );
create policy "Member may retract own comment" on public.shared_experience_comments
  for update to authenticated
  using (created_by=(select auth.uid()) and
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id)))
  with check (created_by=(select auth.uid()) and
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id)));
revoke all on public.shared_experience_comments from public,anon,authenticated;
grant select on public.shared_experience_comments to authenticated;
grant insert (experience_id,body) on public.shared_experience_comments to authenticated;
grant update (archived_at) on public.shared_experience_comments to authenticated;

create table public.shared_experience_revisions (
  id bigint generated always as identity primary key,
  experience_id uuid not null references public.shared_experiences(id) on delete cascade,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now(),
  before_snapshot jsonb not null,
  after_snapshot jsonb not null
);
create index shared_experience_revision_order
  on public.shared_experience_revisions (experience_id,changed_at desc);
alter table public.shared_experience_revisions enable row level security;
create policy "Couple sees experience change history" on public.shared_experience_revisions
  for select to authenticated using (
    exists (select 1 from public.shared_experiences x
      where x.id=experience_id and private.is_space_member(x.space_id))
  );
revoke all on public.shared_experience_revisions from public,anon,authenticated;
grant select on public.shared_experience_revisions to authenticated;

create function private.experience_update_audit()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  new.updated_at:=now();
  if (old.category,old.title,old.description,old.source_url,
       old.platform,old.status,old.planned_on,old.enjoyed_on,old.archived_at)
     is distinct from
     (new.category,new.title,new.description,new.source_url,
       new.platform,new.status,new.planned_on,new.enjoyed_on,new.archived_at) then
    insert into public.shared_experience_revisions
      (experience_id,changed_by,before_snapshot,after_snapshot)
    values (new.id,auth.uid(),
      jsonb_build_object('title',old.title,'category',old.category,
        'status',old.status,'description',old.description,
        'planned_on',old.planned_on,'enjoyed_on',old.enjoyed_on,
        'archived_at',old.archived_at),
      jsonb_build_object('title',new.title,'category',new.category,
        'status',new.status,'description',new.description,
        'planned_on',new.planned_on,'enjoyed_on',new.enjoyed_on,
        'archived_at',new.archived_at));
  end if;
  return new;
end; $$;
create trigger experience_update_audit before update on public.shared_experiences
  for each row execute function private.experience_update_audit();

create function private.experience_review_touch()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  new.updated_at:=now();
  return new;
end; $$;
create trigger experience_review_touch before update on public.shared_experience_reviews
  for each row execute function private.experience_review_touch();

-- Extend notifications without affecting existing notification rows.
alter table public.space_notifications
  add column experience_id uuid references public.shared_experiences(id) on delete set null;
alter table public.space_notifications drop constraint space_notifications_kind_check;
alter table public.space_notifications add constraint space_notifications_kind_check
  check (kind in ('mention','reply','letter','event','gesture','reminder',
    'checkin_request','checkin_response','checkin_shared',
    'experience_suggestion','experience_comment'));
alter table public.space_notifications drop constraint space_notifications_object_kind_check;
alter table public.space_notifications add constraint space_notifications_object_kind_check
  check (object_kind in ('activity','letter','calendar','gesture','note',
    'checkin','checkin_request','experience'));

create function private.experience_suggestion_notice()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into public.space_notifications
    (space_id,recipient_id,actor_id,kind,object_kind,object_id,experience_id,headline)
  select new.space_id,m.user_id,new.created_by,
    'experience_suggestion','experience',new.id,new.id,
    left('New idea together: '||new.title,180)
  from public.space_members m
  where m.space_id=new.space_id and m.user_id<>new.created_by
  on conflict do nothing;
  return new;
end; $$;
create trigger experience_suggestion_notice after insert on public.shared_experiences
  for each row execute function private.experience_suggestion_notice();

create function private.experience_comment_notice()
returns trigger language plpgsql security definer set search_path='' as $$
declare x record;
begin
  select space_id,title into x from public.shared_experiences
   where id=new.experience_id;
  if not found then return new; end if;
  insert into public.space_notifications
    (space_id,recipient_id,actor_id,kind,object_kind,object_id,experience_id,headline)
  select x.space_id,m.user_id,new.created_by,
    'experience_comment','experience',new.id,new.experience_id,
    left('New thought on '||x.title,180)
  from public.space_members m
  where m.space_id=x.space_id and m.user_id<>new.created_by
  on conflict do nothing;
  return new;
end; $$;
create trigger experience_comment_notice after insert on public.shared_experience_comments
  for each row execute function private.experience_comment_notice();

alter publication supabase_realtime add table public.shared_experiences;
alter publication supabase_realtime add table public.shared_experience_reviews;
alter publication supabase_realtime add table public.shared_experience_comments;
