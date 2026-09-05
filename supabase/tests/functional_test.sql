-- =============================================================================
-- FUNCTIONAL TEST — run in the Supabase SQL Editor AFTER migrations 0001–0013
-- (0012 re-run last, after 0013).
--
-- Everything runs inside one DO block and is ROLLED BACK at the end by design:
-- the final RAISE EXCEPTION carries the report, so the editor shows a red box whose
-- message starts with "TEST REPORT". That is the expected outcome. No test data,
-- no test user and no alerts survive. Read the PASS/FAIL lines in the message.
--
-- Results are accumulated in a PL/pgSQL array variable, never in a table: sections 4,
-- 5 and 9 run under `set local role authenticated`, and a switched role has no write
-- privilege on a temp table owned by the session user. A variable has no ACL at all,
-- so recording a result can never fail for permission reasons.
--
-- Covers:  0 audit on tables without an `id` column   1 supersede + immutability + audit
--          2 pass-through mismatch alert              3 zone balance with incomplete data
--          4 negative RLS as FIELD_TEAM               5 inactive user scope
--          6 storage curve / linear fallback          7 status propagation + SOURCE_STOPPED
--          8 abnormal-reading flag                    9 management scope (positive control)
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
  v_res    text[] := '{}';               -- PASS/FAIL lines; immune to `set role`
  v_ok     boolean;
  v_total  int;
  v_fail   int;
  v_crash  int;
