# User roles (administrador / usuario)

Authorization in GirokIQ was originally "every row belongs to exactly one
user": every RLS policy is `user_id = auth.uid()`, and the only privileged
actor is the server-side `service_role`. This document describes the per-user
role added on top of that, how it reaches the client, and what an administrator
can and cannot do.

## Where the role lives

| Layer | What it holds | Enforces? |
| --- | --- | --- |
| `public.user_roles` | the source of truth (`user` or `admin`) | yes — RLS |
| The access token (`user_role` claim) | a copy, written at token-mint time | yes — read by `public.is_admin()` |
| `AuthViewModel.currentUserRole` | a copy, for the UI | **no** |

The Swift value decides what the interface *offers*. It never decides what the
backend *permits*: the token lives on the device, so a determined user can
present whatever they like to client code. Every administrator capability is
enforced again in Postgres. If you add an admin feature, the check in the
database is the real one — the Swift check is a convenience.

## How the claim gets into the token

`public.custom_access_token_hook` runs while Supabase mints a token, looks up
the user's row in `public.user_roles`, and writes `user_role` into the claims.
A user with no row still gets an explicit `"user"`, so the client never has to
guess.

**The migration alone is not enough.** The hook must also be enabled:

1. Supabase dashboard → **Authentication** → **Hooks**
2. **Customize Access Token (JWT) Claims** → enable
3. Select `public.custom_access_token_hook`
4. Sign out and back in — existing tokens keep the old claims until they are
   re-minted.

Until step 2 is done the hook is inert, every token lacks the claim, and
`AppUserRole.from(accessToken:)` resolves everyone to `.user`. That is the
intended failure mode: no claim means no privilege.

## Why roles cannot be self-assigned

`public.user_roles` has RLS enabled with **only** `select` policies for
`authenticated`. With RLS on and no permissive policy for a statement, that
statement is rejected — so there is no insert, update or delete a signed-in
client can perform on its own role. Assignment happens through `service_role`
(which bypasses RLS) or a privileged function.

Promoting someone, from the SQL editor or a server-side context:

```sql
update public.user_roles set role = 'admin' where user_id = '<uuid>';
```

The user's next token refresh picks it up; no sign-out is required.

## What an administrator can do

`public.admin_user_overview()` returns per-user **aggregates**: role, notebook
count, page count, last activity. It is `security definer` so it can read past
the per-user policies, and its first statement is the `is_admin()` check.

It deliberately exposes no note content, no page drawings and no chat history.
Administration here means seeing that an account exists and how much it holds —
not reading someone's notes. Widening that is a product decision to be made
explicitly, not something an admin should inherit by default.

## Verifying it works

```sql
-- as the user in question, after re-authenticating
select public.current_user_role();   -- 'user' or 'admin'
select public.is_admin();            -- false or true

-- should fail for any signed-in client
update public.user_roles set role = 'admin' where user_id = auth.uid();

-- should fail unless the caller is an admin
select * from public.admin_user_overview();
```

On the client, `AuthViewModel.currentUserRole` is refreshed on every sign-in
and can be refreshed on demand with `refreshUserRole()`.

## Related files

- `supabase/migrations/20260916_add_user_roles.sql` — schema, policies, hook
- `GirokIQ-ios/Core/Models/AppUserRole.swift` — claim decoding, fails closed
- `GirokIQ-iosTests/AppUserRoleTests.swift` — the fail-closed contract
