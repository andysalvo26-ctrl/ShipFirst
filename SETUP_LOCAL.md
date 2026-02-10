# Local Setup (v0)

Authoritative Supabase values are already committed to:
- `ShipFirstConfig.example.json`
- `Config/Supabase.xcconfig`
- `.env.example`

Use these steps:
1. Copy the JSON config for local runtime use:
   - `cp ShipFirstConfig.example.json ShipFirstConfig.json`
2. Optional local env file for scripts/tools:
   - `cp .env.example .env.local`
3. Ensure your iOS target includes `Config/Supabase.xcconfig` in its xcconfig chain (or equivalent build config include).
4. Never commit `ShipFirstConfig.json` or `.env.local`; both are local-only files.
5. The SQL schema and RLS are already applied manually.
6. No other Supabase setup is required for v0.
