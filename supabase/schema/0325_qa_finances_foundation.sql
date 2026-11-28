-- 0325 (28 Nov 2026, owner decisions D110 onwards): OneSpace Finances, iteration 1.
-- QA first (ugwrpeduzyzrujkizqfo); Production only at go-live with the owner.
--
-- Rules carried by the database:
-- * Every finance record has one owner, its creator (A3), and lives in the
--   owner's personal storage (private_space_id = created_by, ADR-2026-11-20, A5).
-- * Private by default (A4): only the owner reads or writes. A partner can read
--   an item only through an accepted, unrevoked permission row while they are
--   still the owner's current partner (sharing screens come in iteration 3).
-- * Confirmed records are immutable (A9): payments, combined payments and
--   corrections can be inserted, never updated or deleted by a person.
--   A correction is a new row.
-- * Money is numeric(15,4) — never floating point. The app reads it as text.
-- * Shapes for later iterations exist now (A21): categories, providers,
--   per-item permissions with share roles, payment links, paused items.

-- ---------------------------------------------------------------- providers
create table if not exists public.fin_providers (
  id uuid primary key default gen_random_uuid(),
  private_space_id uuid not null references public.user_private_spaces(owner_id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fin_providers_owner check (private_space_id = created_by)
);
create index if not exists fin_providers_owner_idx on public.fin_providers(private_space_id);

-- ---------------------------------------------------------------- categories
-- built_in_key is set for the starter categories the app offers ('housing', …),
-- so their names can be shown in the app language; custom ones have a name only.
create table if not exists public.fin_categories (
  id uuid primary key default gen_random_uuid(),
  private_space_id uuid not null references public.user_private_spaces(owner_id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  built_in_key text check (built_in_key is null or built_in_key ~ '^[a-z_]{2,30}$'),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fin_categories_owner check (private_space_id = created_by)
);
create index if not exists fin_categories_owner_idx on public.fin_categories(private_space_id);
create unique index if not exists fin_categories_builtin_once
  on public.fin_categories(private_space_id, built_in_key) where built_in_key is not null;

-- ---------------------------------------------------------------- items
-- One table for bills and installment plans: the same schedule and amount
-- rules apply to both (lib/features/finances/fin_plan.dart).
create table if not exists public.fin_items (
  id uuid primary key default gen_random_uuid(),
  private_space_id uuid not null references public.user_private_spaces(owner_id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('bill', 'installment')),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  notes text not null default '' check (char_length(notes) <= 2000),
  category_id uuid references public.fin_categories(id) on delete set null,
  provider_id uuid references public.fin_providers(id) on delete set null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount numeric(15,4) not null check (amount >= 0),
  amount_kind text not null default 'fixed' check (amount_kind in ('fixed', 'estimated', 'budget')),
  first_due_on date not null,
  frequency text not null default 'monthly'
    check (frequency in ('once', 'weekly', 'biweekly', 'semimonthly', 'monthly', 'every_months')),
  interval_months smallint not null default 1 check (interval_months between 1 and 120),
  due_day smallint not null check (due_day between 1 and 31),
  second_due_day smallint check (second_due_day between 1 and 31),
  change_kind text not null default 'none' check (change_kind in ('none', 'amount', 'percent')),
  change_amount numeric(15,4) not null default 0,
  change_percent numeric(9,4) not null default 0 check (change_percent > -100 and change_percent <= 1000),
  change_every_months smallint not null default 12 check (change_every_months between 1 and 120),
  balloon_amount numeric(15,4) check (balloon_amount is null or balloon_amount >= 0),
  end_kind text not null default 'never' check (end_kind in ('never', 'date', 'count')),
  end_on date,
  payment_count integer check (payment_count is null or payment_count between 1 and 2400),
  paid_before_count integer not null default 0 check (paid_before_count >= 0),
  auto_paid boolean not null default false,
  reminder_days_before smallint not null default 2 check (reminder_days_before between 0 and 60),
  reminders_on boolean not null default true,
  payment_link text check (payment_link is null or (char_length(payment_link) <= 500 and payment_link ~* '^https?://')),
  paused_on date,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fin_items_owner check (private_space_id = created_by),
  constraint fin_items_end_shape check (
    (end_kind = 'never') or
    (end_kind = 'date' and end_on is not null and end_on >= first_due_on) or
    (end_kind = 'count' and payment_count is not null)),
  constraint fin_items_paid_before_fits check (payment_count is null or paid_before_count <= payment_count),
  constraint fin_items_installment_ends check (kind <> 'installment' or end_kind <> 'never' or frequency = 'once'),
  constraint fin_items_semimonthly_days check (frequency <> 'semimonthly' or second_due_day is not null)
);
create index if not exists fin_items_owner_idx on public.fin_items(private_space_id) where archived_at is null;
create index if not exists fin_items_provider_idx on public.fin_items(provider_id) where provider_id is not null;
create index if not exists fin_items_category_idx on public.fin_items(category_id) where category_id is not null;

-- ---------------------------------------------------------------- combined payments (A17)
create table if not exists public.fin_combined_payments (
  id uuid primary key default gen_random_uuid(),
  private_space_id uuid not null references public.user_private_spaces(owner_id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  provider_id uuid references public.fin_providers(id) on delete set null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  total_amount numeric(15,4) not null check (total_amount > 0),
  paid_on date not null,
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  constraint fin_combined_owner check (private_space_id = created_by)
);
create index if not exists fin_combined_owner_idx on public.fin_combined_payments(private_space_id);

-- ---------------------------------------------------------------- confirmed payments (A8, A9)
-- One row per confirmation of one expected payment (occurrence_no is 1-based).
-- expected_amount and due_on are a snapshot, so later setup changes never
-- alter a confirmed record. Several rows for one payment are allowed (a
-- partial payment followed by the rest).
create table if not exists public.fin_payments (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.fin_items(id) on delete cascade,
  private_space_id uuid not null references public.user_private_spaces(owner_id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  occurrence_no integer not null check (occurrence_no between 1 and 2400),
  due_on date not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  expected_amount numeric(15,4) not null check (expected_amount >= 0),
  status text not null check (status in ('done', 'not_done', 'partial')),
  actual_amount numeric(15,4) check (actual_amount is null or actual_amount >= 0),
  paid_on date,
  combined_id uuid references public.fin_combined_payments(id) on delete cascade,
  note text not null default '' check (char_length(note) <= 500),
  created_at timestamptz not null default now(),
  constraint fin_payments_owner check (private_space_id = created_by),
  constraint fin_payments_partial_amount check (status <> 'partial' or actual_amount is not null),
  constraint fin_payments_not_done_amount check (status <> 'not_done' or actual_amount is null)
);
create index if not exists fin_payments_item_idx on public.fin_payments(item_id, occurrence_no);
create index if not exists fin_payments_owner_idx on public.fin_payments(private_space_id);
create index if not exists fin_payments_combined_idx on public.fin_payments(combined_id) where combined_id is not null;

-- Corrections (A9): a new entry that replaces the status and amount of one
-- confirmed payment; the original stays as it was.
create table if not exists public.fin_payment_corrections (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.fin_payments(id) on delete cascade,
  private_space_id uuid not null references public.user_private_spaces(owner_id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  status text not null check (status in ('done', 'not_done', 'partial')),
  actual_amount numeric(15,4) check (actual_amount is null or actual_amount >= 0),
  reason text not null default '' check (char_length(reason) <= 500),
  created_at timestamptz not null default now(),
  constraint fin_corrections_owner check (private_space_id = created_by),
  constraint fin_corrections_partial_amount check (status <> 'partial' or actual_amount is not null)
);
create index if not exists fin_corrections_payment_idx on public.fin_payment_corrections(payment_id, created_at);
create index if not exists fin_corrections_owner_idx on public.fin_payment_corrections(private_space_id);

-- ---------------------------------------------------------------- permissions (A4; used from iteration 3)
-- share_role: 'view' (partner sees it), 'split' (partner owns a share and its
-- payment history, A3), 'joint' (jointly funded). A partner must accept before
-- it counts in their plan. Revoked rows are kept (separation keeps a basic
-- record, A5).
create table if not exists public.fin_item_permissions (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.fin_items(id) on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  grantee_id uuid not null references auth.users(id) on delete cascade,
  share_role text not null default 'view' check (share_role in ('view', 'split', 'joint')),
  share_amount numeric(15,4) check (share_amount is null or share_amount >= 0),
  share_percent numeric(7,4) check (share_percent is null or (share_percent > 0 and share_percent <= 100)),
  can_confirm boolean not null default false,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint fin_permissions_not_self check (owner_id <> grantee_id)
);
create unique index if not exists fin_permissions_one_open
  on public.fin_item_permissions(item_id, grantee_id) where revoked_at is null;
create index if not exists fin_permissions_grantee_idx on public.fin_item_permissions(grantee_id) where revoked_at is null;

-- ---------------------------------------------------------------- access helpers
create or replace function private.fin_owns_item(p_item uuid)
returns boolean language sql stable security definer set search_path to '' as $f$
  select exists (select 1 from public.fin_items i
    where i.id = p_item and i.created_by = (select auth.uid()) and i.private_space_id = (select auth.uid()));
$f$;

-- A partner reads an item only with an accepted, unrevoked permission and
-- only while the owner is still their current partner.
create or replace function private.fin_partner_can_view(p_item uuid)
returns boolean language sql stable security definer set search_path to '' as $f$
  select exists (select 1 from public.fin_item_permissions p
    join public.fin_items i on i.id = p.item_id
    where p.item_id = p_item and p.grantee_id = (select auth.uid())
      and p.owner_id = i.created_by
      and p.accepted_at is not null and p.revoked_at is null
      and private.qa_is_current_partner(i.created_by));
$f$;

revoke all on function private.fin_owns_item(uuid) from public, anon;
revoke all on function private.fin_partner_can_view(uuid) from public, anon;
grant execute on function private.fin_owns_item(uuid) to authenticated;
grant execute on function private.fin_partner_can_view(uuid) to authenticated;

-- ---------------------------------------------------------------- RLS
alter table public.fin_providers enable row level security;
alter table public.fin_categories enable row level security;
alter table public.fin_items enable row level security;
alter table public.fin_combined_payments enable row level security;
alter table public.fin_payments enable row level security;
alter table public.fin_payment_corrections enable row level security;
alter table public.fin_item_permissions enable row level security;

-- Providers and categories: owner only.
drop policy if exists fin_providers_owner on public.fin_providers;
create policy fin_providers_owner on public.fin_providers for all to authenticated
  using (private_space_id = (select auth.uid()) and created_by = (select auth.uid()))
  with check (private_space_id = (select auth.uid()) and created_by = (select auth.uid()));
drop policy if exists fin_categories_owner on public.fin_categories;
create policy fin_categories_owner on public.fin_categories for all to authenticated
  using (private_space_id = (select auth.uid()) and created_by = (select auth.uid()))
  with check (private_space_id = (select auth.uid()) and created_by = (select auth.uid()));

-- Items: the owner does everything (policies below, after the triggers);
-- a permitted partner may read.
drop policy if exists fin_items_partner_read on public.fin_items;
create policy fin_items_partner_read on public.fin_items for select to authenticated
  using (private.fin_partner_can_view(id));

-- Payments: insert and read only; no update or delete for people (A9).
drop policy if exists fin_payments_owner_read on public.fin_payments;
create policy fin_payments_owner_read on public.fin_payments for select to authenticated
  using (private_space_id = (select auth.uid()) and created_by = (select auth.uid()));
drop policy if exists fin_payments_partner_read on public.fin_payments;
create policy fin_payments_partner_read on public.fin_payments for select to authenticated
  using (private.fin_partner_can_view(item_id));
drop policy if exists fin_payments_owner_insert on public.fin_payments;
create policy fin_payments_owner_insert on public.fin_payments for insert to authenticated
  with check (private_space_id = (select auth.uid()) and created_by = (select auth.uid())
    and private.fin_owns_item(item_id)
    and (combined_id is null or exists (select 1 from public.fin_combined_payments c
      where c.id = combined_id and c.created_by = (select auth.uid()))));

drop policy if exists fin_corrections_owner_read on public.fin_payment_corrections;
create policy fin_corrections_owner_read on public.fin_payment_corrections for select to authenticated
  using (private_space_id = (select auth.uid()) and created_by = (select auth.uid()));
drop policy if exists fin_corrections_partner_read on public.fin_payment_corrections;
create policy fin_corrections_partner_read on public.fin_payment_corrections for select to authenticated
  using (exists (select 1 from public.fin_payments p where p.id = payment_id and private.fin_partner_can_view(p.item_id)));
drop policy if exists fin_corrections_owner_insert on public.fin_payment_corrections;
create policy fin_corrections_owner_insert on public.fin_payment_corrections for insert to authenticated
  with check (private_space_id = (select auth.uid()) and created_by = (select auth.uid())
    and exists (select 1 from public.fin_payments p where p.id = payment_id and p.created_by = (select auth.uid())));

drop policy if exists fin_combined_owner_read on public.fin_combined_payments;
create policy fin_combined_owner_read on public.fin_combined_payments for select to authenticated
  using (private_space_id = (select auth.uid()) and created_by = (select auth.uid()));

-- Permissions: the owner grants and revokes for their current partner; the
-- grantee sees their own rows and accepts through fin_answer_permission().
drop policy if exists fin_permissions_owner on public.fin_item_permissions;
create policy fin_permissions_owner on public.fin_item_permissions for select to authenticated
  using (owner_id = (select auth.uid()) or grantee_id = (select auth.uid()));
drop policy if exists fin_permissions_owner_insert on public.fin_item_permissions;
create policy fin_permissions_owner_insert on public.fin_item_permissions for insert to authenticated
  with check (owner_id = (select auth.uid()) and private.fin_owns_item(item_id)
    and private.qa_is_current_partner(grantee_id) and accepted_at is null and revoked_at is null);
drop policy if exists fin_permissions_owner_update on public.fin_item_permissions;
create policy fin_permissions_owner_update on public.fin_item_permissions for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

grant select, insert, update, delete on public.fin_providers to authenticated;
grant select, insert, update, delete on public.fin_categories to authenticated;
grant select, insert, update, delete on public.fin_items to authenticated;
grant select, insert on public.fin_payments to authenticated;
grant select, insert on public.fin_payment_corrections to authenticated;
grant select on public.fin_combined_payments to authenticated;
grant select, insert, update on public.fin_item_permissions to authenticated;
revoke all on public.fin_providers, public.fin_categories, public.fin_items, public.fin_payments,
  public.fin_payment_corrections, public.fin_combined_payments, public.fin_item_permissions from anon;

-- ---------------------------------------------------------------- triggers
-- Owner and scope never change; updated_at is kept by the server.
create or replace function private.fin_keep_owner()
returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  new.private_space_id := old.private_space_id;
  new.created_by := old.created_by;
  new.created_at := old.created_at;
  new.updated_at := now();
  if tg_table_name = 'fin_items' then
    new.kind := old.kind;
  end if;
  return new;
end $f$;
revoke all on function private.fin_keep_owner() from public, anon, authenticated;

drop trigger if exists fin_providers_keep_owner on public.fin_providers;
create trigger fin_providers_keep_owner before update on public.fin_providers
  for each row execute function private.fin_keep_owner();
drop trigger if exists fin_categories_keep_owner on public.fin_categories;
create trigger fin_categories_keep_owner before update on public.fin_categories
  for each row execute function private.fin_keep_owner();
drop trigger if exists fin_items_keep_owner on public.fin_items;
create trigger fin_items_keep_owner before update on public.fin_items
  for each row execute function private.fin_keep_owner();

-- A permission row: the owner may only revoke or change the share; acceptance
-- belongs to the grantee (through the function below).
create or replace function private.fin_permission_guard()
returns trigger language plpgsql security definer set search_path to '' as $f$
begin
  if current_user in ('authenticated', 'anon') then
    new.item_id := old.item_id; new.owner_id := old.owner_id; new.grantee_id := old.grantee_id;
    new.created_at := old.created_at; new.accepted_at := old.accepted_at;
    if old.revoked_at is not null then new.revoked_at := old.revoked_at; end if;
  end if;
  return new;
end $f$;
revoke all on function private.fin_permission_guard() from public, anon, authenticated;
drop trigger if exists fin_permission_guard on public.fin_item_permissions;
create trigger fin_permission_guard before update on public.fin_item_permissions
  for each row execute function private.fin_permission_guard();

-- A payment's currency is the item's; an expected payment cannot be later than
-- the item allows.
create or replace function private.fin_payment_check()
returns trigger language plpgsql security definer set search_path to '' as $f$
declare it record;
begin
  select currency, payment_count into it from public.fin_items where id = new.item_id;
  if it.currency is distinct from new.currency then
    raise exception 'Payment currency must match the item' using errcode = '23514';
  end if;
  if it.payment_count is not null and new.occurrence_no > it.payment_count then
    raise exception 'This plan has no payment number %', new.occurrence_no using errcode = '23514';
  end if;
  return new;
end $f$;
revoke all on function private.fin_payment_check() from public, anon, authenticated;
drop trigger if exists fin_payment_check on public.fin_payments;
create trigger fin_payment_check before insert on public.fin_payments
  for each row execute function private.fin_payment_check();

-- No content changes while the account is being finalized for deletion
-- (same fence as every other content table).
do $fence$
declare t text;
begin
  foreach t in array array['fin_providers','fin_categories','fin_items','fin_combined_payments',
    'fin_payments','fin_payment_corrections','fin_item_permissions'] loop
    execute format('drop trigger if exists qa_finalization_write_fence on public.%I', t);
    execute format('create trigger qa_finalization_write_fence before insert or update or delete on public.%I
      for each row execute function private.qa_reject_finalizing_user_writes()', t);
  end loop;
end $fence$;

-- An item with confirmed payments can be archived but not deleted by a person,
-- so confirmed history is never lost by accident (A9).
drop policy if exists fin_items_owner on public.fin_items;
drop policy if exists fin_items_owner_read on public.fin_items;
drop policy if exists fin_items_owner_insert on public.fin_items;
drop policy if exists fin_items_owner_update on public.fin_items;
drop policy if exists fin_items_owner_delete on public.fin_items;
create policy fin_items_owner_read on public.fin_items for select to authenticated
  using (private_space_id = (select auth.uid()) and created_by = (select auth.uid()));
create policy fin_items_owner_insert on public.fin_items for insert to authenticated
  with check (private_space_id = (select auth.uid()) and created_by = (select auth.uid())
    and (category_id is null or exists (select 1 from public.fin_categories c
      where c.id = category_id and c.created_by = (select auth.uid())))
    and (provider_id is null or exists (select 1 from public.fin_providers p
      where p.id = provider_id and p.created_by = (select auth.uid()))));
create policy fin_items_owner_update on public.fin_items for update to authenticated
  using (private_space_id = (select auth.uid()) and created_by = (select auth.uid()))
  with check (private_space_id = (select auth.uid()) and created_by = (select auth.uid())
    and (category_id is null or exists (select 1 from public.fin_categories c
      where c.id = category_id and c.created_by = (select auth.uid())))
    and (provider_id is null or exists (select 1 from public.fin_providers p
      where p.id = provider_id and p.created_by = (select auth.uid()))));
create policy fin_items_owner_delete on public.fin_items for delete to authenticated
  using (private_space_id = (select auth.uid()) and created_by = (select auth.uid())
    and not exists (select 1 from public.fin_payments p where p.item_id = fin_items.id));

-- ---------------------------------------------------------------- functions
-- A combined payment split by the owner across several plans (A17): the parts
-- must add up to the total exactly; everything is saved together or not at all.
-- p_parts: [{"item_id": uuid, "occurrence_no": int, "due_on": date,
--            "expected_amount": "123.45", "amount": "100.00"}, …]
create or replace function public.fin_record_combined_payment(
  p_currency text, p_total numeric, p_paid_on date, p_parts jsonb,
  p_provider uuid default null, p_note text default '')
returns uuid language plpgsql security definer set search_path to '' as $f$
declare
  me uuid := auth.uid();
  combined uuid;
  part jsonb;
  sum_parts numeric(15,4) := 0;
  amt numeric(15,4);
  expected numeric(15,4);
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if private.qa_is_account_in_finalization(me) then
    raise exception 'Account finalization has started; content changes are disabled' using errcode = '42501';
  end if;
  if p_total is null or p_total <= 0 then raise exception 'The total must be more than zero'; end if;
  if jsonb_typeof(p_parts) <> 'array' or jsonb_array_length(p_parts) = 0 then
    raise exception 'Choose at least one plan';
  end if;
  if p_provider is not null and not exists (select 1 from public.fin_providers
      where id = p_provider and created_by = me) then
    raise exception 'Unknown provider' using errcode = '42501';
  end if;
  for part in select * from jsonb_array_elements(p_parts) loop
    amt := (part->>'amount')::numeric(15,4);
    if amt is null or amt <= 0 then raise exception 'Each part must be more than zero'; end if;
    if not exists (select 1 from public.fin_items i where i.id = (part->>'item_id')::uuid
        and i.created_by = me and i.private_space_id = me and i.currency = upper(p_currency)) then
      raise exception 'A plan is not yours or uses another currency' using errcode = '42501';
    end if;
    sum_parts := sum_parts + amt;
  end loop;
  if sum_parts <> p_total then raise exception 'The parts must add up to the total'; end if;
  if (select count(distinct (e->>'item_id') || '#' || (e->>'occurrence_no')) from jsonb_array_elements(p_parts) e)
     <> jsonb_array_length(p_parts) then
    raise exception 'A payment is listed twice';
  end if;

  insert into public.fin_combined_payments(private_space_id, created_by, provider_id, currency, total_amount, paid_on, note)
    values (me, me, p_provider, upper(p_currency), p_total, p_paid_on, coalesce(left(p_note, 500), ''))
    returning id into combined;
  for part in select * from jsonb_array_elements(p_parts) loop
    amt := (part->>'amount')::numeric(15,4);
    expected := (part->>'expected_amount')::numeric(15,4);
    insert into public.fin_payments(item_id, private_space_id, created_by, occurrence_no, due_on, currency,
        expected_amount, status, actual_amount, paid_on, combined_id)
      values ((part->>'item_id')::uuid, me, me, (part->>'occurrence_no')::int, (part->>'due_on')::date,
        upper(p_currency), expected,
        case when amt >= coalesce(part->>'remaining', part->>'expected_amount')::numeric then 'done' else 'partial' end,
        amt, p_paid_on, combined);
  end loop;
  return combined;
end $f$;
revoke all on function public.fin_record_combined_payment(text, numeric, date, jsonb, uuid, text) from public, anon;
grant execute on function public.fin_record_combined_payment(text, numeric, date, jsonb, uuid, text) to authenticated;

-- The partner accepts (or declines) a payment responsibility (A4, iteration 3).
create or replace function public.fin_answer_permission(p_permission uuid, p_accept boolean)
returns void language plpgsql security definer set search_path to '' as $f$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  update public.fin_item_permissions p
     set accepted_at = case when p_accept then now() else null end,
         revoked_at = case when p_accept then null else now() end
   where p.id = p_permission and p.grantee_id = me and p.revoked_at is null
     and private.qa_is_current_partner(p.owner_id);
  if not found then raise exception 'This request is no longer open' using errcode = '42501'; end if;
end $f$;
revoke all on function public.fin_answer_permission(uuid, boolean) from public, anon;
grant execute on function public.fin_answer_permission(uuid, boolean) to authenticated;

-- ---------------------------------------------------------------- history (record_action_history)
alter table public.record_action_history drop constraint if exists record_action_history_record_kind_check;
alter table public.record_action_history add constraint record_action_history_record_kind_check
  check (record_kind = any (array['note','task','goal','memory','event','reminder','occasion','experience',
    'trip','contact','checkin','checkin_request','experience_comment','sort_item','activity','fin_item']));

-- Who/what/when only: never amounts, titles or notes.
create or replace function private.fin_capture_action()
returns trigger language plpgsql security definer set search_path to '' as $f$
declare before jsonb; after jsonb; fields text[]; action_name text;
begin
  after := to_jsonb(new);
  if tg_op = 'INSERT' then
    action_name := 'created'; fields := '{}';
  else
    before := to_jsonb(old);
    select coalesce(array_agg(key order by key), '{}'::text[]) into fields
      from jsonb_object_keys(after) as k(key)
      where (after->key) is distinct from (before->key) and key not in ('updated_at', 'created_at');
    if cardinality(fields) = 0 then return new; end if;
    action_name := case
      when before->>'archived_at' is null and after->>'archived_at' is not null then 'archived'
      when before->>'archived_at' is not null and after->>'archived_at' is null then 'restored'
      else 'edited' end;
  end if;
  insert into public.record_action_history(space_id, private_space_id, record_kind, record_id, actor_id, action, changed_fields)
    values (null, (after->>'private_space_id')::uuid, 'fin_item', (after->>'id')::uuid, auth.uid(), action_name, fields);
  return new;
end $f$;
revoke all on function private.fin_capture_action() from public, anon, authenticated;
drop trigger if exists fin_item_actions on public.fin_items;
create trigger fin_item_actions after insert or update on public.fin_items
  for each row execute function private.fin_capture_action();

drop policy if exists "QA owner reads finance item history" on public.record_action_history;
create policy "QA owner reads finance item history" on public.record_action_history for select to authenticated
  using (record_kind = 'fin_item' and private_space_id = (select auth.uid())
    and exists (select 1 from public.fin_items i where i.id = record_action_history.record_id
      and i.private_space_id = (select auth.uid()) and i.created_by = (select auth.uid())));
