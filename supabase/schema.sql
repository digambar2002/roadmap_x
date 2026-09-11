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

-- ─────────────────────────────────────────────────────────────
-- admins — who may activate other people's accounts
-- ─────────────────────────────────────────────────────────────
-- Membership is granted by hand from the table editor, exactly like premium.
-- There is deliberately no way to add yourself from the client.

create table if not exists public.admins (
  user_id    uuid primary key references auth.users on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;

drop policy if exists "read own admin row" on public.admins;
create policy "read own admin row" on public.admins
  for select using (auth.uid() = user_id);

create or replace function public.is_admin(uid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (select 1 from public.admins a where a.user_id = uid);
$$;

-- Admins can see and edit every profile. Ordinary users keep their existing
-- read-own-row policy and still cannot write their own premium flag.
drop policy if exists "admins read all profiles" on public.profiles;
create policy "admins read all profiles" on public.profiles
  for select using (public.is_admin(auth.uid()));

drop policy if exists "admins update profiles" on public.profiles;
create policy "admins update profiles" on public.profiles
  for update using (public.is_admin(auth.uid()))
         with check (public.is_admin(auth.uid()));

-- ─────────────────────────────────────────────────────────────
-- grant_premium() — the one operation the admin screen performs
-- ─────────────────────────────────────────────────────────────
-- A function rather than a bare UPDATE so the *extension* rule lives on the
-- server: granting a month to someone with two weeks left gives them six
-- weeks, not four. Doing that arithmetic in the client would let two admins
-- racing each other silently shorten a subscription.
--
-- months = 0 revokes. A null premium_until means no expiry.

create or replace function public.grant_premium(
  target_email text,
  months int
)
returns table (email text, is_premium boolean, premium_until timestamptz)
language plpgsql
security definer set search_path = public
as $$
declare
  target       uuid;
  cur_premium  boolean;
  cur_until    timestamptz;
  base         timestamptz;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'not authorised';
  end if;

  select p.id, p.is_premium, p.premium_until
    into target, cur_premium, cur_until
  from public.profiles p
  where p.email = target_email;

  if target is null then
    raise exception 'no account for %', target_email;
  end if;

  if months <= 0 then
    -- premium_until is left as it stands: it is a record of when access
    -- lapsed, and the admin screen shows it as "Expired <date>".
    update public.profiles p set is_premium = false where p.id = target;

  elsif cur_premium and cur_until is null then
    -- Already unlimited. Stamping an expiry here would silently downgrade a
    -- lifetime account into a fixed term.
    update public.profiles p set is_premium = true where p.id = target;

  else
    -- Extend only from time the account still actually holds. A period that
    -- was revoked, or that has already elapsed, must not be carried forward:
    -- granting one month after a revoke has to mean one month from today.
    base := case
              when cur_premium and cur_until is not null and cur_until > now()
                then cur_until
              else now()
            end;

    update public.profiles p
      set is_premium = true,
          premium_until = base + make_interval(months => months)
      where p.id = target;
  end if;

  return query
    select p.email, p.is_premium, p.premium_until
    from public.profiles p where p.id = target;
end $$;

revoke all on function public.grant_premium(text, int) from public;
grant execute on function public.grant_premium(text, int) to authenticated;
