-- =============================================================================
-- FUNCTIONAL TEST — safe to run against the production project at any time.
-- Run in the Supabase SQL Editor AFTER migrations 0001–0018
-- (order: 0001…0011, 0013, 0014, 0015, 0016, 0017, 0018, then 0012 last).
--
-- The whole run is ROLLED BACK by design: the closing RAISE EXCEPTION carries the
-- report, so the editor shows a red box whose message starts with "TEST REPORT".
-- That is the expected outcome. No test data, no test user and no alerts survive.
--
-- Three properties make the report trustworthy:
--
--  1. ISOLATION. The test builds its OWN area, assets, measurement points and balance
--     zone, all prefixed ZZT-, and asserts only against those. It never reads a seeded
--     row and never assumes an empty database, so entering real readings — or renaming
--     every placeholder — cannot make it fail. Where a function is global by nature
--     (entry tasks, missing readings, placeholder inventory) the assertion is scoped by
--     the test prefix or the test area, never by an absolute row count.
--
--  2. RECORDING. Results accumulate with array_append() into a PL/pgSQL text[].
--     `v_res := v_res || 'literal'` is NOT used: with an unknown-typed literal on the
--     right PostgreSQL resolves `anyarray || anyarray` and fails with 22P02, which once
--     aborted whole sections. A variable also has no ACL, so recording cannot fail under
--     `set local role`. The MECHANISM block proves both before anything else runs.
--
--  3. FIXTURES OUTSIDE HANDLERS. BEGIN…EXCEPTION opens a subtransaction: a section that
--     raised used to roll back its own inserts while its PASS lines survived, so later
--     sections measured missing data and reported false failures.
--
-- Covers:  0 audit on tables without an `id` column   1 supersede + immutability + audit
--          2 pass-through mismatch alert              3 zone balance with incomplete data
--          4 negative RLS as FIELD_TEAM               5 inactive user scope
--          6 storage curve / linear fallback          7 status propagation + SOURCE_STOPPED
--          8 abnormal-reading flag                    9 management scope (positive control)
--         10 non-daily points and entry tasks        11 asset management write path
-- =============================================================================
do $$
declare
  v_admin  uuid;
  v_field  uuid := gen_random_uuid();
  v_area   uuid;
  v_zone   uuid;
  v_aw1 uuid; v_atank uuid; v_asp uuid; v_atmp uuid;
  v_pw1 uuid; v_pw2 uuid; v_pw3 uuid; v_pw4 uuid; v_pw5 uuid;
  v_pin uuid; v_pout uuid; v_psp uuid; v_ptmp uuid;
  v_d      date := date '2019-06-01';   -- far past: cannot collide with operational data
  v_r1 uuid; v_r2 uuid; v_r3 uuid; v_r4 uuid;
  v_new_asset uuid; v_new_point uuid;
  v_old    public.readings%rowtype;
  v_bal    record;
  v_i      int;
  v_n      int;
  v_num    numeric;
  v_txt    text;
  v_res    text[] := '{}';             -- PASS/FAIL lines; no ACL, survives `set role`
  v_ok     boolean;
  v_total  int;
  v_fail   int;
  v_crash  int;
