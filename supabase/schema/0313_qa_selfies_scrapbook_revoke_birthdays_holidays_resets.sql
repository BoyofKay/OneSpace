-- QA 0313 (Amr's 21 Nov test findings). QA only; never apply to Production.
--  1. Daily selfies are allowed in the personal space (solo too); one a day.
--  2. A scrapbook owner can withdraw the invitation or stop co-editing.
--  3. Living arrangement & meeting dates need both partners.
--  4. Each person owns their birthday, and chooses whether their partner sees
--     it and whether the year is shown. Both choices reset to "no" whenever
--     the pairing changes (partner joins, leaves, is removed, space deleted).
--  5. Preferred names for a partner reset when the pairing ends.
--  6. Each person chooses their own holiday countries (any country); a
--     current partner sees them too.

-- 1. Daily selfies -------------------------------------------------------
alter table public.memories drop constraint if exists qa_private_memories_story_only;
alter table public.memories add constraint qa_private_memories_story_only
 check(private_space_id is null or memory_type in ('story','scrapbook','daily_selfie')) not valid;
create unique index if not exists qa_one_daily_selfie_per_person_per_day
 on public.memories(created_by, memory_date)
 where memory_type='daily_selfie' and archived_at is null;

-- 2. Scrapbook invitation withdraw / stop co-editing -----------------------
create or replace function public.revoke_scrapbook_invite(p_memory_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare me uuid:=auth.uid(); m record;
begin
 select id,created_by,memory_type,visibility,archived_at into m
 from public.memories where id=p_memory_id;
 if me is null or not found or m.created_by<>me or m.memory_type<>'scrapbook'
    or m.visibility<>'shared' or m.archived_at is not null then
  raise exception 'Only the owner of a shared scrapbook can withdraw the invitation'
   using errcode='42501';
 end if;
 delete from public.scrapbook_invites i
  where i.memory_id=p_memory_id and i.status in ('pending','accepted');
 if not found then raise exception 'There is no invitation to withdraw'; end if;
 delete from public.space_notifications n
  where n.kind='scrapbook_invite' and n.object_id=p_memory_id;
end $$;
revoke all on function public.revoke_scrapbook_invite(uuid) from public,anon,authenticated;
grant execute on function public.revoke_scrapbook_invite(uuid) to authenticated;

-- Helper: is p_user my partner in a complete (two-person) couple space?
create or replace function private.qa_is_current_partner(p_user uuid)
returns boolean language sql stable security definer set search_path to '' as $$
 select (select auth.uid()) is not null and p_user is not null
  and p_user<>(select auth.uid())
  and exists(select 1 from public.space_members a
   join public.space_members b on b.space_id=a.space_id
   where a.user_id=(select auth.uid()) and b.user_id=p_user
     and (select count(*) from public.space_members c where c.space_id=a.space_id)=2)
$$;
revoke all on function private.qa_is_current_partner(uuid) from public,anon;
grant execute on function private.qa_is_current_partner(uuid) to authenticated;

-- 3. Relationship settings need two partners --------------------------------
create or replace function private.qa_relationship_settings_need_pair()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
 if (select auth.uid()) is not null
    and (new.relationship_mode is distinct from old.relationship_mode
      or new.last_met_on is distinct from old.last_met_on
      or new.next_meet_on is distinct from old.next_meet_on)
    and (select count(*) from public.space_members m where m.space_id=new.id)<>2 then
  raise exception 'Living arrangement can be set once your partner joins' using errcode='42501';
 end if;
 return new;
end $$;
drop trigger if exists qa_relationship_settings_need_pair on public.spaces;
create trigger qa_relationship_settings_need_pair before update on public.spaces
 for each row execute function private.qa_relationship_settings_need_pair();

-- 4. Account-owned birthdays --------------------------------------------
create table if not exists public.account_birthdays (
 user_id uuid primary key references auth.users(id) on delete cascade default auth.uid(),
 month smallint not null check (month between 1 and 12),
 day smallint not null check (day between 1 and 31),
 year smallint check (year between 1900 and 2100),
 share_with_partner boolean not null default false,
 share_year boolean not null default false,
 updated_at timestamptz not null default now(),
 check (make_date(2000, month, 1) + (day - 1) < (make_date(2000, month, 1) + interval '1 month')::date)
);
alter table public.account_birthdays enable row level security;
drop policy if exists "Own birthday" on public.account_birthdays;
create policy "Own birthday" on public.account_birthdays for all to authenticated
 using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
revoke all on public.account_birthdays from public,anon,authenticated;
grant select,insert,update,delete on public.account_birthdays to authenticated;

-- The partner's birthday, only what they chose to share.
create or replace function public.partner_birthday()
returns table(person_id uuid, month smallint, day smallint, year smallint)
language sql stable security definer set search_path to '' as $$
 select b.user_id, b.month, b.day, case when b.share_year then b.year end
 from public.account_birthdays b
 where b.share_with_partner and private.qa_is_current_partner(b.user_id)
$$;
revoke all on function public.partner_birthday() from public,anon,authenticated;
grant execute on function public.partner_birthday() to authenticated;

-- 6. Account-owned holiday countries ------------------------------------
create table if not exists public.account_holiday_countries (
 user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
 country_code text not null check (country_code ~ '^[A-Z]{2}$'),
 created_at timestamptz not null default now(),
 primary key (user_id, country_code)
);
alter table public.account_holiday_countries enable row level security;
drop policy if exists "Own holiday countries" on public.account_holiday_countries;
create policy "Own holiday countries" on public.account_holiday_countries for all to authenticated
 using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
drop policy if exists "Partner holiday countries" on public.account_holiday_countries;
create policy "Partner holiday countries" on public.account_holiday_countries for select to authenticated
 using (private.qa_is_current_partner(user_id));
revoke all on public.account_holiday_countries from public,anon,authenticated;
grant select,insert,delete on public.account_holiday_countries to authenticated;

-- 4 + 5. Pairing changed: reset sharing choices and partner names --------
create or replace function private.qa_reset_on_pairing_change()
returns trigger language plpgsql security definer set search_path to '' as $$
declare s uuid:=coalesce(new.space_id, old.space_id);
 people uuid[];
begin
 select array_agg(m.user_id) into people from public.space_members m where m.space_id=s;
 people:=coalesce(people,'{}')||coalesce(new.user_id, old.user_id);
 update public.account_birthdays b set share_with_partner=false, share_year=false, updated_at=now()
  where b.user_id=any(people) and (b.share_with_partner or b.share_year);
 if tg_op='DELETE' then
  update public.profiles p set partner_label=null, partner_labels='{}'
   where p.id=any(people) and (p.partner_label is not null or cardinality(p.partner_labels)>0);
 end if;
 return null;
end $$;
drop trigger if exists qa_reset_on_pairing_change on public.space_members;
create trigger qa_reset_on_pairing_change after insert or delete on public.space_members
 for each row execute function private.qa_reset_on_pairing_change();
