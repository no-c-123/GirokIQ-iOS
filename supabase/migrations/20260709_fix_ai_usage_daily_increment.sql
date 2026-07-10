-- Fix ambiguous `usage_date` reference inside `increment_ai_usage_daily`.
-- When a PL/pgSQL variable has the same name as a table column, Postgres can raise:
--   "column reference \"usage_date\" is ambiguous"

create or replace function public.increment_ai_usage_daily(p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usage_date date := (timezone('utc', now()))::date;
  v_next_count integer;
begin
  insert into public.ai_usage_daily (user_id, usage_date, request_count, updated_at)
  values (p_user_id, v_usage_date, 1, timezone('utc', now()))
  on conflict (user_id, usage_date) do update
    set request_count = public.ai_usage_daily.request_count + 1,
        updated_at = timezone('utc', now())
  returning request_count into v_next_count;

  return v_next_count;
end;
$$;