begin
  -- ============================== MECHANISM SELF-CHECK ==============================
  begin
    v_res := array_append(v_res, 'PASS  mechanism: array_append with a bare literal');
    v_res := array_append(v_res, (case when true then 'PASS  mechanism: array_append with a CASE expression'
                                       else 'FAIL  mechanism: CASE' end));
    v_res := array_append(v_res, 'PASS  mechanism: array_append with a numeric detail (' || 0 || ')');
    if array_length(v_res, 1) <> 3 then
      raise exception 'recorded % lines, expected 3', coalesce(array_length(v_res, 1), 0);
    end if;
  exception when others then
    raise exception 'RECORDING MECHANISM BROKEN: % %', sqlstate, sqlerrm;
  end;

  -- ============================== ENVIRONMENT CHECKS =================================
  select id into v_admin from auth.users where lower(email) = 'ehabomear@gmail.com';
  v_ok := v_admin is not null;
  v_res := array_append(v_res, (case when v_ok then 'PASS  env: admin auth user found'
                                     else 'FAIL  env: admin auth user found  — ehabomear@gmail.com missing' end));

  v_ok := exists (select 1 from public.profiles where id = v_admin and role = 'SUPER_ADMIN' and is_active);
  v_res := array_append(v_res, (case when v_ok then 'PASS  env: admin profile is an active SUPER_ADMIN (0012 applied)'
                                     else 'FAIL  env: admin profile is an active SUPER_ADMIN  — re-run 0012 last' end));

  select string_agg(want, ', ') into v_txt
  from (values ('self_role'), ('user_role'), ('can_access_point')) w(want)
  where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'app' and p.proname = w.want);
  v_ok := v_txt is null;
  v_res := array_append(v_res, (case when v_ok then 'PASS  env: the app helper functions exist (0008 and 0014 applied)'
                                     else 'FAIL  env: missing app helpers  — ' || v_txt end));

  select string_agg(want, ', ') into v_txt
  from (values ('calculate_zone_balance'), ('get_daily_entry_tasks'), ('get_asset_catalogue'),
               ('get_placeholder_rows'), ('upsert_water_asset'), ('retire_water_asset')) w(want)
  where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = w.want);
  v_ok := v_txt is null;
  v_res := array_append(v_res, (case when v_ok then 'PASS  env: the public functions exist (0016, 0017 and 0018 applied)'
                                     else 'FAIL  env: missing public functions  — ' || v_txt end));

  select count(*) into v_n from pg_tables where schemaname = 'public' and not rowsecurity;
  v_ok := v_n = 0;
  v_res := array_append(v_res, (case when v_ok then 'PASS  env: row level security is enabled on every public table'
                                     else 'FAIL  env: ' || v_n || ' public table(s) without RLS' end));

  -- ==================================== FIXTURES ====================================
  -- Everything the test asserts on is created by the test, outside every exception handler.
  begin
    insert into public.areas (code, name_ar, name_en) values ('ZZT-AREA', 'منطقة اختبار', 'Test area')
    returning id into v_area;

    for v_i in 1..7 loop
      insert into public.water_assets (code, name_ar, asset_type, supply_type, area_id, current_status)
      values ('ZZT-W-' || v_i, 'بئر اختبار ' || v_i, 'WELL', 'GROUNDWATER', v_area, 'UNKNOWN');
    end loop;
    for v_i in 1..2 loop
      insert into public.water_assets (code, name_ar, asset_type, supply_type, area_id, current_status)
      values ('ZZT-IC-' || v_i, 'وصلة اختبار ' || v_i, 'ISRAELI_CONNECTION', 'ISRAELI', v_area, 'UNKNOWN');
    end loop;

    insert into public.water_assets (code, name_ar, asset_type, area_id, current_status, is_pass_through)
    values ('ZZT-TANK', 'خزان عبور اختبار', 'TANK', v_area, 'UNKNOWN', true) returning id into v_atank;
    insert into public.water_assets (code, name_ar, asset_type, area_id, current_status)
    values ('ZZT-SP-1', 'مزوّد اختبار', 'SERVICE_PROVIDER', v_area, 'OPERATING') returning id into v_asp;
    -- a placeholder-shaped code, so the inventory is tested without touching seeded rows
    insert into public.water_assets (code, name_ar, asset_type, supply_type, area_id, current_status)
    values ('ZZT-TMP-X', 'بئر مؤقت اختبار', 'WELL', 'GROUNDWATER', v_area, 'UNKNOWN') returning id into v_atmp;

    select id into v_aw1 from public.water_assets where code = 'ZZT-W-1';

    for v_i in 1..7 loop
      insert into public.measurement_points (code, name_ar, point_type, asset_id, area_id, expects_daily_reading)
      select 'ZZT-MP-W-' || v_i, 'عداد بئر اختبار ' || v_i, 'SOURCE_METER', a.id, v_area, true
      from public.water_assets a where a.code = 'ZZT-W-' || v_i;
    end loop;
    for v_i in 1..2 loop
      insert into public.measurement_points (code, name_ar, point_type, asset_id, area_id, expects_daily_reading)
      select 'ZZT-MP-IC-' || v_i, 'عداد وصلة اختبار ' || v_i, 'SOURCE_METER', a.id, v_area, true
      from public.water_assets a where a.code = 'ZZT-IC-' || v_i;
    end loop;

    insert into public.measurement_points (code, name_ar, point_type, asset_id, area_id, expects_daily_reading)
    values ('ZZT-MP-IN',  'عداد مدخل اختبار', 'TANK_INLET_METER',  v_atank, v_area, true) returning id into v_pin;
    insert into public.measurement_points (code, name_ar, point_type, asset_id, area_id, expects_daily_reading)
    values ('ZZT-MP-OUT', 'عداد مخرج اختبار', 'TANK_OUTLET_METER', v_atank, v_area, true) returning id into v_pout;
    insert into public.measurement_points (code, name_ar, point_type, asset_id, area_id, expects_daily_reading)
    values ('ZZT-MP-SP-1', 'عداد مزوّد اختبار', 'SERVICE_PROVIDER_METER', v_asp, v_area, false) returning id into v_psp;
    insert into public.measurement_points (code, name_ar, point_type, asset_id, area_id, expects_daily_reading)
    values ('ZZT-MP-TMP-X', 'عداد مؤقت اختبار', 'SOURCE_METER', v_atmp, v_area, false) returning id into v_ptmp;

    select id into v_pw1 from public.measurement_points where code = 'ZZT-MP-W-1';
    select id into v_pw2 from public.measurement_points where code = 'ZZT-MP-W-2';
    select id into v_pw3 from public.measurement_points where code = 'ZZT-MP-W-3';
    select id into v_pw4 from public.measurement_points where code = 'ZZT-MP-W-4';
    select id into v_pw5 from public.measurement_points where code = 'ZZT-MP-W-5';

    -- the test's own transit zone: nine inflows, one arrival, no storage term
    insert into public.balance_zones (code, name_ar) values ('ZZT-ZONE', 'منطقة موازنة اختبار')
    returning id into v_zone;
    insert into public.balance_zone_members (zone_id, measurement_point_id, role, measurement_quality, sign)
    select v_zone, mp.id, 'INFLOW', 'MEASURED', 1
    from public.measurement_points mp
    where mp.code like 'ZZT-MP-W-%' or mp.code like 'ZZT-MP-IC-%';
    insert into public.balance_zone_members (zone_id, measurement_point_id, role, measurement_quality, sign)
    values (v_zone, v_pin, 'ARRIVAL', 'MEASURED', 1);

    -- a throw-away FIELD_TEAM user assigned to exactly one test point
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    values (v_field, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'field.test@example.invalid', extensions.crypt('Test-1234', extensions.gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', '{"full_name":"Field Tester"}', now(), now(),
            '', '', '', '');
    update public.profiles set is_active = true, role = 'FIELD_TEAM', full_name_ar = 'عامل حقلي تجريبي'
     where id = v_field;
    insert into public.assignments (user_id, measurement_point_id, active_from)
    values (v_field, v_pw1, date '2019-01-01');

    -- supersede fixture on the assigned point (day 0)
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_pw1, v_d, v_d, 1200, 'METER_DISPLAY', 'OPERATING', v_admin) returning id into v_r1;
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by, supersedes_id, notes)
    values (v_pw1, v_d, v_d, 1250, 'METER_DISPLAY', 'OPERATING', v_admin, v_r1, 'تصحيح') returning id into v_r2;

    -- pass-through pairs: 10% (>3%), then 1.5% (<3%), then tighten to 1% and repeat 1.5%
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_pin,  v_d,     v_d,     1000, 'METER_DIFF', v_admin),
           (v_pout, v_d,     v_d,      900, 'METER_DIFF', v_admin),
           (v_pin,  v_d + 1, v_d + 1, 1000, 'METER_DIFF', v_admin),
           (v_pout, v_d + 1, v_d + 1,  985, 'METER_DIFF', v_admin);
    update public.water_assets set pass_through_tolerance_pct = 1 where id = v_atank;
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_pin,  v_d + 2, v_d + 2, 1000, 'METER_DIFF', v_admin),
           (v_pout, v_d + 2, v_d + 2,  985, 'METER_DIFF', v_admin);

    -- four more sources on day 0; wells 6 and 7 and both connections stay missing on purpose
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_pw2, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_pw3, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_pw4, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_pw5, v_d, v_d, 800, 'METER_DISPLAY', v_admin);

    -- a 2-day reading for the proration check
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_pw2, v_d + 1, v_d + 2, 600, 'METER_DIFF', v_admin);

    -- status propagation: newer STOPPED first, then an OLDER OPERATING that must not win
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_pw1, v_d + 6, v_d + 6, 0, 'ESTIMATE', 'STOPPED', v_admin);
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_pw1, v_d + 3, v_d + 3, 1100, 'METER_DISPLAY', 'OPERATING', v_admin);

    -- abnormal-reading history: eight flat days, then a spike
    for v_i in 10..17 loop
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
      values (v_pw2, v_d + v_i, v_d + v_i, 1000, 'METER_DISPLAY', v_admin);
    end loop;
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_pw2, v_d + 18, v_d + 18, 5000, 'METER_DISPLAY', v_admin) returning id into v_r3;

    -- one reading on the placeholder-shaped point, so renaming can be shown to keep it
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_ptmp, v_d, v_d, 500, 'ESTIMATE', v_admin);
  exception when others then
    raise exception 'FIXTURE STAGE FAILED (nothing was tested): % %', sqlstate, sqlerrm;
  end;

  -- ------------------------- 0. audit on tables without an `id` column (0013) --
  begin
    insert into public.user_areas (user_id, area_id) values (v_field, v_area);
    v_res := array_append(v_res, 'PASS  0 audit: INSERT into user_areas (composite PK) succeeds');

    v_ok := exists (select 1 from public.audit_logs where entity_table = 'user_areas' and action = 'INSERT'
                      and entity_id is null and (entity_key ->> 'user_id')::uuid = v_field
                      and (entity_key ->> 'area_id')::uuid = v_area);
    v_res := array_append(v_res, (case when v_ok then 'PASS  0 audit: user_areas logged with entity_key, entity_id null'
                                       else 'FAIL  0 audit: user_areas logged with entity_key, entity_id null' end));

    update public.system_settings set value = '4' where key = 'pass_through_mismatch_pct';
    v_ok := exists (select 1 from public.audit_logs where entity_table = 'system_settings' and action = 'UPDATE'
                      and entity_key ->> 'key' = 'pass_through_mismatch_pct');
    v_res := array_append(v_res, (case when v_ok then 'PASS  0 audit: system_settings (text PK) logged with entity_key'
                                       else 'FAIL  0 audit: system_settings (text PK) logged with entity_key' end));
    update public.system_settings set value = '3' where key = 'pass_through_mismatch_pct';

    v_ok := exists (select 1 from public.audit_logs where entity_table = 'readings' and entity_id = v_r2
                      and entity_key ->> 'id' = v_r2::text);
    v_res := array_append(v_res, (case when v_ok then 'PASS  0 audit: tables with an id column keep entity_id AND entity_key'
                                       else 'FAIL  0 audit: tables with an id column keep entity_id AND entity_key' end));
  exception when others then
    v_res := array_append(v_res, 'FAIL  0 section crashed (is 0013 applied?)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------- 1. supersede + immutability
  begin
    select * into v_old from public.readings where id = v_r1;

    v_ok := v_old.is_superseded;
    v_res := array_append(v_res, (case when v_ok then 'PASS  1 supersede: original marked is_superseded'
                                       else 'FAIL  1 supersede: original marked is_superseded' end));

    v_ok := v_old.volume_m3 = 1200;
    v_res := array_append(v_res, (case when v_ok then 'PASS  1 supersede: original volume intact (1200)'
                                       else 'FAIL  1 supersede: original volume intact (1200)  — got ' || v_old.volume_m3 end));

    v_ok := (select count(*) from public.readings
              where measurement_point_id = v_pw1 and covers_from = v_d and not is_superseded) = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  1 supersede: the correction is the only active row for that day'
                                       else 'FAIL  1 supersede: the correction is the only active row for that day' end));

    v_ok := (select supersedes_id = v_r1 from public.readings where id = v_r2);
    v_res := array_append(v_res, (case when v_ok then 'PASS  1 supersede: the correction points at the original'
                                       else 'FAIL  1 supersede: the correction points at the original' end));

    begin
      update public.readings set volume_m3 = 999 where id = v_r1;
      v_res := array_append(v_res, 'FAIL  1 immutability: UPDATE of volume refused  — update was allowed');
    exception when others then
      v_res := array_append(v_res, 'PASS  1 immutability: UPDATE of volume refused (' || sqlstate || ')');
    end;

    begin
      update public.readings set covers_from = v_d + 30, covers_to = v_d + 30 where id = v_r2;
      v_res := array_append(v_res, 'FAIL  1 immutability: UPDATE of the covered period refused  — update was allowed');
    exception when others then
      v_res := array_append(v_res, 'PASS  1 immutability: UPDATE of the covered period refused (' || sqlstate || ')');
    end;

    begin
      delete from public.readings where id = v_r1;
      v_res := array_append(v_res, 'FAIL  1 immutability: DELETE refused  — delete was allowed');
    exception when others then
      v_res := array_append(v_res, 'PASS  1 immutability: DELETE refused (' || sqlstate || ')');
    end;

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by, supersedes_id)
      values (v_pw1, v_d, v_d, 1, 'ESTIMATE', v_admin, v_r1);
      v_res := array_append(v_res, 'FAIL  1 supersede: double supersede refused  — was allowed');
    exception when others then
      v_res := array_append(v_res, 'PASS  1 supersede: double supersede refused (' || sqlstate || ')');
    end;

    select count(*) into v_n from public.audit_logs where entity_table = 'readings' and entity_id in (v_r1, v_r2);
    v_ok := v_n >= 3;
    v_res := array_append(v_res, (case when v_ok then 'PASS  1 audit: both inserts and the supersede update are logged (>=3)'
                                       else 'FAIL  1 audit: both inserts and the supersede update are logged (>=3)  — rows=' || v_n end));

    v_ok := exists (select 1 from public.audit_logs where entity_id = v_r1 and action = 'UPDATE'
                      and (old_value ->> 'is_superseded')::boolean = false
                      and (new_value ->> 'is_superseded')::boolean = true);
    v_res := array_append(v_res, (case when v_ok then 'PASS  1 audit: the previous value is recoverable from audit_logs'
                                       else 'FAIL  1 audit: the previous value is recoverable from audit_logs' end));
  exception when others then
    v_res := array_append(v_res, 'FAIL  1 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------------ 2. pass-through check
  begin
    v_ok := exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                      and asset_id = v_atank and reference_date = v_d and status = 'OPEN');
    v_res := array_append(v_res, (case when v_ok then 'PASS  2 pass-through: 10% mismatch raised PASS_THROUGH_MISMATCH'
                                       else 'FAIL  2 pass-through: 10% mismatch raised PASS_THROUGH_MISMATCH' end));

    select (details ->> 'difference_pct')::numeric into v_num
    from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH' and asset_id = v_atank and reference_date = v_d;
    v_ok := v_num between 9.9 and 10.1
            and (select (details ->> 'threshold_pct')::numeric = 3 and (details ->> 'inlet_m3')::numeric = 1000
                   from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                    and asset_id = v_atank and reference_date = v_d);
    v_res := array_append(v_res, (case when v_ok then 'PASS  2 pass-through: the alert stores its inputs (difference 10%, threshold 3%)'
                                       else 'FAIL  2 pass-through: the alert stores its inputs  — difference_pct=' || coalesce(v_num::text, 'null') end));

    v_ok := not exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                          and asset_id = v_atank and reference_date = v_d + 1);
    v_res := array_append(v_res, (case when v_ok then 'PASS  2 pass-through: 1.5% mismatch under a 3% threshold raises nothing'
                                       else 'FAIL  2 pass-through: 1.5% mismatch under a 3% threshold raises nothing' end));

    v_ok := exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                      and asset_id = v_atank and reference_date = v_d + 2);
    v_res := array_append(v_res, (case when v_ok then 'PASS  2 pass-through: the same 1.5% alerts after the per-asset threshold drops to 1%'
                                       else 'FAIL  2 pass-through: the same 1.5% alerts after the per-asset threshold drops to 1%' end));
  exception when others then
    v_res := array_append(v_res, 'FAIL  2 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------- 3. balance with incomplete data
  begin
    -- day 0 on the test zone: 1250 (corrected) + 4 x 800 = 4450 in; 1000 arrived; 3450 unexplained
    select * into v_bal from public.calculate_zone_balance(v_zone, v_d, v_d);

    v_ok := v_bal.inflow_m3 = 4450;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 balance: inflow = 4450'
                                       else 'FAIL  3 balance: inflow = 4450  — got ' || v_bal.inflow_m3 end));

    v_ok := v_bal.inflow_groundwater_m3 = 4450 and v_bal.inflow_israeli_m3 = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 balance: groundwater 4450 / israeli 0'
                                       else 'FAIL  3 balance: groundwater 4450 / israeli 0  — got '
                                            || v_bal.inflow_groundwater_m3 || ' / ' || v_bal.inflow_israeli_m3 end));

    v_ok := v_bal.arrival_m3 = 1000;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 balance: arrival = 1000'
                                       else 'FAIL  3 balance: arrival = 1000  — got ' || v_bal.arrival_m3 end));

    v_ok := v_bal.outflow_measured_m3 = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 balance: measured outflow = 0 (no route meters)'
                                       else 'FAIL  3 balance: measured outflow = 0  — got ' || v_bal.outflow_measured_m3 end));

    v_ok := v_bal.difference_m3 = 3450;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 balance: difference (unexplained) = 3450'
                                       else 'FAIL  3 balance: difference (unexplained) = 3450  — got ' || v_bal.difference_m3 end));

    v_ok := v_bal.storage_change_m3 = 0 and v_bal.storage_complete;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 balance: no storage term for a transit zone'
                                       else 'FAIL  3 balance: no storage term for a transit zone' end));

    v_ok := v_bal.points_expected = 10;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 completeness: points_expected = 10'
                                       else 'FAIL  3 completeness: points_expected = 10  — got ' || v_bal.points_expected end));

    v_ok := v_bal.points_complete = 6;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 completeness: points_complete = 6'
                                       else 'FAIL  3 completeness: points_complete = 6  — got ' || v_bal.points_complete end));

    v_ok := v_bal.point_days_reported = 6 and v_bal.point_days_expected = 10;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 completeness: point-days 6/10'
                                       else 'FAIL  3 completeness: point-days 6/10  — got '
                                            || v_bal.point_days_reported || '/' || v_bal.point_days_expected end));

    v_ok := v_bal.sources_total = 9 and v_bal.sources_operating = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 sources: total 9, operating 1'
                                       else 'FAIL  3 sources: total 9, operating 1  — got total='
                                            || v_bal.sources_total || ' operating=' || v_bal.sources_operating end));

    v_ok := v_bal.sources_groundwater_total = 7 and v_bal.sources_groundwater_reported = 5
            and v_bal.sources_israeli_total = 2 and v_bal.sources_israeli_reported = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 sources: by supply type, groundwater 5/7 and israeli 0/2'
                                       else 'FAIL  3 sources: by supply type  — gw '
                                            || v_bal.sources_groundwater_reported || '/' || v_bal.sources_groundwater_total
                                            || ' il ' || v_bal.sources_israeli_reported || '/' || v_bal.sources_israeli_total end));

    v_ok := (v_bal.by_role -> 'INFLOW' ->> 'points_complete')::int = 5
            and (v_bal.by_role -> 'INFLOW' ->> 'points_expected')::int = 9;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 by_role: INFLOW 5/9 complete'
                                       else 'FAIL  3 by_role: INFLOW 5/9 complete  — ' || v_bal.by_role::text end));

    -- scoped to the test area, so operational points elsewhere cannot change the count
    select count(*) into v_n from public.get_missing_readings(v_d, v_d, v_area);
    v_ok := v_n = 4;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 missing readings: 4 of the 11 daily test points missing on day 0'
                                       else 'FAIL  3 missing readings: expected 4  — got ' || v_n end));

    select * into v_bal from public.calculate_zone_balance(v_zone, v_d + 1, v_d + 1);
    v_ok := v_bal.inflow_m3 = 300;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 proration: a 2-day 600 m³ reading contributes 300 to one day'
                                       else 'FAIL  3 proration: expected 300  — got ' || v_bal.inflow_m3 end));

    v_ok := v_bal.points_complete = 2;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 proration: the 2-day reading counts as coverage on both days'
                                       else 'FAIL  3 proration: coverage  — got ' || v_bal.points_complete end));

    select * into v_bal from public.calculate_zone_balance(v_zone, v_d, v_d + 2);
    v_ok := v_bal.point_days_expected = 30 and v_bal.arrival_m3 = 3000;
    v_res := array_append(v_res, (case when v_ok then 'PASS  3 range: 3-day window → 30 point-days expected, arrival 3000'
                                       else 'FAIL  3 range: 3-day window  — point-days=' || v_bal.point_days_expected
                                            || ' arrival=' || v_bal.arrival_m3 end));
  exception when others then
    v_res := array_append(v_res, 'FAIL  3 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------ 4. negative RLS: FIELD_TEAM
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_field, 'role', 'authenticated')::text, true);

    v_ok := auth.uid() = v_field;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: impersonation active (auth.uid() = the field user)'
                                       else 'FAIL  4 rls: impersonation active  — auth.uid()=' || coalesce(auth.uid()::text, 'null') end));

    v_ok := app.user_role() = 'FIELD_TEAM';
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: app.user_role() = FIELD_TEAM'
                                       else 'FAIL  4 rls: app.user_role() = FIELD_TEAM  — got ' || coalesce(app.user_role(), 'null') end));

    -- a fresh user with exactly one assignment: independent of how large the catalogue is
    select count(*) into v_n from public.measurement_points;
    v_ok := v_n = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: sees exactly the 1 assigned point out of the whole catalogue'
                                       else 'FAIL  4 rls: sees exactly the 1 assigned point  — got ' || v_n end));

    select count(*) into v_n from public.readings where measurement_point_id = v_pw2;
    v_ok := v_n = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: readings of an unassigned point are hidden (0)'
                                       else 'FAIL  4 rls: readings of an unassigned point are hidden (0)  — got ' || v_n end));

    -- SPEC §6: the entry form shows the previous few days on the assigned point.
    select count(*) into v_n from public.readings where measurement_point_id = v_pw1;
    v_ok := v_n = 4;    -- superseded 1200, corrected 1250, day+3, day+6 — all created by this test
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: all 4 readings of the assigned point are visible'
                                       else 'FAIL  4 rls: all 4 readings of the assigned point are visible  — got ' || v_n end));

    v_ok := (select count(*) from public.readings where id in (v_r1, v_r2)) = 2;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: history includes the superseded row'
                                       else 'FAIL  4 rls: history includes the superseded row' end));

    v_ok := (select count(distinct covers_from) from public.readings where measurement_point_id = v_pw1) >= 3;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: previous days'' values are readable for the entry form'
                                       else 'FAIL  4 rls: previous days'' values are readable for the entry form' end));

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis)
      values (v_pw2, v_d + 5, v_d + 5, 10, 'ESTIMATE');
      v_res := array_append(v_res, 'FAIL  4 rls: INSERT on an unassigned point refused  — insert was allowed');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '42501' then 'PASS  4 rls: INSERT on an unassigned point refused (42501)'
                                         else 'FAIL  4 rls: INSERT on an unassigned point  — wrong error ' || sqlstate || ' ' || sqlerrm end));
    end;

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
      values (v_pw1, v_d + 5, v_d + 5, 10, 'ESTIMATE', v_admin);   -- forging entered_by
      v_res := array_append(v_res, 'FAIL  4 rls: INSERT with a forged entered_by refused  — insert was allowed');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '42501' then 'PASS  4 rls: INSERT with a forged entered_by refused (42501)'
                                         else 'FAIL  4 rls: INSERT with a forged entered_by  — wrong error ' || sqlstate || ' ' || sqlerrm end));
    end;

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis)
    values (v_pw1, v_d + 5, v_d + 5, 10, 'ESTIMATE') returning id into v_r4;
    v_ok := (select entered_by = v_field from public.readings where id = v_r4);
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: INSERT on the assigned point allowed, entered_by = self'
                                       else 'FAIL  4 rls: INSERT on the assigned point allowed, entered_by = self' end));

    update public.readings set validation_notes = 'x' where id = v_r4;
    get diagnostics v_n = row_count;
    v_ok := v_n = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: UPDATE by the field team affects 0 rows'
                                       else 'FAIL  4 rls: UPDATE by the field team affects 0 rows  — rows=' || v_n end));

    begin
      delete from public.readings where id = v_r4;
      get diagnostics v_n = row_count;
      v_ok := v_n = 0;
      v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: DELETE by the field team affects 0 rows'
                                         else 'FAIL  4 rls: DELETE by the field team  — deleted ' || v_n || ' row(s)' end));
    exception when others then
      v_res := array_append(v_res, 'PASS  4 rls: DELETE by the field team refused (' || sqlstate || ')');
    end;

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, supersedes_id)
    values (v_pw1, v_d + 5, v_d + 5, 12, 'ESTIMATE', v_r4);
    v_ok := (select is_superseded from public.readings where id = v_r4);
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: the field team corrects its own reading via supersede (no UPDATE right)'
                                       else 'FAIL  4 rls: the field team corrects its own reading via supersede' end));

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, supersedes_id)
      values (v_pw1, v_d + 5, v_d + 5, 13, 'ESTIMATE', v_r4);      -- already superseded above
      v_res := array_append(v_res, 'FAIL  4 rls: supersede of an already-superseded row refused  — was allowed');
    exception when others then
      v_res := array_append(v_res, 'PASS  4 rls: supersede of an already-superseded row refused (' || sqlstate || ')');
    end;

    select count(*) into v_n from public.alerts where asset_id = v_atank;
    v_ok := v_n = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: tank alerts are hidden from the field team (0)'
                                       else 'FAIL  4 rls: tank alerts are hidden from the field team (0)  — got ' || v_n end));

    select count(*) into v_n from public.audit_logs;
    v_ok := v_n = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: audit_logs are hidden from the field team (0)'
                                       else 'FAIL  4 rls: audit_logs are hidden from the field team (0)  — got ' || v_n end));

    select count(*) into v_n from public.profiles;
    v_ok := v_n = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: profiles → own row only (1)'
                                       else 'FAIL  4 rls: profiles → own row only (1)  — got ' || v_n end));

    -- 0014 regression: editing one's own name/phone must WORK (it raised 42P17 before).
    begin
      update public.profiles set phone = '0599000000', full_name_ar = 'اسم محدَّث' where id = auth.uid();
      get diagnostics v_n = row_count;
      v_ok := v_n = 1;
      v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: a user may edit their own name/phone (no 42P17)'
                                         else 'FAIL  4 rls: a user may edit their own name/phone  — rows=' || v_n end));
    exception when others then
      v_res := array_append(v_res, 'FAIL  4 rls: a user may edit their own name/phone  — ' || sqlstate || ' ' || sqlerrm
                                   || (case when sqlstate = '42P17' then ' (apply 0014)' else '' end));
    end;

    begin
      update public.profiles set role = 'SUPER_ADMIN' where id = auth.uid();
      get diagnostics v_n = row_count;
      v_res := array_append(v_res, 'FAIL  4 rls: self-promotion to SUPER_ADMIN refused  — updated ' || v_n || ' row(s)');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '42501' then 'PASS  4 rls: self-promotion to SUPER_ADMIN refused (42501)'
                                         else 'FAIL  4 rls: self-promotion refused for the WRONG reason  — ' || sqlstate || ' ' || sqlerrm end));
    end;

    begin
      update public.profiles set is_active = false where id = auth.uid();
      get diagnostics v_n = row_count;
      v_res := array_append(v_res, 'FAIL  4 rls: changing one''s own activation refused  — updated ' || v_n || ' row(s)');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '42501' then 'PASS  4 rls: changing one''s own activation refused (42501)'
                                         else 'FAIL  4 rls: activation change refused for the WRONG reason  — ' || sqlstate end));
    end;

    begin
      insert into public.water_assets (code, name_ar, asset_type, supply_type) values ('ZZT-HACK', 'x', 'WELL', 'GROUNDWATER');
      v_res := array_append(v_res, 'FAIL  4 rls: the field team cannot create assets  — was allowed');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '42501' then 'PASS  4 rls: the field team cannot create assets (42501)'
                                         else 'FAIL  4 rls: asset creation refused for the WRONG reason  — ' || sqlstate end));
    end;

    begin
      update public.system_settings set value = '99' where key = 'pass_through_mismatch_pct';
      get diagnostics v_n = row_count;
      v_ok := v_n = 0;
      v_res := array_append(v_res, (case when v_ok then 'PASS  4 rls: the field team cannot change thresholds'
                                         else 'FAIL  4 rls: the field team cannot change thresholds  — rows=' || v_n end));
    exception when others then
      v_res := array_append(v_res, 'PASS  4 rls: the field team cannot change thresholds (' || sqlstate || ')');
    end;

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_res := array_append(v_res, 'FAIL  4 section crashed (its writes were rolled back)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------------- 5. inactive user
  begin
    update public.profiles set is_active = false where id = v_field;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_field, 'role', 'authenticated')::text, true);

    select count(*) into v_n from public.profiles where id = auth.uid();
    v_ok := v_n = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  5 inactive: own profile stays readable (the UI can explain the state)'
                                       else 'FAIL  5 inactive: own profile stays readable  — got ' || v_n end));

    v_ok := (select not is_active from public.profiles where id = auth.uid());
    v_res := array_append(v_res, (case when v_ok then 'PASS  5 inactive: is_active reads false'
                                       else 'FAIL  5 inactive: is_active reads false' end));

    select count(*) into v_n from public.measurement_points;
    v_ok := v_n = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  5 inactive: sees 0 measurement points'
                                       else 'FAIL  5 inactive: sees 0 measurement points  — got ' || v_n end));

    select count(*) into v_n from public.readings;
    v_ok := v_n = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  5 inactive: sees 0 readings'
                                       else 'FAIL  5 inactive: sees 0 readings  — got ' || v_n end));

    v_ok := app.user_role() is null;
    v_res := array_append(v_res, (case when v_ok then 'PASS  5 inactive: app.user_role() is null'
                                       else 'FAIL  5 inactive: app.user_role() is null  — got ' || coalesce(app.user_role(), 'null') end));

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    update public.profiles set is_active = true where id = v_field;
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_res := array_append(v_res, 'FAIL  5 section crashed (its writes were rolled back)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ---------------------------------------------- 6. storage: curve / fallback
  begin
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_atank, v_d, 2.5, v_admin);
    v_ok := (select storage_m3 is null and percentage_full is null
               from public.tank_level_readings where asset_id = v_atank and reading_date = v_d);
    v_res := array_append(v_res, (case when v_ok then 'PASS  6 storage: unknown geometry → storage NULL (never invented)'
                                       else 'FAIL  6 storage: unknown geometry → storage NULL' end));

    update public.water_assets set capacity_m3 = 5000, height_m = 5 where id = v_atank;
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_atank, v_d + 1, 2.5, v_admin);
    v_ok := (select storage_m3 = 2500 and percentage_full = 50
               from public.tank_level_readings where asset_id = v_atank and reading_date = v_d + 1);
    v_res := array_append(v_res, (case when v_ok then 'PASS  6 storage: linear fallback 2.5 m of 5 m × 5000 = 2500 m³ (50%)'
                                       else 'FAIL  6 storage: linear fallback  — got '
                                            || coalesce((select storage_m3::text from public.tank_level_readings
                                                          where asset_id = v_atank and reading_date = v_d + 1), 'null') end));

    insert into public.level_volume_curve (asset_id, level_m, volume_m3) values (v_atank, 0, 0), (v_atank, 2, 2000), (v_atank, 5, 6000);
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_atank, v_d + 2, 2.5, v_admin);
    v_ok := (select storage_m3 = 2666.67 from public.tank_level_readings where asset_id = v_atank and reading_date = v_d + 2);
    v_res := array_append(v_res, (case when v_ok then 'PASS  6 storage: curve interpolation at 2.5 m between (2,2000)-(5,6000) = 2666.67'
                                       else 'FAIL  6 storage: curve interpolation  — got '
                                            || coalesce((select storage_m3::text from public.tank_level_readings
                                                          where asset_id = v_atank and reading_date = v_d + 2), 'null') end));

    v_ok := public.get_storage_m3(v_atank, 1) = 1000;
    v_res := array_append(v_res, (case when v_ok then 'PASS  6 storage: the curve wins over the linear fallback (level 1 → 1000)'
                                       else 'FAIL  6 storage: the curve wins over the linear fallback  — got '
                                            || coalesce(public.get_storage_m3(v_atank, 1)::text, 'null') end));
  exception when others then
    v_res := array_append(v_res, 'FAIL  6 section crashed (its writes were rolled back)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------ 7. status propagation + alert
  -- The fixtures inserted a STOPPED reading for day+6 and THEN an OPERATING reading for
  -- day+3. The later-entered but older reading must not win.
  begin
    v_txt := (select current_status from public.water_assets where id = v_aw1);
    v_ok := v_txt = 'STOPPED';
    v_res := array_append(v_res, (case when v_ok then 'PASS  7 status: the asset follows the newest reading (STOPPED)'
                                       else 'FAIL  7 status: the asset follows the newest reading  — got ' || coalesce(v_txt, 'null') end));

    -- This check computes its own condition. It previously reused the alert result and so
    -- never tested anything.
    v_ok := v_txt = 'STOPPED'
            and exists (select 1 from public.readings r
                         where r.measurement_point_id = v_pw1 and r.covers_from = v_d + 3
                           and r.operational_status = 'OPERATING' and not r.is_superseded);
    v_res := array_append(v_res, (case when v_ok then 'PASS  7 status: a later-entered OLDER reading did not overwrite the status'
                                       else 'FAIL  7 status: a later-entered OLDER reading overwrote the status  — status='
                                            || coalesce(v_txt, 'null') end));

    v_ok := exists (select 1 from public.alerts where alert_type = 'SOURCE_STOPPED'
                      and asset_id = v_aw1 and reference_date = v_d + 6);
    v_res := array_append(v_res, (case when v_ok then 'PASS  7 status: SOURCE_STOPPED alert raised'
                                       else 'FAIL  7 status: SOURCE_STOPPED alert raised' end));

    v_ok := (select operational_status = 'OPERATING' from public.readings
              where measurement_point_id = v_pw1 and covers_from = v_d and not is_superseded);
    v_res := array_append(v_res, (case when v_ok then 'PASS  7 status: the per-day status stays on the reading (history preserved)'
                                       else 'FAIL  7 status: the per-day status stays on the reading' end));
  exception when others then
    v_res := array_append(v_res, 'FAIL  7 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------- 8. abnormal-reading flag
  begin
    v_ok := (select validation_status = 'FLAGGED' from public.readings where id = v_r3);
    v_res := array_append(v_res, (case when v_ok then 'PASS  8 abnormal: 5000 after eight days of 1000 → FLAGGED, not rejected'
                                       else 'FAIL  8 abnormal: expected FLAGGED  — got '
                                            || (select validation_status from public.readings where id = v_r3) end));

    v_ok := (select volume_m3 = 5000 from public.readings where id = v_r3);
    v_res := array_append(v_res, (case when v_ok then 'PASS  8 abnormal: the flagged value is stored unchanged'
                                       else 'FAIL  8 abnormal: the flagged value is stored unchanged' end));

    v_ok := exists (select 1 from public.alerts where alert_type = 'ABNORMAL_READING' and reading_id = v_r3);
    v_res := array_append(v_res, (case when v_ok then 'PASS  8 abnormal: ABNORMAL_READING alert raised'
                                       else 'FAIL  8 abnormal: ABNORMAL_READING alert raised' end));

    v_ok := (select bool_and(validation_status = 'OK') from public.readings
              where measurement_point_id = v_pw2 and covers_from between v_d + 10 and v_d + 17);
    v_res := array_append(v_res, (case when v_ok then 'PASS  8 abnormal: normal values are not flagged'
                                       else 'FAIL  8 abnormal: normal values are not flagged' end));
  exception when others then
    v_res := array_append(v_res, 'FAIL  8 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------- 9. management scope (positive control)
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

    -- scoped to the test prefix: the size of the real catalogue is irrelevant
    select count(*) into v_n from public.measurement_points where code like 'ZZT-%';
    v_ok := v_n = 13;   -- 7 wells + 2 connections + inlet + outlet + provider + placeholder
    v_res := array_append(v_res, (case when v_ok then 'PASS  9 admin: sees all 13 test measurement points'
                                       else 'FAIL  9 admin: sees all 13 test measurement points  — got ' || v_n end));

    select count(*) into v_n from public.alerts
     where status = 'OPEN'
       and asset_id in (select id from public.water_assets where code like 'ZZT-%');
    v_ok := v_n >= 4;
    v_res := array_append(v_res, (case when v_ok then 'PASS  9 admin: sees the 4 alerts raised on the test assets'
                                       else 'FAIL  9 admin: sees the 4 alerts raised on the test assets  — got ' || v_n end));

    update public.readings set validation_status = 'REVIEWED', validation_notes = 'checked' where id = v_r3;
    get diagnostics v_n = row_count;
    v_ok := v_n = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  9 admin: may update validation fields (1 row)'
                                       else 'FAIL  9 admin: may update validation fields  — rows=' || v_n end));

    begin
      update public.readings set volume_m3 = 1 where id = v_r3;
      v_res := array_append(v_res, 'FAIL  9 admin: still cannot edit the volume (immutability)  — was allowed');
    exception when others then
      v_res := array_append(v_res, 'PASS  9 admin: still cannot edit the volume (immutability)');
    end;

    select count(*) into v_n from public.audit_logs;
    v_ok := v_n > 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  9 admin: reads audit_logs (>0)'
                                       else 'FAIL  9 admin: reads audit_logs (>0)  — got ' || v_n end));

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_res := array_append(v_res, 'FAIL  9 section crashed (its writes were rolled back)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------- 10. non-daily points and the derived entry task list
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

    v_ok := (select not expects_daily_reading from public.measurement_points where id = v_psp);
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 providers: a service-provider meter expects no daily reading'
                                       else 'FAIL  10 providers: a service-provider meter expects no daily reading' end));

    select count(*) into v_n from public.balance_zone_members where measurement_point_id = v_psp;
    v_ok := v_n = 0;
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 providers: it is in no balance zone (the difference stays unexplained)'
                                       else 'FAIL  10 providers: it leaked into a balance zone  — ' || v_n || ' membership(s)' end));

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
      values (v_psp, v_d, v_d + 29, 12000, 'ESTIMATE', v_admin);
      v_ok := (select days_covered = 30 from public.readings
                where measurement_point_id = v_psp and covers_from = v_d);
      v_res := array_append(v_res, (case when v_ok then 'PASS  10 providers: a 30-day billing period is storable (days_covered = 30)'
                                         else 'FAIL  10 providers: a 30-day billing period is storable' end));
    exception when others then
      v_res := array_append(v_res, 'FAIL  10 providers: a 30-day billing period is storable  — ' || sqlstate || ' ' || sqlerrm);
    end;

    select * into v_bal from public.calculate_zone_balance(v_zone, v_d, v_d);
    v_ok := v_bal.inflow_m3 = 4450 and v_bal.outflow_measured_m3 = 0 and v_bal.difference_m3 = 3450;
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 providers: the monthly row does not touch the daily balance'
                                       else 'FAIL  10 providers: the monthly row changed the daily balance  — inflow='
                                            || v_bal.inflow_m3 || ' outflow=' || v_bal.outflow_measured_m3 end));

    -- scoped to the test prefix, so operational points cannot change these counts
    select count(*) into v_n from public.get_daily_entry_tasks(v_d) where code like 'ZZT-%';
    v_ok := v_n = 11;
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 tasks: 11 daily test points listed (non-daily points excluded)'
                                       else 'FAIL  10 tasks: 11 daily test points listed  — got ' || v_n end));

    select count(*) into v_n from public.get_daily_entry_tasks(v_d)
     where code like 'ZZT-%' and reading_id is not null;
    v_ok := v_n = 7;
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 tasks: 7 already entered, 4 pending for that day'
                                       else 'FAIL  10 tasks: 7 already entered  — got ' || v_n end));

    v_ok := (select volume_m3 = 1250 from public.get_daily_entry_tasks(v_d)
              where measurement_point_id = v_pw1);
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 tasks: an entered point carries the CORRECTED volume (1250)'
                                       else 'FAIL  10 tasks: an entered point carries the corrected volume' end));

    v_ok := not exists (select 1 from public.get_daily_entry_tasks(v_d) where measurement_point_id = v_psp);
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 tasks: the non-daily point never reaches the task list'
                                       else 'FAIL  10 tasks: a non-daily point reached the task list' end));

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_field, 'role', 'authenticated')::text, true);
    select count(*) into v_n from public.get_daily_entry_tasks(v_d);
    v_ok := v_n = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 tasks: the field worker sees only their 1 assigned point'
                                       else 'FAIL  10 tasks: the field worker sees only their 1 assigned point  — got ' || v_n end));
    v_ok := (select is_assigned from public.get_daily_entry_tasks(v_d) limit 1);
    v_res := array_append(v_res, (case when v_ok then 'PASS  10 tasks: is_assigned reads true for the field worker'
                                       else 'FAIL  10 tasks: is_assigned reads true for the field worker' end));
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_res := array_append(v_res, 'FAIL  10 section crashed (its writes were rolled back)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------- 11. Stage 5: asset management write path (0017/0018)
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

    begin
      v_new_asset := public.upsert_water_asset(
        null, 'zzt-valve', 'محبس اختبار', null, 'VALVE', null, v_area, 'OPERATING',
        null, null, null, null, null, null, null, null, null, null);
      v_res := array_append(v_res, 'PASS  11 types: a future asset type (VALVE) is accepted');
    exception when others then
      v_res := array_append(v_res, 'FAIL  11 types: a future asset type (VALVE)  — ' || sqlstate || ' ' || sqlerrm);
    end;

    v_ok := (select code = 'ZZT-VALVE' from public.water_assets where id = v_new_asset);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 assets: the code is normalised to upper case'
                                       else 'FAIL  11 assets: the code is normalised to upper case' end));

    v_ok := (select geom is null from public.water_assets where id = v_new_asset);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 assets: no coordinates → geometry stays NULL (never invented)'
                                       else 'FAIL  11 assets: no coordinates → geometry stays NULL' end));

    begin
      perform public.upsert_water_asset(
        null, 'ZZT-HALF', 'إحداثية ناقصة', null, 'VALVE', null, v_area, 'OPERATING',
        35.1, null, null, null, null, null, null, null, null, null);
      v_res := array_append(v_res, 'FAIL  11 assets: half a coordinate pair refused  — was accepted');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '22023' then 'PASS  11 assets: half a coordinate pair refused (22023)'
                                         else 'FAIL  11 assets: half a coordinate pair  — wrong error ' || sqlstate end));
    end;

    begin
      perform public.upsert_water_asset(
        null, 'ZZT-BADLL', 'إحداثية خارج المدى', null, 'VALVE', null, v_area, 'OPERATING',
        999, 999, null, null, null, null, null, null, null, null);
      v_res := array_append(v_res, 'FAIL  11 assets: out-of-range coordinates refused  — were accepted');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '22023' then 'PASS  11 assets: out-of-range coordinates refused (22023)'
                                         else 'FAIL  11 assets: out-of-range coordinates  — wrong error ' || sqlstate end));
    end;

    perform public.upsert_water_asset(
      v_new_asset, 'ZZT-VALVE', 'محبس اختبار معدّل', 'Test valve', 'VALVE', null, v_area, 'MAINTENANCE',
      35.155, 31.595, null, null, null, null, date '2018-01-01', null, null, null);
    v_ok := (select name_ar = 'محبس اختبار معدّل' and current_status = 'MAINTENANCE' and geom is not null
               from public.water_assets where id = v_new_asset);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 assets: update applies, coordinates can be added later'
                                       else 'FAIL  11 assets: update applies, coordinates can be added later' end));

    v_ok := (select round(longitude::numeric, 3) = 35.155 and round(latitude::numeric, 3) = 31.595
               from public.get_asset_catalogue(true) where id = v_new_asset);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 assets: the catalogue reads longitude/latitude back correctly'
                                       else 'FAIL  11 assets: the catalogue reads longitude/latitude back' end));

    begin
      v_new_point := public.upsert_measurement_point(
        null, 'zzt-consumer', 'عداد مشترك اختبار', null, 'CONSUMER_METER',
        v_new_asset, null, v_area, false, true);
      v_res := array_append(v_res, 'PASS  11 types: a future point type (CONSUMER_METER) is accepted');
    exception when others then
      v_res := array_append(v_res, 'FAIL  11 types: a future point type (CONSUMER_METER)  — ' || sqlstate || ' ' || sqlerrm);
    end;

    begin
      perform public.upsert_measurement_point(
        null, 'ZZT-ORPHAN', 'نقطة بلا أصل', null, 'SOURCE_METER', null, null, null, true, true);
      v_res := array_append(v_res, 'FAIL  11 points: a point with neither asset nor path refused  — was accepted');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate in ('22023','23514') then 'PASS  11 points: a point with neither asset nor path refused'
                                         else 'FAIL  11 points: orphan point  — wrong error ' || sqlstate end));
    end;

    perform public.upsert_water_path(null, v_new_asset, v_atank, 'PIPELINE', 5, 'خط اختبار', null, v_d, null, null);
    v_ok := (select count(*) from public.get_asset_paths(v_new_asset) where direction = 'OUT') = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 paths: a new path appears on the asset as outgoing'
                                       else 'FAIL  11 paths: a new path appears on the asset as outgoing' end));

    v_ok := (select count(*) from public.get_asset_paths(v_atank)
              where direction = 'IN' and other_asset_id = v_new_asset) = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 paths: the same path appears on the far asset as incoming'
                                       else 'FAIL  11 paths: the same path appears on the far asset as incoming' end));

    begin
      perform public.upsert_water_path(null, v_new_asset, v_new_asset, 'PIPELINE', 1, null, null, v_d, null, null);
      v_res := array_append(v_res, 'FAIL  11 paths: a self-loop refused  — was accepted');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate in ('22023','23514') then 'PASS  11 paths: a self-loop refused'
                                         else 'FAIL  11 paths: self-loop  — wrong error ' || sqlstate end));
    end;

    perform public.retire_water_asset(v_new_asset, date '2021-03-01', 'STOPPED', 'خرج من الخدمة للاختبار');
    v_ok := (select operational_end_date = date '2021-03-01' and current_status = 'STOPPED'
               from public.water_assets where id = v_new_asset);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 retire: end date and status set, row kept'
                                       else 'FAIL  11 retire: end date and status set' end));

    v_ok := (select is_retired from public.get_asset_catalogue(true) where id = v_new_asset);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 retire: the catalogue marks it retired'
                                       else 'FAIL  11 retire: the catalogue marks it retired' end));

    v_ok := not exists (select 1 from public.get_asset_catalogue(false) where id = v_new_asset);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 retire: it drops out of the active-only catalogue'
                                       else 'FAIL  11 retire: it drops out of the active-only catalogue' end));

    begin
      delete from public.water_assets where id = v_new_asset;
      v_res := array_append(v_res, 'FAIL  11 retire: DELETE on an asset refused  — the delete succeeded');
    exception when others then
      v_res := array_append(v_res, 'PASS  11 retire: DELETE on an asset refused (' || sqlstate || ')');
    end;

    perform public.reinstate_water_asset(v_new_asset, 'OPERATING');
    v_ok := (select operational_end_date is null from public.water_assets where id = v_new_asset);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 retire: reinstating clears the end date'
                                       else 'FAIL  11 retire: reinstating clears the end date' end));

    -- placeholder inventory, asserted on the test's own rows only
    v_ok := exists (select 1 from public.get_placeholder_rows() where id = v_atmp)
            and exists (select 1 from public.get_placeholder_rows() where id = v_ptmp);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 placeholders: a TMP-coded asset and its point are listed'
                                       else 'FAIL  11 placeholders: a TMP-coded asset and its point are listed' end));

    v_ok := not exists (select 1 from public.get_placeholder_rows() where id in (v_aw1, v_new_asset));
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 placeholders: assets with a real code are not listed'
                                       else 'FAIL  11 placeholders: an asset with a real code was listed' end));

    v_ok := (select is_placeholder from public.get_asset_catalogue(true) where id = v_atmp)
            and not (select is_placeholder from public.get_asset_catalogue(true) where id = v_aw1);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 placeholders: the catalogue flag matches the inventory'
                                       else 'FAIL  11 placeholders: the catalogue flag matches the inventory' end));

    -- renaming a placeholder keeps its readings and clears the flag
    select reading_count into v_n from public.get_asset_catalogue(true) where id = v_atmp;
    perform public.upsert_water_asset(
      v_atmp, 'ZZT-REAL-1', 'بئر حقيقي', 'Real well', 'WELL', 'GROUNDWATER', v_area, 'OPERATING',
      35.16, 31.52, null, null, null, null, null, null, null, null);
    v_ok := (select not is_placeholder and reading_count = v_n
               from public.get_asset_catalogue(true) where id = v_atmp);
    v_res := array_append(v_res, (case when v_ok then 'PASS  11 placeholders: renaming keeps every reading and clears the flag'
                                       else 'FAIL  11 placeholders: renaming lost readings or kept the flag' end));

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);

    -- a field worker may not create or retire assets
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_field, 'role', 'authenticated')::text, true);
    begin
      perform public.upsert_water_asset(
        null, 'ZZT-HACK2', 'اختراق', null, 'WELL', 'GROUNDWATER', null, 'OPERATING',
        null, null, null, null, null, null, null, null, null, null);
      v_res := array_append(v_res, 'FAIL  11 rls: the field team cannot create assets through the function  — it worked');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '42501' then 'PASS  11 rls: the field team cannot create assets through the function (42501)'
                                         else 'FAIL  11 rls: field-team asset creation  — wrong error ' || sqlstate end));
    end;
    begin
      perform public.retire_water_asset(v_atank, v_d, 'STOPPED', null);
      v_res := array_append(v_res, 'FAIL  11 rls: the field team cannot retire an asset  — it worked');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '42501' then 'PASS  11 rls: the field team cannot retire an asset (42501)'
                                         else 'FAIL  11 rls: field-team retire  — wrong error ' || sqlstate end));
    end;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_res := array_append(v_res, 'FAIL  11 section crashed (its writes were rolled back)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------- 12. anti double-count guards and explained zeros (0019)
  begin
    -- a main meter fed from a neighbouring system must be able to say which supply it is
    begin
      insert into public.water_assets (code, name_ar, asset_type, supply_type, area_id)
      values ('ZZT-MM-1', 'عداد رئيسي اختبار', 'MAIN_METER', 'ISRAELI', v_area);
      v_res := array_append(v_res, 'PASS  12 supply: a MAIN_METER may carry ISRAELI');
    exception when others then
      v_res := array_append(v_res, 'FAIL  12 supply: a MAIN_METER may carry ISRAELI  — ' || sqlstate || ' ' || sqlerrm);
    end;

    begin
      insert into public.water_assets (code, name_ar, asset_type, supply_type, area_id)
      values ('ZZT-TANK-BAD', 'خزان بنوع مياه', 'TANK', 'ISRAELI', v_area);
      v_res := array_append(v_res, 'FAIL  12 supply: a TANK must not carry a supply type  — it was accepted');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '23514' then 'PASS  12 supply: a TANK still may not carry a supply type (23514)'
                                         else 'FAIL  12 supply: TANK supply type  — wrong error ' || sqlstate end));
    end;

    -- a point measured upstream of the tank may never join a zone
    insert into public.measurement_points (code, name_ar, point_type, asset_id, area_id,
                                           expects_daily_reading, excluded_from_balance)
    values ('ZZT-MP-UPSTREAM', 'عداد قبل الخزان', 'SOURCE_METER', v_aw1, v_area, true, true)
    returning id into v_new_point;

    v_ok := (select excluded_from_balance from public.measurement_points where id = v_new_point);
    v_res := array_append(v_res, (case when v_ok then 'PASS  12 upstream: the point is marked excluded_from_balance'
                                       else 'FAIL  12 upstream: the point is marked excluded_from_balance' end));

    begin
      insert into public.balance_zone_members (zone_id, measurement_point_id, role, measurement_quality)
      values (v_zone, v_new_point, 'INFLOW', 'MEASURED');
      v_res := array_append(v_res, 'FAIL  12 upstream: an excluded point was allowed into a balance zone');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '23514' then 'PASS  12 upstream: an excluded point is refused by any balance zone (23514)'
                                         else 'FAIL  12 upstream: excluded point  — wrong error ' || sqlstate || ' ' || sqlerrm end));
    end;

    -- it still appears in the daily task list: we want a record of what it pumped
    select count(*) into v_n from public.get_daily_entry_tasks(v_d)
     where measurement_point_id = v_new_point;
    v_ok := v_n = 1;
    v_res := array_append(v_res, (case when v_ok then 'PASS  12 upstream: it is still read daily, only kept out of the balance'
                                       else 'FAIL  12 upstream: it should still appear in the task list  — got ' || v_n end));

    -- one INFLOW membership per point, across every zone
    insert into public.balance_zones (code, name_ar) values ('ZZT-ZONE-2', 'منطقة موازنة اختبار 2')
    returning id into v_new_asset;   -- reused as a scratch uuid holder

    begin
      insert into public.balance_zone_members (zone_id, measurement_point_id, role, measurement_quality)
      values (v_new_asset, v_pw1, 'INFLOW', 'MEASURED');
      v_res := array_append(v_res, 'FAIL  12 double count: the same point was allowed as INFLOW in two zones');
    exception when others then
      v_res := array_append(v_res, (case when sqlstate = '23505' then 'PASS  12 double count: a point may be INFLOW in only one zone (23505)'
                                         else 'FAIL  12 double count  — wrong error ' || sqlstate || ' ' || sqlerrm end));
    end;

    -- the legitimate chain: ARRIVAL of one zone becomes INFLOW of the next
    begin
      insert into public.balance_zone_members (zone_id, measurement_point_id, role, measurement_quality)
      values (v_new_asset, v_pin, 'INFLOW', 'MEASURED');
      v_res := array_append(v_res, 'PASS  12 chain: an ARRIVAL point may be the INFLOW of the next zone');
    exception when others then
      v_res := array_append(v_res, 'FAIL  12 chain: an ARRIVAL point may be the INFLOW of the next zone  — '
                                   || sqlstate || ' ' || sqlerrm);
    end;

    -- an explained zero is not an anomaly; an unexplained zero still is
    insert into public.measurement_points (code, name_ar, point_type, asset_id, area_id, expects_daily_reading)
    values ('ZZT-MP-INTERMITTENT', 'عداد بئر متقطع', 'SOURCE_METER', v_aw1, v_area, true)
    returning id into v_new_point;
    for v_i in 30..37 loop
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3,
                                   entry_basis, operational_status, entered_by)
      values (v_new_point, v_d + v_i, v_d + v_i, 1000, 'METER_DISPLAY', 'OPERATING', v_admin);
    end loop;
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3,
                                 entry_basis, operational_status, entered_by)
    values (v_new_point, v_d + 38, v_d + 38, 0, 'METER_DISPLAY', 'STOPPED', v_admin);
    v_ok := (select validation_status = 'OK' from public.readings
              where measurement_point_id = v_new_point and covers_from = v_d + 38);
    v_res := array_append(v_res, (case when v_ok then 'PASS  12 zeros: a zero with a STOPPED status is not flagged'
                                       else 'FAIL  12 zeros: a zero with a STOPPED status was flagged' end));

    v_ok := not exists (select 1 from public.alerts
                         where alert_type = 'ABNORMAL_READING'
                           and measurement_point_id = v_new_point and reference_date = v_d + 38);
    v_res := array_append(v_res, (case when v_ok then 'PASS  12 zeros: no ABNORMAL_READING alert for an explained zero'
                                       else 'FAIL  12 zeros: an explained zero raised an alert' end));

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3,
                                 entry_basis, operational_status, entered_by)
    values (v_new_point, v_d + 39, v_d + 39, 0, 'METER_DISPLAY', 'OPERATING', v_admin);
    v_ok := (select validation_status = 'FLAGGED' from public.readings
              where measurement_point_id = v_new_point and covers_from = v_d + 39);
    v_res := array_append(v_res, (case when v_ok then 'PASS  12 zeros: a zero while claiming to OPERATE is still flagged'
                                       else 'FAIL  12 zeros: a zero while claiming to OPERATE was not flagged  — got '
                                            || (select validation_status from public.readings
                                                 where measurement_point_id = v_new_point and covers_from = v_d + 39) end));

    -- the stopped day must not drag the baseline down
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3,
                                 entry_basis, operational_status, entered_by)
    values (v_new_point, v_d + 40, v_d + 40, 1000, 'METER_DISPLAY', 'OPERATING', v_admin);
    v_ok := (select validation_status = 'OK' from public.readings
              where measurement_point_id = v_new_point and covers_from = v_d + 40);
    v_res := array_append(v_res, (case when v_ok then 'PASS  12 zeros: an ordinary day after downtime is not flagged'
                                       else 'FAIL  12 zeros: an ordinary day after downtime was flagged' end));
  exception when others then
    v_res := array_append(v_res, 'FAIL  12 section crashed (its writes were rolled back)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ==================================== REPORT ======================================
  -- A crashed section means its checks never ran — that is missing coverage, not a pass.
  v_total := coalesce(array_length(v_res, 1), 0);
  select count(*) into v_fail  from unnest(v_res) x where x like 'FAIL%';
  select count(*) into v_crash from unnest(v_res) x where x like 'FAIL%section crashed%';

  raise exception E'TEST REPORT — % failed of % checks (% crashed sections). All test data rolled back (expected).\n%',
    v_fail, v_total, v_crash, array_to_string(v_res, E'\n');
end;
$$;
