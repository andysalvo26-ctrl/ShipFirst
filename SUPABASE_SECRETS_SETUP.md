# Supabase Secrets Setup

- Open `supabase/functions/.env` and fill in values.
- Then run: `supabase secrets set --env-file supabase/functions/.env`.
- These secrets are for Edge Functions only and must never go in iOS client code.
