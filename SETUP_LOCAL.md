# Local Setup (v0)

1. Open your Supabase project dashboard, then go to **Project Settings → API**.
2. Copy the **Project URL** and the **anon/public key** from that API page.
3. From the repo root, copy the example file:
   - `cp ShipFirstConfig.example.json ShipFirstConfig.json`
4. Open `ShipFirstConfig.json` and paste your real Supabase values.
5. Never commit `ShipFirstConfig.json`; it is ignored by git and should stay local-only.
6. The SQL schema has already been applied manually.
7. No other Supabase setup is required for v0.
