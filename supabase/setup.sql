-- =====================================================================
--  Attendance system — cloud sync setup for Supabase
--  Run the whole file once in: Dashboard → SQL Editor → New query → Run.
--  Safe to run again (it updates what exists and keeps your data).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

-- Who may use the app. Only emails in this table can read or change data,
-- even if someone else manages to create an account.
--   admin  / editor : read and change data
--   viewer          : read only
create table if not exists public.app_members (
  email        text primary key check (email = lower(btrim(email))),
  display_name text,
  role         text not null default 'editor' check (role in ('admin', 'editor', 'viewer')),
  created_at   timestamptz not null default now()
);

-- All app data, one row per item (shift, employee, attendance day, holiday, settings).
-- A deleted item stays as a row with deleted = true so other devices learn about the delete.
create table if not exists public.att_docs (
  collection text not null check (collection in ('shifts', 'employees', 'records', 'holidays', 'settings')),
  id         text not null check (length(id) between 1 and 200),
  data       jsonb,
  deleted    boolean not null default false,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by text,
  primary key (collection, id)
);
create index if not exists att_docs_updated_idx on public.att_docs (updated_at, collection, id);

-- Edits made directly in the dashboard also get a new timestamp, so devices pick them up.
create or replace function public.att_touch() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;
drop trigger if exists att_docs_touch on public.att_docs;
create trigger att_docs_touch before update on public.att_docs
  for each row execute function public.att_touch();

-- ---------------------------------------------------------------------
-- 2. Access rules (Row Level Security)
-- ---------------------------------------------------------------------
alter table public.app_members enable row level security;
alter table public.att_docs    enable row level security;

-- The signed-in user's role, or NULL if their email is not in app_members.
-- Only accounts with a CONFIRMED email get a role, so nobody can sign up with a member's
-- email before that person creates their own account.
create or replace function public.att_my_role() returns text
language sql stable security definer set search_path = '' as $$
  select m.role
  from public.app_members m
  join auth.users u on u.id = (select auth.uid())
  where u.email_confirmed_at is not null
    and lower(u.email) = m.email
$$;

drop policy if exists "members read own row" on public.app_members;
create policy "members read own row" on public.app_members
  for select to authenticated
  using (email = lower(coalesce((select auth.jwt()) ->> 'email', '')));

drop policy if exists "members read docs" on public.att_docs;
create policy "members read docs" on public.att_docs
  for select to authenticated
  using ((select public.att_my_role()) is not null);

-- No insert/update/delete policies on purpose: the app writes only through att_sync_push below,
-- which checks the role. Anonymous visitors get nothing.
revoke all on public.att_docs, public.app_members from anon;
revoke insert, update, delete, truncate on public.att_docs, public.app_members from authenticated;
grant select on public.att_docs, public.app_members to authenticated;

-- ---------------------------------------------------------------------
-- 3. Sync functions used by the app
-- ---------------------------------------------------------------------

-- Save a batch of items: [{collection, id, data, deleted}, ...]. The newest save wins.
create or replace function public.att_sync_push(p_docs jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_role  text := public.att_my_role();
  v_email text := lower(coalesce((select auth.jwt()) ->> 'email', ''));
  v_doc   jsonb;
  v_del   boolean;
  v_n     int := 0;
begin
  if v_role is null then
    raise exception 'not a member of this app' using errcode = '42501';
  end if;
  if v_role = 'viewer' then
    raise exception 'read-only member' using errcode = '42501';
  end if;
  if jsonb_typeof(p_docs) is distinct from 'array' then
    raise exception 'p_docs must be a JSON array';
  end if;
  if jsonb_array_length(p_docs) > 1000 then
    raise exception 'at most 1000 items per call';
  end if;

  for v_doc in select value from jsonb_array_elements(p_docs) loop
    v_del := coalesce((v_doc ->> 'deleted')::boolean, false);
    insert into public.att_docs as d (collection, id, data, deleted, updated_at, updated_by)
    values (v_doc ->> 'collection', v_doc ->> 'id',
            case when v_del then null else v_doc -> 'data' end,
            v_del, clock_timestamp(), v_email)
    on conflict (collection, id) do update
      set data = excluded.data, deleted = excluded.deleted,
          updated_at = excluded.updated_at, updated_by = excluded.updated_by;
    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('saved', v_n, 'server_time', clock_timestamp());
end $$;

-- Read items changed after a point, in pages (keyset paging: time, then collection, then id).
-- Runs with the caller's own rights: the row-level rule above means non-members get no rows.
create or replace function public.att_sync_pull(
  p_since            timestamptz default '-infinity',
  p_after_collection text        default '',
  p_after_id         text        default '',
  p_limit            int         default 1000)
returns table (collection text, id text, data jsonb, deleted boolean, updated_at timestamptz, updated_by text)
language sql stable security invoker set search_path = '' as $$
  select d.collection, d.id, d.data, d.deleted, d.updated_at, d.updated_by
  from public.att_docs d
  where (d.updated_at, d.collection, d.id) > (p_since, p_after_collection, p_after_id)
  order by d.updated_at, d.collection, d.id
  limit least(greatest(p_limit, 1), 1000)
$$;

revoke all on function public.att_my_role()                          from public, anon;
revoke all on function public.att_sync_push(jsonb)                    from public, anon;
revoke all on function public.att_sync_pull(timestamptz, text, text, int) from public, anon;
grant execute on function public.att_my_role()                          to authenticated;
grant execute on function public.att_sync_push(jsonb)                    to authenticated;
grant execute on function public.att_sync_pull(timestamptz, text, text, int) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Live updates between devices (Supabase Realtime)
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'att_docs') then
    alter publication supabase_realtime add table public.att_docs;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5. Add yourself as the first admin
--    Replace the email below with the email you will log in with, then run the file.
--    Add more people later the same way (role: 'admin', 'editor' or 'viewer').
-- ---------------------------------------------------------------------
insert into public.app_members (email, display_name, role)
values (lower('YOUR-EMAIL@example.com'), 'Admin', 'admin')
on conflict (email) do update set role = excluded.role;
