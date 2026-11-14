-- R30: Each partner expresses their own preference for a shared experience.
-- Additive: no modifications to existing experiences, reviews or notifications.
create table public.shared_experience_interests (
 experience_id uuid not null references public.shared_experiences(id)
  on delete cascade,
 user_id uuid not null default auth.uid() references auth.users(id),
 choice text not null default 'undecided'
  check (choice in ('yes','maybe','not_now','undecided')),
 updated_at timestamptz not null default now(),
 primary key (experience_id,user_id)
);
create index shared_experience_interests_user
 on public.shared_experience_interests(user_id,updated_at desc);

alter table public.shared_experience_interests enable row level security;
create policy "Couple reads partner preferences"
 on public.shared_experience_interests for select to authenticated
 using (exists (
  select 1 from public.shared_experiences e
  where e.id=experience_id and private.is_space_member(e.space_id)
 ));
create policy "Partner creates own preference"
 on public.shared_experience_interests for insert to authenticated
 with check (
  user_id=(select auth.uid()) and exists (
   select 1 from public.shared_experiences e
   where e.id=experience_id and private.is_space_member(e.space_id)
  )
 );
create policy "Partner changes only own preference"
 on public.shared_experience_interests for update to authenticated
 using (
  user_id=(select auth.uid()) and exists (
   select 1 from public.shared_experiences e
   where e.id=experience_id and private.is_space_member(e.space_id)
  )
 )
 with check (
  user_id=(select auth.uid()) and exists (
   select 1 from public.shared_experiences e
   where e.id=experience_id and private.is_space_member(e.space_id)
  )
 );

revoke all on public.shared_experience_interests from public,anon,authenticated;
grant select on public.shared_experience_interests to authenticated;
grant insert (experience_id,choice) on public.shared_experience_interests to authenticated;
grant update (choice) on public.shared_experience_interests to authenticated;

create function private.experience_interest_touch()
 returns trigger language plpgsql set search_path='' as $$
begin
 new.updated_at:=now();
 return new;
end $$;
create trigger experience_interest_touch
 before update on public.shared_experience_interests
 for each row execute function private.experience_interest_touch();
revoke all on function private.experience_interest_touch()
 from public,anon,authenticated;

alter publication supabase_realtime add table public.shared_experience_interests;
