-- User roles (administrador / usuario)
--
-- Authorization so far has been "every row belongs to exactly one user": every
-- policy is `user_id = auth.uid()`, and the only privileged actor is the
-- server-side `service_role`. This adds a real per-user role that travels
-- inside the JWT, so the database can distinguish an administrator from an
-- ordinary user without an extra query on every request.
--
-- Design notes:
--   * The role lives in its own table, not in `app_state`, because `app_state`
--     is client-writable and a role must never be.
--   * The role reaches the token through Supabase's custom access token hook.
--     The hook must additionally be ENABLED in the dashboard
--     (Authentication -> Hooks -> Customize Access Token) or it silently does
--     nothing. See Docs/Roles.md.
--   * Nothing here grants an administrator access to note CONTENT. The admin
--     surface is an aggregate overview (counts and timestamps). Widening it is
--     a deliberate decision, not a side effect of being an admin.

-- MARK: - Role type and table

do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_user_role') then
    create type public.app_user_role as enum ('user', 'admin');
  end if;
end
$$;

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role public.app_user_role not null default 'user',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.user_roles enable row level security;

-- MARK: - Claim helpers
--
-- Both read the role from the request JWT rather than the table, so a policy
-- costs no extra row lookup. `current_user_role()` fails closed: a missing or
-- unparseable claim is treated as an ordinary user.

create or replace function public.current_user_role()
returns text
language sql
stable
set search_path = public
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'user_role',
    'user'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = public
as $$
  select public.current_user_role() = 'admin';
$$;

-- MARK: - Policies
--
-- Read-only for clients. There is deliberately NO insert/update/delete policy
-- for `authenticated`: with RLS enabled and no permissive policy, those
-- statements are rejected, so a user cannot promote themselves. Roles are
-- assigned by the server (`service_role` bypasses RLS) or by an administrator
-- through a privileged function.

drop policy if exists "Users read own role" on public.user_roles;
create policy "Users read own role"
on public.user_roles
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "Admins read all roles" on public.user_roles;
create policy "Admins read all roles"
on public.user_roles
for select
to authenticated
using (public.is_admin());

-- MARK: - Default role on signup

create or replace function public.assign_default_user_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_roles (user_id, role)
  values (new.id, 'user')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists assign_default_user_role on auth.users;
create trigger assign_default_user_role
after insert on auth.users
for each row
execute function public.assign_default_user_role();

-- Backfill anyone who signed up before this migration.
insert into public.user_roles (user_id, role)
select id, 'user' from auth.users
on conflict (user_id) do nothing;

create trigger set_user_roles_updated_at
before update on public.user_roles
for each row
execute function public.set_current_timestamp_updated_at();

-- MARK: - Access token hook
--
-- Supabase calls this while minting a token; whatever it returns as `claims`
-- becomes the JWT payload. Keep it cheap: it runs on every login and refresh.

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  claims jsonb;
  resolved_role public.app_user_role;
begin
  select role
    into resolved_role
    from public.user_roles
   where user_id = (event ->> 'user_id')::uuid;

  claims := coalesce(event -> 'claims', '{}'::jsonb);
  -- Always write the claim, so a user with no row still gets an explicit
  -- 'user' rather than a token the client has to guess about.
  claims := jsonb_set(claims, '{user_role}', to_jsonb(coalesce(resolved_role, 'user')::text));

  return jsonb_set(event, '{claims}', claims);
end;
$$;

-- The hook runs as `supabase_auth_admin`, which needs to reach the schema,
-- the function and the table. No one else may execute it.
grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
grant select on public.user_roles to supabase_auth_admin;

revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;

drop policy if exists "Auth admin reads roles" on public.user_roles;
create policy "Auth admin reads roles"
on public.user_roles
for select
to supabase_auth_admin
using (true);

-- MARK: - Administrator surface
--
-- Aggregates only. `security definer` is what lets this read past the
-- per-user policies, so the admin check is the first statement in the body and
-- the search_path is pinned.

create or replace function public.admin_user_overview()
returns table (
  user_id uuid,
  role text,
  notebook_count bigint,
  page_count bigint,
  last_updated timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'administrator role required'
      using errcode = '42501';
  end if;

  return query
    select
      r.user_id,
      r.role::text,
      (select count(*) from public.notebooks n where n.user_id = r.user_id and n.trashed_at is null),
      (select count(*) from public.pages p
        join public.notebooks n2 on n2.id = p.notebook_id
       where n2.user_id = r.user_id),
      (select max(n3.updated_at) from public.notebooks n3 where n3.user_id = r.user_id)
    from public.user_roles r;
end;
$$;

revoke execute on function public.admin_user_overview() from anon;
grant execute on function public.admin_user_overview() to authenticated;