begin
  -- Recording pattern used below (two lines per check, detail evaluated only on failure):
  --   v_ok  := <condition>;
  --   v_res := v_res || (case when v_ok then 'PASS  <name>' else 'FAIL  <name>  — ' || <detail> end);

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

  v_ok  := v_admin is not null;
  v_res := v_res || (case when v_ok then 'PASS  setup: admin auth user found'
                          else 'FAIL  setup: admin auth user found  — ehabomear@gmail.com missing' end);
  v_ok  := v_zone is not null;
  v_res := v_res || (case when v_ok then 'PASS  setup: SAEER-TRANSIT zone found'
                          else 'FAIL  setup: SAEER-TRANSIT zone found  — run 0011' end);
  v_ok  := v_in is not null and v_out is not null;
  v_res := v_res || (case when v_ok then 'PASS  setup: Saeer inlet/outlet points found'
                          else 'FAIL  setup: Saeer inlet/outlet points found  — run 0011' end);
  v_ok  := exists (select 1 from public.profiles where id = v_admin and role = 'SUPER_ADMIN' and is_active);
  v_res := v_res || (case when v_ok then 'PASS  setup: admin profile is active SUPER_ADMIN (0012 applied)'
                          else 'FAIL  setup: admin profile is active SUPER_ADMIN (0012 applied)  — re-run 0012 after 0013' end);

  -- A throw-away FIELD_TEAM user (rolled back with everything else)
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values (v_field, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          'field.test@example.invalid', extensions.crypt('Test-1234', extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', '{"full_name":"Field Tester"}', now(), now(),
          '', '', '', '');

  v_ok := exists (select 1 from public.profiles where id = v_field and not is_active and role = 'FIELD_TEAM');
  v_res := v_res || (case when v_ok then 'PASS  setup: profile auto-created by auth trigger (inactive, FIELD_TEAM)'
                          else 'FAIL  setup: profile auto-created by auth trigger (inactive, FIELD_TEAM)' end);

  update public.profiles set is_active = true, role = 'FIELD_TEAM', full_name_ar = 'عامل حقلي تجريبي'
   where id = v_field;
  insert into public.assignments (user_id, measurement_point_id, active_from)
  values (v_field, v_p1, date '2019-01-01');

  -- ------------------------- 0. audit on tables without an `id` column (0013) --
  begin
    insert into public.user_areas (user_id, area_id) select v_field, id from public.areas where code = 'HEB';
    v_res := v_res || 'PASS  0 audit: INSERT into user_areas (composite PK) succeeds';

    v_ok := exists (select 1 from public.audit_logs where entity_table = 'user_areas' and action = 'INSERT'
                      and entity_id is null and (entity_key ->> 'user_id')::uuid = v_field and entity_key ? 'area_id');
    v_res := v_res || (case when v_ok then 'PASS  0 audit: user_areas logged with entity_key, entity_id null'
                            else 'FAIL  0 audit: user_areas logged with entity_key, entity_id null' end);

    update public.system_settings set value = '4' where key = 'pass_through_mismatch_pct';
    v_ok := exists (select 1 from public.audit_logs where entity_table = 'system_settings' and action = 'UPDATE'
                      and entity_key ->> 'key' = 'pass_through_mismatch_pct');
    v_res := v_res || (case when v_ok then 'PASS  0 audit: system_settings (text PK) logged with entity_key'
                            else 'FAIL  0 audit: system_settings (text PK) logged with entity_key' end);
    update public.system_settings set value = '3' where key = 'pass_through_mismatch_pct';
  exception when others then
    v_res := v_res || ('FAIL  0 section crashed (is 0013 applied?)  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------- 1. supersede + immutability
  begin
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_p1, v_d, v_d, 1200, 'METER_DISPLAY', 'OPERATING', v_admin) returning id into v_r1;

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by, supersedes_id, notes)
    values (v_p1, v_d, v_d, 1250, 'METER_DISPLAY', 'OPERATING', v_admin, v_r1, 'تصحيح') returning id into v_r2;

    select * into v_old from public.readings where id = v_r1;

    v_ok := v_old.is_superseded;
    v_res := v_res || (case when v_ok then 'PASS  1 supersede: original marked is_superseded'
                            else 'FAIL  1 supersede: original marked is_superseded' end);

    v_ok := v_old.volume_m3 = 1200;
    v_res := v_res || (case when v_ok then 'PASS  1 supersede: original volume intact (1200)'
                            else 'FAIL  1 supersede: original volume intact (1200)  — got ' || v_old.volume_m3 end);

    v_ok := (select count(*) from public.readings
              where measurement_point_id = v_p1 and covers_from = v_d and not is_superseded) = 1;
    v_res := v_res || (case when v_ok then 'PASS  1 supersede: correction is the only active row for the day'
                            else 'FAIL  1 supersede: correction is the only active row for the day' end);

    v_ok := (select supersedes_id = v_r1 from public.readings where id = v_r2);
    v_res := v_res || (case when v_ok then 'PASS  1 supersede: correction points at the original'
                            else 'FAIL  1 supersede: correction points at the original' end);

    begin
      update public.readings set volume_m3 = 999 where id = v_r1;
      v_res := v_res || 'FAIL  1 immutability: UPDATE of volume refused  — update was allowed';
    exception when others then
      v_res := v_res || 'PASS  1 immutability: UPDATE of volume refused';
    end;

    begin
      delete from public.readings where id = v_r1;
      v_res := v_res || 'FAIL  1 immutability: DELETE refused  — delete was allowed';
    exception when others then
      v_res := v_res || 'PASS  1 immutability: DELETE refused';
    end;

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by, supersedes_id)
      values (v_p1, v_d, v_d, 1, 'ESTIMATE', v_admin, v_r1);
      v_res := v_res || 'FAIL  1 supersede: double supersede refused  — was allowed';
    exception when others then
      v_res := v_res || 'PASS  1 supersede: double supersede refused';
    end;

    select count(*) into v_n from public.audit_logs where entity_table = 'readings' and entity_id in (v_r1, v_r2);
    v_ok := v_n >= 3;
    v_res := v_res || (case when v_ok then 'PASS  1 audit: inserts + supersede update logged (>=3)'
                            else 'FAIL  1 audit: inserts + supersede update logged (>=3)  — rows=' || v_n end);

    v_ok := exists (select 1 from public.audit_logs where entity_id = v_r1 and action = 'UPDATE'
                      and (old_value ->> 'is_superseded')::boolean = false
                      and (new_value ->> 'is_superseded')::boolean = true);
    v_res := v_res || (case when v_ok then 'PASS  1 audit: previous value recoverable from audit_logs'
                            else 'FAIL  1 audit: previous value recoverable from audit_logs' end);
  exception when others then
    v_res := v_res || ('FAIL  1 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------------ 2. pass-through check
  begin
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_in,  v_d, v_d, 1000, 'METER_DIFF', v_admin);
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_out, v_d, v_d,  900, 'METER_DIFF', v_admin);

    v_ok := exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                      and asset_id = v_tank and reference_date = v_d and status = 'OPEN');
    v_res := v_res || (case when v_ok then 'PASS  2 pass-through: 10% mismatch raised PASS_THROUGH_MISMATCH'
                            else 'FAIL  2 pass-through: 10% mismatch raised PASS_THROUGH_MISMATCH' end);

    select (details ->> 'difference_pct')::numeric into v_num
    from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH' and asset_id = v_tank and reference_date = v_d;
    v_ok := v_num between 9.9 and 10.1
            and (select (details ->> 'threshold_pct')::numeric = 3 and (details ->> 'inlet_m3')::numeric = 1000
                   from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                    and asset_id = v_tank and reference_date = v_d);
    v_res := v_res || (case when v_ok then 'PASS  2 pass-through: alert stores its inputs (difference_pct≈10, threshold 3)'
                            else 'FAIL  2 pass-through: alert stores its inputs  — difference_pct=' || coalesce(v_num::text, 'null') end);

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_in,  v_d + 1, v_d + 1, 1000, 'METER_DIFF', v_admin);
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_out, v_d + 1, v_d + 1,  985, 'METER_DIFF', v_admin);
    v_ok := not exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                          and asset_id = v_tank and reference_date = v_d + 1);
    v_res := v_res || (case when v_ok then 'PASS  2 pass-through: 1.5% mismatch raises nothing'
                            else 'FAIL  2 pass-through: 1.5% mismatch raises nothing' end);

    -- threshold is data: tighten to 1% for this asset, next day at 1.5% must alert
    update public.water_assets set pass_through_tolerance_pct = 1 where id = v_tank;
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_in,  v_d + 2, v_d + 2, 1000, 'METER_DIFF', v_admin);
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_out, v_d + 2, v_d + 2,  985, 'METER_DIFF', v_admin);
    v_ok := exists (select 1 from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH'
                      and asset_id = v_tank and reference_date = v_d + 2);
    v_res := v_res || (case when v_ok then 'PASS  2 pass-through: per-asset threshold override (1%) applied'
                            else 'FAIL  2 pass-through: per-asset threshold override (1%) applied' end);
  exception when others then
    v_res := v_res || ('FAIL  2 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------- 3. balance with incomplete data
  begin
    -- Day v_d: sources 1..5 reported (1250 + 4×800); sources 6,7 and both connections missing; inlet 1000.
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_p2, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_p3, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_p4, v_d, v_d, 800, 'METER_DISPLAY', v_admin),
           (v_p5, v_d, v_d, 800, 'METER_DISPLAY', v_admin);

    select * into v_bal from public.calculate_zone_balance(v_zone, v_d, v_d);

    v_ok := v_bal.inflow_m3 = 4450;
    v_res := v_res || (case when v_ok then 'PASS  3 balance: inflow = 4450'
                            else 'FAIL  3 balance: inflow = 4450  — got ' || v_bal.inflow_m3 end);

    v_ok := v_bal.inflow_groundwater_m3 = 4450 and v_bal.inflow_israeli_m3 = 0;
    v_res := v_res || (case when v_ok then 'PASS  3 balance: groundwater 4450 / israeli 0'
                            else 'FAIL  3 balance: groundwater 4450 / israeli 0' end);

    v_ok := v_bal.arrival_m3 = 1000;
    v_res := v_res || (case when v_ok then 'PASS  3 balance: arrival = 1000'
                            else 'FAIL  3 balance: arrival = 1000  — got ' || v_bal.arrival_m3 end);

    v_ok := v_bal.outflow_measured_m3 = 0;
    v_res := v_res || (case when v_ok then 'PASS  3 balance: measured outflow = 0'
                            else 'FAIL  3 balance: measured outflow = 0' end);

    v_ok := v_bal.difference_m3 = 3450;
    v_res := v_res || (case when v_ok then 'PASS  3 balance: difference (unexplained) = 3450'
                            else 'FAIL  3 balance: difference (unexplained) = 3450  — got ' || v_bal.difference_m3 end);

    v_ok := v_bal.storage_change_m3 = 0 and v_bal.storage_complete;
    v_res := v_res || (case when v_ok then 'PASS  3 balance: no storage term for a transit zone'
                            else 'FAIL  3 balance: no storage term for a transit zone' end);

    v_ok := v_bal.points_expected = 10;
    v_res := v_res || (case when v_ok then 'PASS  3 completeness: points_expected = 10'
                            else 'FAIL  3 completeness: points_expected = 10  — got ' || v_bal.points_expected end);

    v_ok := v_bal.points_complete = 6;
    v_res := v_res || (case when v_ok then 'PASS  3 completeness: points_complete = 6'
                            else 'FAIL  3 completeness: points_complete = 6  — got ' || v_bal.points_complete end);

    v_ok := v_bal.point_days_reported = 6 and v_bal.point_days_expected = 10;
    v_res := v_res || (case when v_ok then 'PASS  3 completeness: point-days 6/10'
                            else 'FAIL  3 completeness: point-days 6/10' end);

    v_ok := v_bal.sources_total = 9 and v_bal.sources_operating = 1;
    v_res := v_res || (case when v_ok then 'PASS  3 sources: total 9, operating 1'
                            else 'FAIL  3 sources: total 9, operating 1  — ' || format('total=%s operating=%s', v_bal.sources_total, v_bal.sources_operating) end);

    v_ok := (v_bal.by_role -> 'INFLOW' ->> 'points_complete')::int = 5
            and (v_bal.by_role -> 'INFLOW' ->> 'points_expected')::int = 9;
    v_res := v_res || (case when v_ok then 'PASS  3 by_role: INFLOW 5/9 complete'
                            else 'FAIL  3 by_role: INFLOW 5/9 complete  — ' || v_bal.by_role::text end);

    select count(*) into v_n from public.get_missing_readings(v_d, v_d, null);
    v_ok := v_n = 4;
    v_res := v_res || (case when v_ok then 'PASS  3 missing readings: 4 of 11 daily points missing on day 1'
                            else 'FAIL  3 missing readings: 4 of 11 daily points missing on day 1  — got ' || v_n end);

    -- proration: a 2-day reading (600 m³) contributes 300 to each day
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_p2, v_d + 1, v_d + 2, 600, 'METER_DIFF', v_admin);
    select * into v_bal from public.calculate_zone_balance(v_zone, v_d + 1, v_d + 1);

    v_ok := v_bal.inflow_m3 = 300;
    v_res := v_res || (case when v_ok then 'PASS  3 proration: 2-day reading contributes half to a single day'
                            else 'FAIL  3 proration: 2-day reading contributes half to a single day  — got ' || v_bal.inflow_m3 end);

    v_ok := v_bal.points_complete = 2;
    v_res := v_res || (case when v_ok then 'PASS  3 proration: the 2-day reading counts as coverage'
                            else 'FAIL  3 proration: the 2-day reading counts as coverage  — got ' || v_bal.points_complete end);

    select * into v_bal from public.calculate_zone_balance(v_zone, v_d, v_d + 2);
    v_ok := v_bal.point_days_expected = 30 and v_bal.arrival_m3 = 3000;
    v_res := v_res || (case when v_ok then 'PASS  3 range: 3-day window → 30 point-days expected, arrival 3000'
                            else 'FAIL  3 range: 3-day window  — ' || format('pd=%s arrival=%s', v_bal.point_days_expected, v_bal.arrival_m3) end);
  exception when others then
    v_res := v_res || ('FAIL  3 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------ 4. negative RLS: FIELD_TEAM
  -- Recording into v_res (a variable) is what makes this section survive `set role`.
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_field, 'role', 'authenticated')::text, true);

    v_ok := auth.uid() = v_field;
    v_res := v_res || (case when v_ok then 'PASS  4 rls: impersonation active (auth.uid() = field user)'
                            else 'FAIL  4 rls: impersonation active  — auth.uid()=' || coalesce(auth.uid()::text, 'null') end);

    v_ok := app.user_role() = 'FIELD_TEAM';
    v_res := v_res || (case when v_ok then 'PASS  4 rls: app.user_role() = FIELD_TEAM'
                            else 'FAIL  4 rls: app.user_role() = FIELD_TEAM  — got ' || coalesce(app.user_role(), 'null') end);

    select count(*) into v_n from public.measurement_points;
    v_ok := v_n = 1;
    v_res := v_res || (case when v_ok then 'PASS  4 rls: sees only the 1 assigned point (of 11)'
                            else 'FAIL  4 rls: sees only the 1 assigned point (of 11)  — got ' || v_n end);

    select count(*) into v_n from public.readings where measurement_point_id = v_p2;
    v_ok := v_n = 0;
    v_res := v_res || (case when v_ok then 'PASS  4 rls: readings of an unassigned point are hidden (0)'
                            else 'FAIL  4 rls: readings of an unassigned point are hidden (0)  — got ' || v_n end);

    select count(*) into v_n from public.readings where measurement_point_id = v_p1;
    v_ok := v_n = 2;
    v_res := v_res || (case when v_ok then 'PASS  4 rls: readings of the assigned point are visible (2)'
                            else 'FAIL  4 rls: readings of the assigned point are visible (2)  — got ' || v_n end);

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis)
      values (v_p2, v_d + 5, v_d + 5, 10, 'ESTIMATE');
      v_res := v_res || 'FAIL  4 rls: INSERT on an unassigned point refused  — insert was allowed';
    exception when others then
      v_res := v_res || (case when sqlstate = '42501' then 'PASS  4 rls: INSERT on an unassigned point refused (42501)'
                              else 'FAIL  4 rls: INSERT on an unassigned point refused  — wrong error ' || sqlstate || ' ' || sqlerrm end);
    end;

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
      values (v_p1, v_d + 5, v_d + 5, 10, 'ESTIMATE', v_admin);   -- forging entered_by
      v_res := v_res || 'FAIL  4 rls: INSERT with a forged entered_by refused  — insert was allowed';
    exception when others then
      v_res := v_res || (case when sqlstate = '42501' then 'PASS  4 rls: INSERT with a forged entered_by refused (42501)'
                              else 'FAIL  4 rls: INSERT with a forged entered_by refused  — wrong error ' || sqlstate || ' ' || sqlerrm end);
    end;

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis)
    values (v_p1, v_d + 5, v_d + 5, 10, 'ESTIMATE') returning id into v_r3;
    v_ok := (select entered_by = v_field from public.readings where id = v_r3);
    v_res := v_res || (case when v_ok then 'PASS  4 rls: INSERT on the assigned point allowed, entered_by = self'
                            else 'FAIL  4 rls: INSERT on the assigned point allowed, entered_by = self' end);

    update public.readings set validation_notes = 'x' where id = v_r3;
    get diagnostics v_n = row_count;
    v_ok := v_n = 0;
    v_res := v_res || (case when v_ok then 'PASS  4 rls: UPDATE by field team affects 0 rows'
                            else 'FAIL  4 rls: UPDATE by field team affects 0 rows  — rows=' || v_n end);

    begin
      delete from public.readings where id = v_r3;
      get diagnostics v_n = row_count;
      v_ok := v_n = 0;
      v_res := v_res || (case when v_ok then 'PASS  4 rls: DELETE by field team affects 0 rows'
                              else 'FAIL  4 rls: DELETE by field team refused  — rows=' || v_n end);
    exception when others then
      v_res := v_res || ('PASS  4 rls: DELETE by field team refused (' || sqlstate || ')');
    end;

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, supersedes_id)
    values (v_p1, v_d + 5, v_d + 5, 12, 'ESTIMATE', v_r3);
    v_ok := (select is_superseded from public.readings where id = v_r3);
    v_res := v_res || (case when v_ok then 'PASS  4 rls: field team corrects its own reading via supersede (no UPDATE right)'
                            else 'FAIL  4 rls: field team corrects its own reading via supersede' end);

    begin
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, supersedes_id)
      values (v_p1, v_d + 5, v_d + 5, 13, 'ESTIMATE', v_r3);      -- already superseded above
      v_res := v_res || 'FAIL  4 rls: supersede of an already-superseded row refused  — was allowed';
    exception when others then
      v_res := v_res || ('PASS  4 rls: supersede of an already-superseded row refused (' || sqlstate || ')');
    end;

    select count(*) into v_n from public.alerts where alert_type = 'PASS_THROUGH_MISMATCH';
    v_ok := v_n = 0;
    v_res := v_res || (case when v_ok then 'PASS  4 rls: tank alerts hidden from field team (0)'
                            else 'FAIL  4 rls: tank alerts hidden from field team (0)  — got ' || v_n end);

    select count(*) into v_n from public.audit_logs;
    v_ok := v_n = 0;
    v_res := v_res || (case when v_ok then 'PASS  4 rls: audit_logs hidden from field team (0)'
                            else 'FAIL  4 rls: audit_logs hidden from field team (0)  — got ' || v_n end);

    select count(*) into v_n from public.profiles;
    v_ok := v_n = 1;
    v_res := v_res || (case when v_ok then 'PASS  4 rls: profiles → own row only (1)'
                            else 'FAIL  4 rls: profiles → own row only (1)  — got ' || v_n end);

    begin
      update public.profiles set role = 'SUPER_ADMIN' where id = v_field;
      get diagnostics v_n = row_count;
      v_ok := v_n = 0 and (select role from public.profiles where id = v_field) = 'FIELD_TEAM';
      v_res := v_res || (case when v_ok then 'PASS  4 rls: self-promotion to SUPER_ADMIN refused'
                              else 'FAIL  4 rls: self-promotion to SUPER_ADMIN refused  — rows=' || v_n end);
    exception when others then
      v_res := v_res || ('PASS  4 rls: self-promotion to SUPER_ADMIN refused (' || sqlstate || ')');
    end;

    begin
      insert into public.water_assets (code, name_ar, asset_type, supply_type) values ('W-HACK', 'x', 'WELL', 'GROUNDWATER');
      v_res := v_res || 'FAIL  4 rls: field team cannot create assets  — was allowed';
    exception when others then
      v_res := v_res || (case when sqlstate = '42501' then 'PASS  4 rls: field team cannot create assets (42501)'
                              else 'FAIL  4 rls: field team cannot create assets  — wrong error ' || sqlstate end);
    end;

    begin
      update public.system_settings set value = '99' where key = 'pass_through_mismatch_pct';
      get diagnostics v_n = row_count;
      v_ok := v_n = 0;
      v_res := v_res || (case when v_ok then 'PASS  4 rls: field team cannot change thresholds'
                              else 'FAIL  4 rls: field team cannot change thresholds  — rows=' || v_n end);
    exception when others then
      v_res := v_res || ('PASS  4 rls: field team cannot change thresholds (' || sqlstate || ')');
    end;

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || ('FAIL  4 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------------- 5. inactive user
  begin
    update public.profiles set is_active = false where id = v_field;
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_field, 'role', 'authenticated')::text, true);

    select count(*) into v_n from public.profiles where id = auth.uid();
    v_ok := v_n = 1;
    v_res := v_res || (case when v_ok then 'PASS  5 inactive: own profile still readable (UI can explain the state)'
                            else 'FAIL  5 inactive: own profile still readable  — got ' || v_n end);

    v_ok := (select not is_active from public.profiles where id = auth.uid());
    v_res := v_res || (case when v_ok then 'PASS  5 inactive: is_active reads false'
                            else 'FAIL  5 inactive: is_active reads false' end);

    select count(*) into v_n from public.measurement_points;
    v_ok := v_n = 0;
    v_res := v_res || (case when v_ok then 'PASS  5 inactive: sees 0 measurement points'
                            else 'FAIL  5 inactive: sees 0 measurement points  — got ' || v_n end);

    v_ok := app.user_role() is null;
    v_res := v_res || (case when v_ok then 'PASS  5 inactive: app.user_role() is null'
                            else 'FAIL  5 inactive: app.user_role() is null  — got ' || coalesce(app.user_role(), 'null') end);

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    update public.profiles set is_active = true where id = v_field;
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || ('FAIL  5 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ---------------------------------------------- 6. storage: curve / fallback
  begin
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_tank, v_d, 2.5, v_admin);
    v_ok := (select storage_m3 is null and percentage_full is null
               from public.tank_level_readings where asset_id = v_tank and reading_date = v_d);
    v_res := v_res || (case when v_ok then 'PASS  6 storage: unknown geometry → storage NULL (never invented)'
                            else 'FAIL  6 storage: unknown geometry → storage NULL' end);

    update public.water_assets set capacity_m3 = 5000, height_m = 5 where id = v_tank;
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_tank, v_d + 1, 2.5, v_admin);
    v_ok := (select storage_m3 = 2500 and percentage_full = 50
               from public.tank_level_readings where asset_id = v_tank and reading_date = v_d + 1);
    v_res := v_res || (case when v_ok then 'PASS  6 storage: linear fallback 2.5 m of 5 m × 5000 = 2500 m³ (50%)'
                            else 'FAIL  6 storage: linear fallback  — got '
                                 || coalesce((select storage_m3::text from public.tank_level_readings
                                               where asset_id = v_tank and reading_date = v_d + 1), 'null') end);

    insert into public.level_volume_curve (asset_id, level_m, volume_m3) values (v_tank, 0, 0), (v_tank, 2, 2000), (v_tank, 5, 6000);
    insert into public.tank_level_readings (asset_id, reading_date, level_m, entered_by) values (v_tank, v_d + 2, 2.5, v_admin);
    v_ok := (select storage_m3 = 2666.67 from public.tank_level_readings where asset_id = v_tank and reading_date = v_d + 2);
    v_res := v_res || (case when v_ok then 'PASS  6 storage: curve interpolation at 2.5 m between (2,2000)-(5,6000) = 2666.67'
                            else 'FAIL  6 storage: curve interpolation  — got '
                                 || coalesce((select storage_m3::text from public.tank_level_readings
                                               where asset_id = v_tank and reading_date = v_d + 2), 'null') end);

    v_ok := public.get_storage_m3(v_tank, 1) = 1000;
    v_res := v_res || (case when v_ok then 'PASS  6 storage: get_storage_m3 direct call (level 1 → 1000)'
                            else 'FAIL  6 storage: get_storage_m3 direct call  — got '
                                 || coalesce(public.get_storage_m3(v_tank, 1)::text, 'null') end);
  exception when others then
    v_res := v_res || ('FAIL  6 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------ 7. status propagation + alert
  begin
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_p1, v_d + 6, v_d + 6, 0, 'ESTIMATE', 'STOPPED', v_admin);

    v_ok := (select current_status = 'STOPPED' from public.water_assets where id = v_well1);
    v_res := v_res || (case when v_ok then 'PASS  7 status: asset current_status follows the latest reading (STOPPED)'
                            else 'FAIL  7 status: asset current_status follows the latest reading  — got '
                                 || (select current_status from public.water_assets where id = v_well1) end);

    v_ok := exists (select 1 from public.alerts where alert_type = 'SOURCE_STOPPED'
                      and asset_id = v_well1 and reference_date = v_d + 6);
    v_res := v_res || (case when v_ok then 'PASS  7 status: SOURCE_STOPPED alert raised'
                            else 'FAIL  7 status: SOURCE_STOPPED alert raised' end);

    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, operational_status, entered_by)
    values (v_p1, v_d + 3, v_d + 3, 1100, 'METER_DISPLAY', 'OPERATING', v_admin);
    v_ok := (select current_status = 'STOPPED' from public.water_assets where id = v_well1);
    v_res := v_res || (case when v_ok then 'PASS  7 status: an older reading does not overwrite a newer status'
                            else 'FAIL  7 status: an older reading does not overwrite a newer status' end);
  exception when others then
    v_res := v_res || ('FAIL  7 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------------------- 8. abnormal-reading flag
  begin
    for v_n in 10..17 loop
      insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
      values (v_p2, v_d + v_n, v_d + v_n, 1000, 'METER_DISPLAY', v_admin);
    end loop;
    insert into public.readings (measurement_point_id, covers_from, covers_to, volume_m3, entry_basis, entered_by)
    values (v_p2, v_d + 18, v_d + 18, 5000, 'METER_DISPLAY', v_admin) returning id into v_r3;

    v_ok := (select validation_status = 'FLAGGED' from public.readings where id = v_r3);
    v_res := v_res || (case when v_ok then 'PASS  8 abnormal: 5000 after 8×1000 → FLAGGED, not rejected'
                            else 'FAIL  8 abnormal: 5000 after 8×1000 → FLAGGED  — got '
                                 || (select validation_status from public.readings where id = v_r3) end);

    v_ok := exists (select 1 from public.alerts where alert_type = 'ABNORMAL_READING' and reading_id = v_r3);
    v_res := v_res || (case when v_ok then 'PASS  8 abnormal: ABNORMAL_READING alert raised'
                            else 'FAIL  8 abnormal: ABNORMAL_READING alert raised' end);

    v_ok := (select bool_and(validation_status = 'OK') from public.readings
              where measurement_point_id = v_p2 and covers_from between v_d + 10 and v_d + 17);
    v_res := v_res || (case when v_ok then 'PASS  8 abnormal: normal values are not flagged'
                            else 'FAIL  8 abnormal: normal values are not flagged' end);
  exception when others then
    v_res := v_res || ('FAIL  8 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ------------------------------------- 9. management scope (positive control)
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

    select count(*) into v_n from public.measurement_points;
    v_ok := v_n = 11;
    v_res := v_res || (case when v_ok then 'PASS  9 admin: sees all 11 measurement points'
                            else 'FAIL  9 admin: sees all 11 measurement points  — got ' || v_n end);

    select count(*) into v_n from public.alerts where status = 'OPEN';
    v_ok := v_n >= 4;
    v_res := v_res || (case when v_ok then 'PASS  9 admin: sees open alerts (>=4)'
                            else 'FAIL  9 admin: sees open alerts (>=4)  — got ' || v_n end);

    update public.readings set validation_status = 'REVIEWED', validation_notes = 'checked' where id = v_r3;
    get diagnostics v_n = row_count;
    v_ok := v_n = 1;
    v_res := v_res || (case when v_ok then 'PASS  9 admin: may update validation fields (1 row)'
                            else 'FAIL  9 admin: may update validation fields  — rows=' || v_n end);

    begin
      update public.readings set volume_m3 = 1 where id = v_r3;
      v_res := v_res || 'FAIL  9 admin: still cannot edit volume (immutability)  — was allowed';
    exception when others then
      v_res := v_res || 'PASS  9 admin: still cannot edit volume (immutability)';
    end;

    select count(*) into v_n from public.audit_logs;
    v_ok := v_n > 0;
    v_res := v_res || (case when v_ok then 'PASS  9 admin: reads audit_logs (>0)'
                            else 'FAIL  9 admin: reads audit_logs (>0)  — got ' || v_n end);

    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
  exception when others then
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    v_res := v_res || ('FAIL  9 section crashed  — ' || sqlstate || ' ' || sqlerrm);
  end;

  -- ---------------------------------------------------------------- report
  -- Guard: a crashed section means its checks never ran — that is not a pass.
  v_total := coalesce(array_length(v_res, 1), 0);
  select count(*) into v_fail  from unnest(v_res) x where x like 'FAIL%';
  select count(*) into v_crash from unnest(v_res) x where x like 'FAIL%section crashed%';

  raise exception E'TEST REPORT — % failed of % checks (% crashed sections). All test data rolled back (expected).\n%',
    v_fail, v_total, v_crash, array_to_string(v_res, E'\n');
end;
$$;
