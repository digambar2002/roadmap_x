-- RoadmapX sync backend
-- Paste into the Supabase SQL editor (Dashboard → SQL Editor → New query).
-- Safe to re-run: every statement is idempotent.

-- ─────────────────────────────────────────────────────────────
-- profiles — one row per account, and the premium switch
-- ─────────────────────────────────────────────────────────────
-- is_premium is flipped by hand from the Supabase table editor. It is
-- deliberately NOT user-writable: the RLS policies below grant the account
-- holder read access only, so a patched client cannot promote itself.

create table if not exists public.profiles (
  id            uuid primary key references auth.users on delete cascade,
  email         text,
  is_premium    boolean     not null default false,
  premium_until timestamptz,                    -- null = no expiry
  note          text,                           -- free-text: who they are, what they paid
  created_at    timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles
  for select using (auth.uid() = id);

-- No insert/update/delete policies: only the service role (the dashboard, and
-- the trigger below, which is security definer) can write this table.

-- Create the profile row automatically on signup so there is always something
-- to flip when the user asks for premium.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill for accounts that already existed when this schema was applied.
-- Without a profiles row there is nothing to flip, so such a user could never
-- be activated no matter what they paid.
insert into public.profiles (id, email)
select id, email from auth.users
on conflict (id) do nothing;

-- ─────────────────────────────────────────────────────────────
-- is_premium() — the single gate the sync table is guarded by
-- ─────────────────────────────────────────────────────────────
create or replace function public.is_premium(uid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select coalesce(
    (select p.is_premium
            and (p.premium_until is null or p.premium_until > now())
     from public.profiles p
     where p.id = uid),
    false);
$$;

-- ─────────────────────────────────────────────────────────────
-- records — every synced row, from every collection
-- ─────────────────────────────────────────────────────────────
-- One generic table rather than one table per model. The client already
-- serializes each row to JSON for file backup, so reusing that shape means
-- adding a field to a Dart model needs no migration here, one RLS policy
-- covers everything, and one realtime subscription carries all collections.
--
--   updated_at        — the device's clock. The merge key (last-writer-wins).
--   server_updated_at — Postgres's clock, set by trigger. The *pull cursor*,
--                       so a device with a skewed clock cannot make its rows
--                       invisible to peers by dating them in the past.

create table if not exists public.records (
  user_id           uuid        not null references auth.users on delete cascade,
  collection        text        not null,
  uid               text        not null,
  data              jsonb       not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, collection, uid)
);

create index if not exists records_pull_idx
  on public.records (user_id, server_updated_at);

create or replace function public.touch_server_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.server_updated_at := now();
  return new;
end $$;

drop trigger if exists records_touch on public.records;
create trigger records_touch
  before insert or update on public.records
  for each row execute function public.touch_server_updated_at();

alter table public.records enable row level security;

-- Every policy carries the premium check as well as the ownership check, so
-- lapsing a subscription stops sync server-side rather than relying on the
-- client to disable itself.
drop policy if exists "own records read" on public.records;
create policy "own records read" on public.records
  for select using (auth.uid() = user_id and public.is_premium(auth.uid()));

drop policy if exists "own records insert" on public.records;
create policy "own records insert" on public.records
  for insert with check (auth.uid() = user_id and public.is_premium(auth.uid()));

drop policy if exists "own records update" on public.records;
create policy "own records update" on public.records
  for update using (auth.uid() = user_id and public.is_premium(auth.uid()))
         with check (auth.uid() = user_id and public.is_premium(auth.uid()));

-- No delete policy. Rows are tombstoned (deleted_at), never removed — a peer
-- that has not synced yet still needs to learn that the row went away.

-- ─────────────────────────────────────────────────────────────
-- Realtime
-- ─────────────────────────────────────────────────────────────
-- Broadcasts row changes to subscribed clients. RLS is enforced on the
-- realtime stream too, so each device only receives its own rows.
--
-- Postgres has no "add table if not exists" for publications, and a plain
-- ALTER errors once the table is already a member. Since this file is applied
-- as one implicit transaction, that error would roll back everything else in
-- it — so the membership is checked first.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'records'
  ) then
    alter publication supabase_realtime add table public.records;
  end if;
end $$;

-- Needed for realtime to report which row changed on an update.
alter table public.records replica identity full;
