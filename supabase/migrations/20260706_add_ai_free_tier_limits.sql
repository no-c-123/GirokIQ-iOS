alter table public.app_state
  add column if not exists subscription_tier text not null default 'free';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'app_state_subscription_tier_check'
  ) then
    alter table public.app_state
      add constraint app_state_subscription_tier_check
      check (subscription_tier in ('free', 'pro'));
  end if;
end $$;

create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users (id) on delete cascade,
  usage_date date not null default (timezone('utc', now()))::date,
  request_count integer not null default 0,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, usage_date),
  constraint ai_usage_daily_request_count_check check (request_count >= 0)
);

create index if not exists ai_usage_daily_user_date_idx
  on public.ai_usage_daily (user_id, usage_date desc);

alter table public.ai_usage_daily enable row level security;

drop policy if exists "Users manage own AI daily usage" on public.ai_usage_daily;
create policy "Users manage own AI daily usage"
on public.ai_usage_daily
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
