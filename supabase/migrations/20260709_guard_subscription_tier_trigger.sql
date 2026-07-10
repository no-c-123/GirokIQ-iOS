-- Defense-in-depth: ensure `app_state.subscription_tier` is server-managed even if
-- column privileges or policies are misconfigured.
--
-- Allows changes only when the request JWT role is `service_role`.

create or replace function public.prevent_client_subscription_tier_updates()
returns trigger
language plpgsql
as $$
declare
  jwt_role text := current_setting('request.jwt.claim.role', true);
  db_role text := current_user;
begin
  if new.subscription_tier is distinct from old.subscription_tier then
    -- Supabase sets the request role in a GUC for PostgREST requests, but in some
    -- execution paths the GUC may be unset. We allow the write if either the JWT role
    -- or the effective DB role indicates privileged server execution.
    if coalesce(jwt_role, '') not in ('service_role', 'supabase_admin')
       and db_role not in ('service_role', 'supabase_admin') then
      raise exception 'subscription_tier is server-managed';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_client_subscription_tier_updates on public.app_state;
create trigger prevent_client_subscription_tier_updates
before update of subscription_tier on public.app_state
for each row
execute function public.prevent_client_subscription_tier_updates();
