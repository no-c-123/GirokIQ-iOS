-- Security hardening:
-- 1) Prevent clients from writing `app_state.subscription_tier` directly.
-- 2) Make `ai_usage_daily` read-only for clients; increments happen server-side.

-- -----------------------------
-- app_state: lock subscription_tier
-- -----------------------------

-- Clients (anon/authenticated) must never be able to update subscription_tier.
revoke update (subscription_tier) on table public.app_state from anon;
revoke update (subscription_tier) on table public.app_state from authenticated;

-- Replace the broad "for all" policy with scoped policies.
drop policy if exists "Users manage own app state" on public.app_state;

create policy "Users read own app state"
on public.app_state
for select
to authenticated
using (user_id = auth.uid());

-- Allow users to create their own row, but only as free.
create policy "Users insert own app state (free only)"
on public.app_state
for insert
to authenticated
with check (user_id = auth.uid() and subscription_tier = 'free');

-- Allow users to update non-entitlement fields (tier column is blocked by column privileges).
create policy "Users update own app state"
on public.app_state
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "Users delete own app state"
on public.app_state
for delete
to authenticated
using (user_id = auth.uid());

-- -----------------------------
-- ai_usage_daily: read-only + server increment function
-- -----------------------------

drop policy if exists "Users manage own AI daily usage" on public.ai_usage_daily;

create policy "Users read own AI daily usage"
on public.ai_usage_daily
for select
to authenticated
using (auth.uid() = user_id);

-- Atomic increment used by the `ai-chat` Edge Function via the service role.
create or replace function public.increment_ai_usage_daily(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  usage_date date := (timezone('utc', now()))::date;
  next_count integer;
begin
  insert into public.ai_usage_daily (user_id, usage_date, request_count, updated_at)
  values (p_user_id, usage_date, 1, timezone('utc', now()))
  on conflict (user_id, usage_date) do update
    set request_count = public.ai_usage_daily.request_count + 1,
        updated_at = timezone('utc', now())
  returning request_count into next_count;

  return next_count;
end;
$$;

-- Don't allow arbitrary clients to call the increment function.
revoke execute on function public.increment_ai_usage_daily(uuid) from public;
grant execute on function public.increment_ai_usage_daily(uuid) to service_role;

