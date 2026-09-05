-- =============================================================================
-- FUNCTIONAL TEST — run in the Supabase SQL Editor AFTER migrations 0001–0012.
--
-- Everything runs inside one DO block and is ROLLED BACK at the end by design:
-- the final RAISE EXCEPTION carries the report, so the editor shows a red box whose
-- message starts with "TEST REPORT". That is the expected outcome. No test data,
-- no test user and no alerts survive. Read the PASS/FAIL lines in the message.
--
-- Covers:  1 supersede + immutability + audit     2 pass-through mismatch alert
--          3 zone balance with incomplete data     4 negative RLS as FIELD_TEAM
--          5 inactive user scope                   6 storage curve / linear fallback
--          7 status propagation + SOURCE_STOPPED   8 abnormal-reading flag
--          9 management scope (positive control)
-- =============================================================================
do $$
declare
  v_admin  uuid;
  v_field  uuid := gen_random_uuid();
  v_zone   uuid;
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_p4 uuid; v_p5 uuid;
  v_in uuid; v_out uuid; v_tank uuid; v_well1 uuid;
  v_d      date := date '2019-06-01';     -- far in the past: never collides with live data
  v_r1 uuid; v_r2 uuid; v_r3 uuid;
  v_old    public.readings%rowtype;
  v_bal    record;
  v_n      int;
  v_num    numeric;
  v_txt    text;
  v_total  int;
  v_fail   int;
  v_report text;
