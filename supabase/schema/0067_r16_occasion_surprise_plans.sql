-- R16: Occasion and surprise planning, additive and privacy-first.
create table public.occasion_plans (
 id uuid primary key default gen_random_uuid(),
 space_id uuid not null references public.spaces(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check(char_length(btrim(title)) between 1 and 160),
 occasion_on date not null,
 annual boolean not null default true,
 kind text not null default 'other' check(kind in
  ('birthday','anniversary','holiday','celebration','other')),
 visibility text not null default 'private' check(visibility in ('shared','private')),
 status text not null default 'planning' check(status in ('planning','preparing','ready','celebrated','cancelled')),
 prep_lead_days int not null default 30 check(prep_lead_days between 0 and 365),
 saving_lead_days int not null default 60 check(saving_lead_days between 0 and 365),
 budget numeric(12,2) check (budget>=0),
 currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
 notes text not null default '' check(char_length(notes)<=5000),
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index occasion_plans_space_date on public.occasion_plans(space_id,occasion_on,updated_at desc);
alter table public.occasion_plans enable row level security;
create policy "Read accessible occasions" on public.occasion_plans
 for select to authenticated using (
  private.is_space_member(space_id) and
   (visibility='shared' or created_by=(select auth.uid())));
create policy "Only member may create own occasion" on public.occasion_plans
 for insert to authenticated with check (
  created_by=(select auth.uid()) and private.is_space_member(space_id));
create policy "Update accessible occasion" on public.occasion_plans
 for update to authenticated
 using(private.is_space_member(space_id) and
  (visibility='shared' or created_by=(select auth.uid())))
 with check(private.is_space_member(space_id) and
  (visibility='shared' or created_by=(select auth.uid())));
revoke all on public.occasion_plans from public,anon,authenticated;
grant select on public.occasion_plans to authenticated;
grant insert(space_id,title,occasion_on,annual,kind,visibility,status,
 prep_lead_days,saving_lead_days,budget,currency,notes) on public.occasion_plans to authenticated;
-- No visibility updates: surprises cannot accidentally be exposed by an edit.
grant update(title,occasion_on,annual,kind,status,prep_lead_days,
 saving_lead_days,budget,currency,notes,archived_at) on public.occasion_plans to authenticated;

create table public.occasion_plan_steps (
 id uuid primary key default gen_random_uuid(),
 plan_id uuid not null references public.occasion_plans(id) on delete cascade,
 created_by uuid not null default auth.uid() references auth.users(id),
 title text not null check(char_length(btrim(title)) between 1 and 200),
 due_on date,
 estimated_cost numeric(12,2) check(estimated_cost>=0),
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 done boolean not null default false,
 archived_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index occasion_steps_plan_due on public.occasion_plan_steps(plan_id,due_on,created_at);
alter table public.occasion_plan_steps enable row level security;
create policy "Read steps of visible occasion" on public.occasion_plan_steps
 for select to authenticated using(exists(
  select 1 from public.occasion_plans p where p.id=plan_id));
create policy "Insert step on visible occasion" on public.occasion_plan_steps
 for insert to authenticated with check(created_by=(select auth.uid())
  and exists(select 1 from public.occasion_plans p where p.id=plan_id));
create policy "Update steps of visible occasion" on public.occasion_plan_steps
 for update to authenticated using(exists(
  select 1 from public.occasion_plans p where p.id=plan_id))
 with check(exists(select 1 from public.occasion_plans p where p.id=plan_id));
revoke all on public.occasion_plan_steps from public,anon,authenticated;
grant select on public.occasion_plan_steps to authenticated;
grant insert(plan_id,title,due_on,estimated_cost,currency,done)
 on public.occasion_plan_steps to authenticated;
grant update(title,due_on,estimated_cost,currency,done,archived_at)
 on public.occasion_plan_steps to authenticated;

create table public.occasion_plan_revisions (
 id bigint generated always as identity primary key,
 plan_id uuid not null references public.occasion_plans(id) on delete cascade,
 record_kind text not null check(record_kind in ('plan','step')),
 record_id uuid not null,
 changed_by uuid references auth.users(id),
 changed_at timestamptz not null default now(),
 before_snapshot jsonb not null,
 after_snapshot jsonb not null
);
create index occasion_revisions_plan_changed
 on public.occasion_plan_revisions(plan_id,changed_at desc);
alter table public.occasion_plan_revisions enable row level security;
create policy "Read history of visible occasion" on public.occasion_plan_revisions
 for select to authenticated using(exists(
  select 1 from public.occasion_plans p where p.id=plan_id));
revoke all on public.occasion_plan_revisions from public,anon,authenticated;
grant select on public.occasion_plan_revisions to authenticated;

create function private.audit_occasion_change()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_plan uuid;v_kind text;
begin
 if TG_TABLE_NAME='occasion_plans' then
  v_plan:=new.id;v_kind:='plan';
 else
  v_plan:=new.plan_id;v_kind:='step';
 end if;
 new.updated_at:=now();
 if to_jsonb(old) is distinct from to_jsonb(new) then
  insert into public.occasion_plan_revisions
   (plan_id,record_kind,record_id,changed_by,before_snapshot,after_snapshot)
  values(v_plan,v_kind,new.id,auth.uid(),to_jsonb(old),to_jsonb(new));
 end if;
 return new;
end; $$;
create trigger occasion_audit before update on public.occasion_plans
 for each row execute function private.audit_occasion_change();
create trigger occasion_step_audit before update on public.occasion_plan_steps
 for each row execute function private.audit_occasion_change();
revoke all on function private.audit_occasion_change() from public,anon,authenticated;

alter table public.space_notifications drop constraint space_notifications_kind_check;
alter table public.space_notifications add constraint space_notifications_kind_check check
(kind in ('mention','reply','letter','event','gesture','reminder',
 'checkin_request','checkin_response','checkin_shared',
 'experience_suggestion','experience_comment','trip_suggestion','trip_message',
 'trip_document','occasion_shared'));
alter table public.space_notifications drop constraint space_notifications_object_kind_check;
alter table public.space_notifications add constraint space_notifications_object_kind_check check
(object_kind in ('activity','letter','calendar','gesture','note',
 'checkin','checkin_request','experience','trip','occasion'));

alter table public.space_notifications add column occasion_id uuid
 references public.occasion_plans(id) on delete set null;
create function private.notify_shared_occasion()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.visibility<>'shared' then return new; end if;
 insert into public.space_notifications
  (space_id,recipient_id,actor_id,kind,object_kind,object_id,occasion_id,headline)
 select new.space_id,m.user_id,new.created_by,'occasion_shared','occasion',
  new.id,new.id,left('Occasion plan: '||new.title,180)
 from public.space_members m
 where m.space_id=new.space_id and m.user_id<>new.created_by
 on conflict do nothing;
 return new;
end; $$;
create trigger notify_occasion_on_create after insert on public.occasion_plans
 for each row execute function private.notify_shared_occasion();
revoke all on function private.notify_shared_occasion() from public,anon,authenticated;

alter publication supabase_realtime add table public.occasion_plans;
alter publication supabase_realtime add table public.occasion_plan_steps;
