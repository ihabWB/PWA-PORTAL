# Database migrations

Hosted Supabase project, applied **manually from the SQL Editor** (no CLI, no access token).

## How to apply

Run each file in `migrations/` in numeric order, one at a time, and confirm "Success" before the
next. Every file is re-runnable: running one twice is harmless.

| #    | File                              | What it does                                                                                                                                               |
| ---- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0001 | `0001_extensions_and_common.sql`  | PostGIS, btree_gist, `app` helper schema, `updated_at` helper, revoke `anon`                                                                               |
| 0002 | `0002_org.sql`                    | `areas`, `profiles`, `user_areas`; auto-profile on sign-up (inactive, FIELD_TEAM)                                                                          |
| 0003 | `0003_assets.sql`                 | `water_assets` (incl. pass-through flag), `level_volume_curve`, `water_paths`; no-delete guard                                                             |
| 0004 | `0004_measurement.sql`            | `measurement_points`, `meter_devices`, `meter_installations` (no overlaps)                                                                                 |
| 0005 | `0005_readings.sql`               | `readings`, `tank_level_readings`; immutability, supersede, no-overlap, no-delete                                                                          |
| 0006 | `0006_balance.sql`                | `balance_zones`, `balance_zone_members` (INFLOW / OUTFLOW / ARRIVAL / STORAGE)                                                                             |
| 0007 | `0007_operations.sql`             | `assignments`, `system_settings` (thresholds as data), `alerts`, `audit_logs`, import staging                                                              |
| 0008 | `0008_access_helpers.sql`         | `app.user_role()`, `app.can_access_point()` … used by RLS                                                                                                  |
| 0009 | `0009_functions_and_triggers.sql` | audit triggers, `get_storage_m3`, abnormal-reading flag, pass-through mismatch alert, status propagation, `get_missing_readings`, `calculate_zone_balance` |
| 0010 | `0010_rls.sql`                    | `ENABLE ROW LEVEL SECURITY` on every table + explicit policies                                                                                             |
| 0011 | `0011_seed_saeer_chain.sql`       | Saeer chain seed with **placeholder** wells/connections                                                                                                    |
| 0012 | `0012_seed_super_admin.sql`       | Promotes the test user to `SUPER_ADMIN`                                                                                                                    |

Or paste the single bundle produced by `npm run db:bundle` (`supabase/bundle.sql`, git-ignored).

## After applying

1. Regenerate TypeScript types (paste into `src/types/database.ts`):
   Dashboard → API Docs → _Introspection_ / or `npx supabase gen types typescript --project-id <ref>`
   once a token is available. Until then the hand-written types are maintained manually.
2. Sanity checks (SQL Editor):

```sql
select tablename, rowsecurity from pg_tables where schemaname = 'public' order by 1;  -- all true
select * from public.calculate_zone_balance((select id from balance_zones where code='SAEER-TRANSIT'), current_date - 1, current_date - 1);
select * from public.get_missing_readings(current_date - 1, current_date - 1, null);
```

## Functional test

After all 12 files succeed, paste [`tests/functional_test.sql`](tests/functional_test.sql) into the SQL
Editor and run it. It creates a throw-away FIELD_TEAM user, inserts readings, corrections, tank levels,
impersonates users with `set role authenticated`, and then **rolls everything back on purpose** by
ending with `RAISE EXCEPTION`. The editor therefore shows a red error box whose message begins with
`TEST REPORT — N failed of M checks` followed by one `PASS`/`FAIL` line per check. Zero failures is
the goal; send the full message back if any line says `FAIL`.

## Rules baked into the schema

- Readings reference `measurement_point_id`, never a meter.
- Nothing is deleted: triggers refuse `DELETE` on readings, levels, assets, audit logs. Corrections are new rows with `supersedes_id`.
- Thresholds (`pass_through_mismatch_pct`, abnormal-reading σ/window) live in `system_settings`.
- Storage is computed by `get_storage_m3()` from the curve or linear fallback; never in app code.
- Every alert stores its inputs in `details` (jsonb).