begin
  execute 'create temp table t_results (seq serial, name text, passed boolean, detail text) on commit drop';

  -- --------------------------------------------------------------------- setup
  select id into v_admin from auth.users where lower(email) = 'ehabomear@gmail.com';
  select id into v_zone  from public.balance_zones where code = 'SAEER-TRANSIT';
  select id into v_p1  from public.measurement_points where code = 'MP-W-TMP-01';
  select id into v_p2  from public.measurement_points where code = 'MP-W-TMP-02';
  select id into v_p3  from public.measurement_points where code = 'MP-W-TMP-03';
  select id into v_p4  from public.measurement_points where code = 'MP-W-TMP-04';
  select id into v_p5  from public.measurement_points where code = 'MP-W-TMP-05';
  select id into v_in  from public.measurement_points where code = 'MP-TNK-SAEER-IN';
  select id into v_out from public.measurement_points where code = 'MP-TNK-SAEER-OUT';
  select id into v_tank  from public.water_assets where code = 'TNK-SAEER';
  select id into v_well1 from public.water_assets where code = 'W-TMP-01';

  insert into t_results (name, passed, detail) values
    ('setup: admin user found', v_admin is not null, null),
    ('setup: SAEER-TRANSIT zone found', v_zone is not null, null),
    ('setup: Saeer inlet/outlet points found', v_in is not null and v_out is not null, null);

  -- A throw-away FIELD_TEAM user (rolled back with everything else)
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values (v_field, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          'field.test@example.invalid', extensions.crypt('Test-1234', extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', '{"full_name":"Field Tester"}', now(), now(),
          '', '', '', '');

  select count(*) into v_n from public.profiles where id = v_field;
  insert into t_results (name, passed, detail) values
    ('setup: profile auto-created by auth trigger (inactive)', v_n = 1
       and (select not is_active from public.profiles where id = v_field), null);

  update public.profiles set is_active = true, role = 'FIELD_TEAM', full_name_ar = 'عامل حقلي تجريبي'
   where id = v_field;
  insert into public.assignments (user_id, measurement_point_id, active_from)
  values (v_field, v_p1, date '2019-01-01');

  -- ------------------------------------------------- 1. supersede + immutability
  begin
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_p1, v_d, v_d, 1200, 'METER_DISPLAY', 'OPERATING', v_admin) returning id into v_r1;

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by, supersedes_id, notes)
    values (v_p1, v_d, v_d, 1250, 'METER_DISPLAY', 'OPERATING', v_admin, v_r1, 'تصحيح') returning id into v_r2;

    select * into v_old from public.readings where id = v_r1;
    insert into t_results (name, passed, detail) values
      ('1 supersede: original marked is_superseded', v_old.is_superseded, null),
      ('1 supersede: original volume intact (1200)', v_old.volume_m3 = 1200, 'got ' || v_old.volume_m3),
      ('1 supersede: correction is the only active row for the day',
         (select count(*) from public.readings where measurement_point_id = v_p1 and covers_from = v_d and not is_superseded) = 1, null),
      ('1 supersede: correction points at original', (select supersedes_id = v_r1 from public.readings where id = v_r2), null);

    begin
      update public.readings set volume_m3 = 999 where id = v_r1;
      insert into t_results (name, passed, detail) values ('1 immutability: UPDATE volume refused', false, 'update was allowed');
    exception when others then
      insert into t_results (name, passed, detail) values ('1 immutability: UPDATE volume refused', true, sqlerrm);
    end;

    begin
      delete from public.readings where id = v_r1;
      insert into t_results (name, passed, detail) values ('1 immutability: DELETE refused', false, 'delete was allowed');
    exception when others then
      insert into t_results (name, passed, detail) values ('1 immutability: DELETE refused', true, sqlerrm);
    end;

    -- re-superseding an already superseded row must fail
    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by, supersedes_id)
      values (v_p1, v_d, v_d, 1, 'ESTIMATE', v_admin, v_r1);
      insert into t_results (name, passed, detail) values ('1 supersede: double supersede refused', false, 'was allowed');
    exception when others then
      insert into t_results (name, passed, detail) values ('1 supersede: double supersede refused', true, sqlerrm);
    end;

    select count(*) into v_n from public.audit_logs where entity_table = 'readings' and entity_id in (v_r1, v_r2);
    insert into t_results (name, passed, detail) values
      ('1 audit: insert r1, insert r2, update r1 logged (>=3)', v_n >= 3, 'rows=' || v_n);
    insert into t_results (name, passed, detail) values
      ('1 audit: previous value recoverable from audit_logs',
         exists (select 1 from public.audit_logs where entity_id = v_r1 and action = 'UPDATE'
                   and (old_value ->> 'is_superseded')::boolean = false and (new_value ->> 'is_superseded')::boolean = true), null);
  exception when others then
    insert into t_results (name, passed, detail) values ('1 section crashed', false, sqlerrm);
  end;

  -- ------------------------------------------------------ 2. pass-through check
  begin
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_in,  v_d, v_d, 1000, 'METER_DIFF', v_admin);
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_out, v_d, v_d,  900, 'METER_DIFF', v_admin);

    insert into t_results (name, passed, detail) values
      ('2 pass-through: 10% mismatch raised PASS_THROUGH_MISMATCH',
         exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                   and asset_id = v_tank and reference_date = v_d and status = 'OPEN'), null);

    select (details ->> 'difference_pct')::numeric into v_num
    from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH' and asset_id = v_tank and reference_date = v_d;
    insert into t_results (name, passed, detail) values
      ('2 pass-through: alert stores inputs (difference_pct≈10, threshold 3)',
         v_num between 9.9 and 10.1
         and (select (details ->> 'threshold_pct')::numeric = 3 and (details ->> 'inlet_m3')::numeric = 1000
                from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH' and asset_id = v_tank and reference_date = v_d),
         'difference_pct=' || coalesce(v_num::text, 'null'));

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_in,  v_d + 1, v_d + 1, 1000, 'METER_DIFF', v_admin);
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_out, v_d + 1, v_d + 1,  985, 'METER_DIFF', v_admin);
    insert into t_results (name, passed, detail) values
      ('2 pass-through: 1.5% mismatch raises nothing',
         not exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                       and asset_id = v_tank and reference_date = v_d + 1), null);

    -- threshold is data: tighten to 1% for this asset, next day at 1.5% must alert
    update public.water_assets set pass_through_tolerance_pct = 1 where id = v_tank;
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_in,  v_d + 2, v_d + 2, 1000, 'METER_DIFF', v_admin);
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_out, v_d + 2, v_d + 2,  985, 'METER_DIFF', v_admin);
    insert into t_results (name, passed, detail) values
      ('2 pass-through: per-asset threshold override (1%) applied',
         exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                   and asset_id = v_tank and reference_date = v_d + 2), null);
  exception when others then
    insert into t_results (name, passed, detail) values ('2 section crashed', false, sqlerrm);
  end;

  -- ------------------------------------------- 3. balance with incomplete data
  begin
    -- Day v_d: sources 1..5 reported (1250 + 4×800), sources 6,7, IC1, IC2 missing; inlet 1000.
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_p2, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_p3, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_p4, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_p5, v_d, v_d, 800, 'METER_DISPLAY', v_admin);

    select * into v_bal from public.calculate_zone_balance(v_zone, v_d, v_d);
    insert into t_results (name, passed, detail) values
      ('3 balance: inflow = 4450',              v_bal.inflow_m3 = 4450,            'got ' || v_bal.inflow_m3),
      ('3 balance: groundwater 4450 / israeli 0', v_bal.inflow_groundwater_m3 = 4450 and v_bal.inflow_israeli_m3 = 0, null),
      ('3 balance: arrival = 1000',             v_bal.arrival_m3 = 1000,           'got ' || v_bal.arrival_m3),
      ('3 balance: measured outflow = 0',       v_bal.outflow_measured_m3 = 0,     null),
      ('3 balance: difference (unexplained) = 3450', v_bal.difference_m3 = 3450,   'got ' || v_bal.difference_m3),
      ('3 balance: no storage term for transit zone', v_bal.storage_change_m3 = 0 and v_bal.storage_complete, null),
      ('3 completeness: points_expected = 10',  v_bal.points_expected = 10,        'got ' || v_bal.points_expected),
      ('3 completeness: points_complete = 6',   v_bal.points_complete = 6,         'got ' || v_bal.points_complete),
      ('3 completeness: point-days 6/10',       v_bal.point_days_reported = 6 and v_bal.point_days_expected = 10, null),
      ('3 sources: total 9, operating 1 (only W-TMP-01 carried a status)',
         v_bal.sources_total = 9 and v_bal.sources_operating = 1, format('total=%s operating=%s', v_bal.sources_total, v_bal.sources_operating)),
      ('3 by_role: INFLOW 5/9 complete', (v_bal.by_role -> 'INFLOW' ->> 'points_complete')::int = 5
                                          and (v_bal.by_role -> 'INFLOW' ->> 'points_expected')::int = 9, v_bal.by_role::text);

    select count(*) into v_n from public.get_missing_readings(v_d, v_d, null);
    insert into t_results (name, passed, detail) values
      ('3 missing readings: 4 of 11 daily points missing on day 1', v_n = 4, 'got ' || v_n);

    -- proration: a 2-day reading (600 m³) on p2 contributes 300 to each day
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_p2, v_d + 1, v_d + 2, 600, 'METER_DIFF', v_admin);
    select * into v_bal from public.calculate_zone_balance(v_zone, v_d + 1, v_d + 1);
    insert into t_results (name, passed, detail) values
      ('3 proration: 2-day reading contributes half to a single day', v_bal.inflow_m3 = 300, 'got ' || v_bal.inflow_m3),
      ('3 proration: the 2-day reading counts as coverage for day 2', v_bal.points_complete = 2, 'got ' || v_bal.points_complete);

    -- week range: 3 days, expected point-days = 30
    select * into v_bal from public.calculate_zone_balance(v_zone, v_d, v_d + 2);
    insert into t_results (name, passed, detail) values
      ('3 range: 3-day window → 30 point-days expected, arrival 3000', v_bal.point_days_expected = 30 and v_bal.arrival_m3 = 3000,
         format('pd=%s arrival=%s', v_bal.point_days_expected, v_bal.arrival_m3));
  exception when others then
    insert into t_results (name, passed, detail) values ('3 section crashed', false, sqlerrm);
  end;

  -- ------------------------------------------------ 4. negative RLS: FIELD_TEAM
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_field, 'role', 'authenticated')::text, true);

    insert into t_results (name, passed, detail) values
      ('4 rls: impersonation works (auth.uid() = field user)', auth.uid() = v_field, null),
      ('4 rls: app.user_role() = FIELD_TEAM', app.user_role() = 'FIELD_TEAM', app.user_role());

    select count(*) into v_n from public.measurement_points;
    insert into t_results (name, passed, detail) values ('4 rls: sees only the 1 assigned point (of 11)', v_n = 1, 'got ' || v_n);

    select count(*) into v_n from public.readings where measurement_point_id = v_p2;
    insert into t_results (name, passed, detail) values ('4 rls: readings of unassigned point hidden (0)', v_n = 0, 'got ' || v_n);

    select count(*) into v_n from public.readings where measurement_point_id = v_p1;
    insert into t_results (name, passed, detail) values ('4 rls: readings of assigned point visible (2 incl. superseded)', v_n = 2, 'got ' || v_n);

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis)
      values (v_p2, v_d + 5, v_d + 5, 10, 'ESTIMATE');
      insert into t_results (name, passed, detail) values ('4 rls: INSERT on unassigned point refused (42501)', false, 'insert was allowed');
    exception when others then
      insert into t_results (name, passed, detail) values ('4 rls: INSERT on unassigned point refused (42501)', sqlstate = '42501', sqlstate || ' ' || sqlerrm);
    end;

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
      values (v_p1, v_d + 5, v_d + 5, 10, 'ESTIMATE', v_admin);   -- forging entered_by
      insert into t_results (name, passed, detail) values ('4 rls: INSERT with forged entered_by refused', false, 'insert was allowed');
    exception when others then
      insert into t_results (name, passed, detail) values ('4 rls: INSERT with forged entered_by refused', sqlstate = '42501', sqlstate || ' ' || sqlerrm);
    end;

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis)
    values (v_p1, v_d + 5, v_d + 5, 10, 'ESTIMATE') returning id into v_r3;
    insert into t_results (name, passed, detail) values
      ('4 rls: INSERT on assigned point allowed, entered_by = self',
         (select entered_by = v_field from public.readings where id = v_r3), null);

    update public.readings set validation_notes = 'x' where id = v_r3;
    get diagnostics v_n = row_count;
    insert into t_results (name, passed, detail) values ('4 rls: UPDATE by field team affects 0 rows', v_n = 0, 'rows=' || v_n);

    begin
      delete from public.readings where id = v_r3;
      get diagnostics v_n = row_count;
      insert into t_results (name, passed, detail) values ('4 rls: DELETE by field team refused', v_n = 0, 'rows=' || v_n);
    exception when others then
      insert into t_results (name, passed, detail) values ('4 rls: DELETE by field team refused', true, sqlstate || ' ' || sqlerrm);
    end;

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, supersedes_id)
    values (v_p1, v_d + 5, v_d + 5, 12, 'ESTIMATE', v_r3);
    insert into t_results (name, passed, detail) values
      ('4 rls: field team corrects own reading via supersede (no UPDATE right needed)',
         (select is_superseded from public.readings where id = v_r3), null);

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, supersedes_id)
      values (v_p1, v_d + 5, v_d + 5, 13, 'ESTIMATE', v_r1);   -- superseding a row on another day/point mismatch is a trigger error
      insert into t_results (name, passed, detail) values ('4 rls: supersede of already-superseded row refused', false, 'was allowed');
    exception when others then
      insert into t_results (name, passed, detail) values ('4 rls: supersede of already-superseded row refused', true, sqlstate);
    end;

    select count(*) into v_n from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH';
    insert into t_results (name, passed, detail) values ('4 rls: tank alerts hidden from field team (0)', v_n = 0, 'got ' || v_n);

    select count(*) into v_n from public.audit_logs;
    insert into t_results (name, passed, detail) values ('4 rls: audit_logs hidden from field team (0)', v_n = 0, 'got ' || v_n);

    select count(*) into v_n from public.profiles;
    insert into t_results (name, passed, detail) values ('4 rls: profiles → own row only (1)', v_n = 1, 'got ' || v_n);

    begin
      update public.profiles set role = 'SUPER_ADMIN' where id = v_field;
      get diagnostics v_n = row_count;
      insert into t_results (name, passed, detail) values ('4 rls: self-promotion to SUPER_ADMIN refused', v_n = 0, 'rows=' || v_n);
    exception when others then
      insert into t_results (name, passed, detail) values ('4 rls: self-promotion to SUPER_ADMIN refused', true, sqlstate || ' ' || sqlerrm);
    end;

    begin
      insert into public.water_assets (code, name_ar, asset_type, supply_type) values ('W-HACK', 'x', 'WELL', 'GROUNDWATER');
      insert into t_results (name, passed, detail) values ('4 rls: field team cannot create assets', false, 'was allowed');
    exception when others then
      insert into t_results (name, passed, detail) values ('4 rls: field team cannot create assets', sqlstate = '42501', sqlstate);
    end;

    begin
      update public.system_settings set value = '99' where key = 'pass_through_mismatch_pct';
      get diagnostics v_n = row_count;
      insert into t_results (name, passed, detail) values ('4 rls: field team cannot change thresholds', v_n = 0, 'rows=' || v_n);
    exception when others then
      insert into t_results (name, passed, detail) values ('4 rls: field team cannot change thresholds', true, sqlstate);
    end;

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    insert into t_results (name, passed, detail) values ('4 section crashed', false, sqlerrm);
  end;

  -- ------------------------------------------------------- 5. inactive user
  begin
    update public.profiles set is_active = false where id = v_field;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_field, 'role', 'authenticated')::text, true);

    select count(*) into v_n from public.profiles where id = auth.uid();
    insert into t_results (name, passed, detail) values ('5 inactive: own profile still readable (UI can explain state)', v_n = 1, 'got ' || v_n);
    insert into t_results (name, passed, detail) values ('5 inactive: is_active reads false', (select not is_active from public.profiles where id = auth.uid()), null);
    select count(*) into v_n from public.measurement_points;
    insert into t_results (name, passed, detail) values ('5 inactive: sees 0 measurement points', v_n = 0, 'got ' || v_n);
    insert into t_results (name, passed, detail) values ('5 inactive: app.user_role() is null', app.user_role() is null, coalesce(app.user_role(), 'null'));

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    update public.profiles set is_active = true where id = v_field;
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    insert into t_results (name, passed, detail) values ('5 section crashed', false, sqlerrm);
  end;

  -- ---------------------------------------------- 6. storage: curve / fallback
  begin
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_tank, v_d, 2.5, v_admin);
    insert into t_results (name, passed, detail) values
      ('6 storage: unknown geometry → storage NULL (never invented)',
         (select storage_m3 is null and percentage_full is null from public.tank_level_readings where asset_id = v_tank and reading_date = v_d), null);

    update public.water_assets set capacity_m3 = 5000, height_m = 5 where id = v_tank;
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_tank, v_d + 1, 2.5, v_admin);
    insert into t_results (name, passed, detail) values
      ('6 storage: linear fallback 2.5 m of 5 m × 5000 = 2500 m³ (50%)',
         (select storage_m3 = 2500 and percentage_full = 50 from public.tank_level_readings where asset_id = v_tank and reading_date = v_d + 1), null);

    insert into public.level_volume_curve (asset_id, level_m, volume_m3) values (v_tank, 0, 0), (v_tank, 2, 2000), (v_tank, 5, 6000);
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_tank, v_d + 2, 2.5, v_admin);
    insert into t_results (name, passed, detail) values
      ('6 storage: curve interpolation 2.5 m between (2,2000)-(5,6000) = 2666.67',
         (select storage_m3 = 2666.67 from public.tank_level_readings where asset_id = v_tank and reading_date = v_d + 2),
         (select 'got ' || storage_m3 from public.tank_level_readings where asset_id = v_tank and reading_date = v_d + 2));
    insert into t_results (name, passed, detail) values
      ('6 storage: get_storage_m3 direct call (level 1 → 1000)', public.get_storage_m3(v_tank, 1) = 1000, null);
  exception when others then
    insert into t_results (name, passed, detail) values ('6 section crashed', false, sqlerrm);
  end;

  -- ------------------------------------------ 7. status propagation + alert
  begin
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_p1, v_d + 6, v_d + 6, 0, 'ESTIMATE', 'STOPPED', v_admin);
    insert into t_results (name, passed, detail) values
      ('7 status: asset current_status follows latest reading (STOPPED)',
         (select current_status = 'STOPPED' from public.water_assets where id = v_well1), null),
      ('7 status: SOURCE_STOPPED alert raised',
         exists (select 1 from public.alerts where alert_type = 'SOURCE_STOPPED' and asset_id = v_well1 and reference_date = v_d + 6), null);
    -- an older reading must not overwrite a newer status
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_p1, v_d + 3, v_d + 3, 1100, 'METER_DISPLAY', 'OPERATING', v_admin);
    insert into t_results (name, passed, detail) values
      ('7 status: older reading does not overwrite newer status',
         (select current_status = 'STOPPED' from public.water_assets where id = v_well1), null);
  exception when others then
    insert into t_results (name, passed, detail) values ('7 section crashed', false, sqlerrm);
  end;

  -- ------------------------------------------------- 8. abnormal-reading flag
  begin
    for v_n in 10..17 loop
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
      values (v_p2, v_d + v_n, v_d + v_n, 1000, 'METER_DISPLAY', v_admin);
    end loop;
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_p2, v_d + 18, v_d + 18, 5000, 'METER_DISPLAY', v_admin) returning id into v_r3;
    insert into t_results (name, passed, detail) values
      ('8 abnormal: 5000 after 8×1000 → FLAGGED, not rejected',
         (select validation_status = 'FLAGGED' from public.readings where id = v_r3),
         (select validation_notes from public.readings where id = v_r3)),
      ('8 abnormal: ABNORMAL_READING alert raised',
         exists (select 1 from public.alerts where alert_type = 'ABNORMAL_READING' and reading_id = v_r3), null),
      ('8 abnormal: normal value is not flagged',
         (select bool_and(validation_status = 'OK') from public.readings where measurement_point_id = v_p2 and covers_from between v_d + 10 and v_d + 17), null);
  exception when others then
    insert into t_results (name, passed, detail) values ('8 section crashed', false, sqlerrm);
  end;

  -- ------------------------------------- 9. management scope (positive control)
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    select count(*) into v_n from public.measurement_points;
    insert into t_results (name, passed, detail) values ('9 admin: sees all 11 points', v_n = 11, 'got ' || v_n);
    select count(*) into v_n from public.alerts where status = 'OPEN';
    insert into t_results (name, passed, detail) values ('9 admin: sees open alerts (>=4)', v_n >= 4, 'got ' || v_n);
    update public.readings set validation_status = 'REVIEWED', validation_notes = 'checked' where id = v_r3;
    get diagnostics v_n = row_count;
    insert into t_results (name, passed, detail) values ('9 admin: may update validation fields (1 row)', v_n = 1, 'rows=' || v_n);
    begin
      update public.readings set volume_m3 = 1 where id = v_r3;
      insert into t_results (name, passed, detail) values ('9 admin: still cannot edit volume (immutability)', false, 'was allowed');
    exception when others then
      insert into t_results (name, passed, detail) values ('9 admin: still cannot edit volume (immutability)', true, sqlerrm);
    end;
    select count(*) into v_n from public.audit_logs;
    insert into t_results (name, passed, detail) values ('9 admin: reads audit_logs (>0)', v_n > 0, 'got ' || v_n);
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    insert into t_results (name, passed, detail) values ('9 section crashed', false, sqlerrm);
  end;

  -- ---------------------------------------------------------------- report
  select count(*), count(*) filter (where not passed) into v_total, v_fail from t_results;
  select string_agg(format('%s  %s%s', case when passed then 'PASS' else 'FAIL' end, name,
                           case when passed then '' else coalesce('  — ' || detail, '') end), E'\n' order by seq)
    into v_report from t_results;

  raise exception E'TEST REPORT — % failed of % checks. All test data rolled back (expected).\n%',
    v_fail, v_total, v_report;
end;
$$;
