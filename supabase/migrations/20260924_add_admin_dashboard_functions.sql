-- Administrator dashboard: platform-level aggregates
--
-- Extends the administrator surface from a single per-account listing to the
-- numbers an operator actually needs: how many accounts exist, how many are
-- active, what the platform holds, and how AI usage is trending.
--
-- The privacy rule from 20260916_add_user_roles.sql still holds, and is the
-- reason these are functions over aggregates rather than a view over the
-- tables: an administrator sees COUNTS, never content. No note text, no
-- drawings, no chat messages, no page titles, no email addresses. Everything
-- returned here is a number, a date or a role.
--
-- Every function checks is_admin() as its first statement and is
-- `security definer` with a pinned search_path, which is what lets it read
-- past the per-user RLS policies.

-- MARK: - Platform totals

create or replace function public.admin_platform_stats()
returns table (
  total_accounts bigint,
  admin_accounts bigint,
  new_accounts_7d bigint,
  new_accounts_30d bigint,
  active_accounts_7d bigint,
  active_accounts_30d bigint,
  pro_accounts bigint,
  free_accounts bigint,
  total_notebooks bigint,
  total_pages bigint,
  total_elements bigint,
  trashed_notebooks bigint,
  storage_bytes bigint,
  ai_requests_7d bigint,
  ai_requests_30d bigint,
  ai_requests_total bigint
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
    (select count(*) from auth.users),
    (select count(*) from public.user_roles where role = 'admin'),
    (select count(*) from auth.users where created_at > now() - interval '7 days'),
    (select count(*) from auth.users where created_at > now() - interval '30 days'),
    -- "Active" means the account touched a notebook, which is the cheapest
    -- honest proxy for use: sessions are not tracked anywhere.
    (select count(distinct user_id) from public.notebooks
      where updated_at > now() - interval '7 days'),
    (select count(distinct user_id) from public.notebooks
      where updated_at > now() - interval '30 days'),
    (select count(*) from public.app_state where subscription_tier = 'pro'),
    -- An account with no app_state row has never synced a tier, and a null
    -- tier means free, so both are counted as free rather than dropped.
    (select count(*) from auth.users u
      where not exists (
        select 1 from public.app_state s
        where s.user_id = u.id and s.subscription_tier = 'pro'
      )),
    (select count(*) from public.notebooks where deleted_at is null and trashed_at is null),
    (select count(*) from public.pages where deleted_at is null),
    (select count(*) from public.canvas_elements),
    (select count(*) from public.notebooks where trashed_at is not null and deleted_at is null),
    (select coalesce(sum(p.drawing_bytes), 0)::bigint
       + coalesce((
           select sum((o.metadata->>'size')::bigint)
           from storage.objects o
           where o.bucket_id = 'canvas-images'
         ), 0)::bigint
     from public.pages p where p.deleted_at is null),
    (select coalesce(sum(request_count), 0)::bigint from public.ai_usage_daily
      where usage_date > (now() - interval '7 days')::date),
    (select coalesce(sum(request_count), 0)::bigint from public.ai_usage_daily
      where usage_date > (now() - interval '30 days')::date),
    (select coalesce(sum(request_count), 0)::bigint from public.ai_usage_daily);
end;
$$;

revoke execute on function public.admin_platform_stats() from anon;
grant execute on function public.admin_platform_stats() to authenticated;

-- MARK: - Daily series for the dashboard chart

create or replace function public.admin_daily_metrics(days integer default 30)
returns table (
  day date,
  new_accounts bigint,
  ai_requests bigint,
  active_accounts bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  window_days integer := least(greatest(coalesce(days, 30), 1), 365);
begin
  if not public.is_admin() then
    raise exception 'administrator role required'
      using errcode = '42501';
  end if;

  -- generate_series fills the gaps, so a day with no activity comes back as a
  -- zero instead of being missing. A chart that silently skips empty days
  -- misrepresents the trend.
  return query
  with calendar as (
    select generate_series(
      (now() - (window_days - 1) * interval '1 day')::date,
      now()::date,
      interval '1 day'
    )::date as day
  )
  select
    c.day,
    (select count(*) from auth.users u where u.created_at::date = c.day),
    (select coalesce(sum(a.request_count), 0)::bigint from public.ai_usage_daily a
      where a.usage_date = c.day),
    (select count(distinct n.user_id) from public.notebooks n
      where n.updated_at::date = c.day)
  from calendar c
  order by c.day;
end;
$$;

revoke execute on function public.admin_daily_metrics(integer) from anon;
grant execute on function public.admin_daily_metrics(integer) to authenticated;
