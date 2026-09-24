## Edge Functions

This directory contains the server-side functions used by the iOS app:

- `ai-chat`: validates the user's Supabase JWT and proxies Anthropic requests from the server
- `delete-account`: validates the user's Supabase JWT, deletes user-owned data, then removes the auth user

### Required secrets

Set these in your Supabase project before deploying:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SERVICE_ROLE_KEY` (recommended; Supabase UI blocks `SUPABASE_*` custom secret names)
- `ANTHROPIC_API_KEY`

### Deploy

```bash
supabase functions deploy ai-chat
supabase functions deploy delete-account
```

### Local serve

```bash
supabase functions serve --env-file .env.local
```
