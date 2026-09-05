-- =============================================================================
-- 0010  Row Level Security — every table, deny by default, explicit policies.
-- No table has a DELETE policy except pure junction/staging tables listed at the end.
-- Roles: SUPER_ADMIN, WATER_MANAGEMENT (=management), AREA_MANAGER (user_areas scope),
--        FIELD_TEAM (assigned points; INSERT readings only; never UPDATE/DELETE).
-- =============================================================================

-- ---- enable RLS everywhere ---------------------------------------------------
alter table public.areas                 enable row level security;
alter table public.profiles              enable row level security;
alter table public.user_areas            enable row level security;
alter table public.water_assets          enable row level security;
alter table public.level_volume_curve    enable row level security;
alter table public.water_paths           enable row level security;
alter table public.measurement_points    enable row level security;
alter table public.meter_devices         enable row level security;
alter table public.meter_installations   enable row level security;
alter table public.readings              enable row level security;
alter table public.tank_level_readings   enable row level security;
alter table public.balance_zones         enable row level security;
alter table public.balance_zone_members  enable row level security;
alter table public.assignments           enable row level security;
alter table public.system_settings       enable row level security;
alter table public.alerts                enable row level security;
alter table public.audit_logs            enable row level security;
alter table public.import_batches        enable row level security;
alter table public.import_rows           enable row level security;
alter table public.import_errors         enable row level security;

-- ---- areas -------------------------------------------------------------------
drop policy if exists areas_select on public.areas;
create policy areas_select on public.areas for select to authenticated
  using (app.user_role() is not null);            -- any active user; needed for labels & filters
drop policy if exists areas_insert on public.areas;
create policy areas_insert on public.areas for insert to authenticated
  with check (app.is_management());
drop policy if exists areas_update on public.areas;
create policy areas_update on public.areas for update to authenticated
  using (app.is_management()) with check (app.is_management());

-- ---- profiles ----------------------------------------------------------------
-- Own row always readable (even if inactive, so the UI can explain the state);
-- management reads all; area managers read profiles of users sharing an area.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or app.is_management()
    or (app.is_area_manager() and exists (
          select 1 from public.user_areas ua
          where ua.user_id = profiles.id and ua.area_id in (select app.user_area_ids())))
  );
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated
  with check (app.is_super_admin());                -- normal creation happens via the auth trigger
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid()
              and role = (select p.role from public.profiles p where p.id = auth.uid())
              and is_active = (select p.is_active from public.profiles p where p.id = auth.uid()));
drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles for update to authenticated
  using (app.is_super_admin()) with check (app.is_super_admin());

-- ---- user_areas --------------------------------------------------------------
drop policy if exists user_areas_select on public.user_areas;
create policy user_areas_select on public.user_areas for select to authenticated
  using (user_id = auth.uid() or app.is_management()
         or (app.is_area_manager() and area_id in (select app.user_area_ids())));
drop policy if exists user_areas_insert on public.user_areas;
create policy user_areas_insert on public.user_areas for insert to authenticated
  with check (app.is_management());
drop policy if exists user_areas_delete on public.user_areas;
create policy user_areas_delete on public.user_areas for delete to authenticated
  using (app.is_management());

-- ---- water_assets ------------------------------------------------------------
drop policy if exists water_assets_select on public.water_assets;
create policy water_assets_select on public.water_assets for select to authenticated
  using (app.can_access_asset(id));
drop policy if exists water_assets_insert on public.water_assets;
create policy water_assets_insert on public.water_assets for insert to authenticated
  with check (app.is_management());
drop policy if exists water_assets_update on public.water_assets;
create policy water_assets_update on public.water_assets for update to authenticated
  using (app.is_management()) with check (app.is_management());
-- no delete policy (and a trigger refuses deletes anyway)

-- ---- level_volume_curve ------------------------------------------------------
drop policy if exists level_volume_curve_select on public.level_volume_curve;
create policy level_volume_curve_select on public.level_volume_curve for select to authenticated
  using (app.can_access_asset(asset_id));
drop policy if exists level_volume_curve_write on public.level_volume_curve;
create policy level_volume_curve_write on public.level_volume_curve for all to authenticated
  using (app.is_management()) with check (app.is_management());

-- ---- water_paths -------------------------------------------------------------
drop policy if exists water_paths_select on public.water_paths;
create policy water_paths_select on public.water_paths for select to authenticated
  using (app.can_access_asset(from_asset_id) or app.can_access_asset(to_asset_id));
drop policy if exists water_paths_insert on public.water_paths;
create policy water_paths_insert on public.water_paths for insert to authenticated
  with check (app.is_management());
drop policy if exists water_paths_update on public.water_paths;
create policy water_paths_update on public.water_paths for update to authenticated
  using (app.is_management()) with check (app.is_management());

-- ---- measurement_points ------------------------------------------------------
drop policy if exists measurement_points_select on public.measurement_points;
create policy measurement_points_select on public.measurement_points for select to authenticated
  using (app.can_access_point(id));
drop policy if exists measurement_points_insert on public.measurement_points;
create policy measurement_points_insert on public.measurement_points for insert to authenticated
  with check (app.is_management());
drop policy if exists measurement_points_update on public.measurement_points;
create policy measurement_points_update on public.measurement_points for update to authenticated
  using (app.is_management()) with check (app.is_management());

-- ---- meter_devices / meter_installations -------------------------------------
drop policy if exists meter_devices_select on public.meter_devices;
create policy meter_devices_select on public.meter_devices for select to authenticated
  using (app.is_management() or app.is_area_manager());
drop policy if exists meter_devices_write on public.meter_devices;
create policy meter_devices_write on public.meter_devices for all to authenticated
  using (app.is_management()) with check (app.is_management());

drop policy if exists meter_installations_select on public.meter_installations;
create policy meter_installations_select on public.meter_installations for select to authenticated
  using (app.can_access_point(measurement_point_id));
drop policy if exists meter_installations_insert on public.meter_installations;
create policy meter_installations_insert on public.meter_installations for insert to authenticated
  with check (app.is_management());
drop policy if exists meter_installations_update on public.meter_installations;
create policy meter_installations_update on public.meter_installations for update to authenticated
  using (app.is_management()) with check (app.is_management());

-- ---- readings ----------------------------------------------------------------
drop policy if exists readings_select on public.readings;
create policy readings_select on public.readings for select to authenticated
  using (app.can_access_point(measurement_point_id));
-- Insert within scope; the row must be attributed to the inserting user.
drop policy if exists readings_insert on public.readings;
create policy readings_insert on public.readings for insert to authenticated
  with check (app.can_access_point(measurement_point_id) and entered_by = auth.uid());
-- Only management may update, and the immutability trigger limits it to validation fields.
drop policy if exists readings_update on public.readings;
create policy readings_update on public.readings for update to authenticated
  using (app.is_management()) with check (app.is_management());
-- no delete policy (trigger refuses deletes too)

-- ---- tank_level_readings -----------------------------------------------------
drop policy if exists tank_level_readings_select on public.tank_level_readings;
create policy tank_level_readings_select on public.tank_level_readings for select to authenticated
  using (app.can_access_asset(asset_id));
drop policy if exists tank_level_readings_insert on public.tank_level_readings;
create policy tank_level_readings_insert on public.tank_level_readings for insert to authenticated
  with check (app.can_access_asset(asset_id) and entered_by = auth.uid());
drop policy if exists tank_level_readings_update on public.tank_level_readings;
create policy tank_level_readings_update on public.tank_level_readings for update to authenticated
  using (app.is_management()) with check (app.is_management());

-- ---- balance_zones / members -------------------------------------------------
drop policy if exists balance_zones_select on public.balance_zones;
create policy balance_zones_select on public.balance_zones for select to authenticated
  using (app.user_role() is not null);
drop policy if exists balance_zones_write on public.balance_zones;
create policy balance_zones_write on public.balance_zones for all to authenticated
  using (app.is_management()) with check (app.is_management());

drop policy if exists balance_zone_members_select on public.balance_zone_members;
create policy balance_zone_members_select on public.balance_zone_members for select to authenticated
  using (app.user_role() is not null);
drop policy if exists balance_zone_members_write on public.balance_zone_members;
create policy balance_zone_members_write on public.balance_zone_members for all to authenticated
  using (app.is_management()) with check (app.is_management());

-- ---- assignments -------------------------------------------------------------
drop policy if exists assignments_select on public.assignments;
create policy assignments_select on public.assignments for select to authenticated
  using (user_id = auth.uid() or app.is_management()
         or (app.is_area_manager() and app.can_access_point(measurement_point_id)));
drop policy if exists assignments_insert on public.assignments;
create policy assignments_insert on public.assignments for insert to authenticated
  with check (app.is_management()
              or (app.is_area_manager() and app.can_access_point(measurement_point_id)));
drop policy if exists assignments_update on public.assignments;
create policy assignments_update on public.assignments for update to authenticated
  using (app.is_management() or (app.is_area_manager() and app.can_access_point(measurement_point_id)))
  with check (app.is_management() or (app.is_area_manager() and app.can_access_point(measurement_point_id)));

-- ---- system_settings ---------------------------------------------------------
drop policy if exists system_settings_select on public.system_settings;
create policy system_settings_select on public.system_settings for select to authenticated
  using (app.user_role() is not null);
drop policy if exists system_settings_write on public.system_settings;
create policy system_settings_write on public.system_settings for all to authenticated
  using (app.is_super_admin()) with check (app.is_super_admin());

-- ---- alerts ------------------------------------------------------------------
drop policy if exists alerts_select on public.alerts;
create policy alerts_select on public.alerts for select to authenticated
  using (app.is_management()
         or (asset_id is not null and app.can_access_asset(asset_id))
         or (measurement_point_id is not null and app.can_access_point(measurement_point_id)));
-- Alerts are created by SECURITY DEFINER triggers/functions; management may also file one manually.
drop policy if exists alerts_insert on public.alerts;
create policy alerts_insert on public.alerts for insert to authenticated
  with check (app.is_management());
-- Acknowledge / resolve within scope (field team cannot).
drop policy if exists alerts_update on public.alerts;
create policy alerts_update on public.alerts for update to authenticated
  using (app.is_management()
         or (app.is_area_manager() and (
               (asset_id is not null and app.can_access_asset(asset_id))
               or (measurement_point_id is not null and app.can_access_point(measurement_point_id)))))
  with check (app.is_management() or app.is_area_manager());

-- ---- audit_logs --------------------------------------------------------------
drop policy if exists audit_logs_select on public.audit_logs;
create policy audit_logs_select on public.audit_logs for select to authenticated
  using (app.is_management());
-- no insert/update/delete policies: only SECURITY DEFINER triggers write here

-- ---- import staging ----------------------------------------------------------
drop policy if exists import_batches_all on public.import_batches;
create policy import_batches_all on public.import_batches for all to authenticated
  using (app.is_management()) with check (app.is_management());
drop policy if exists import_rows_all on public.import_rows;
create policy import_rows_all on public.import_rows for all to authenticated
  using (app.is_management()) with check (app.is_management());
drop policy if exists import_errors_all on public.import_errors;
create policy import_errors_all on public.import_errors for all to authenticated
  using (app.is_management()) with check (app.is_management());

-- ---- grant layer (RLS is the boundary; grants just avoid noisy 42501 errors) --
grant select, insert, update on all tables in schema public to authenticated;
grant delete on public.user_areas, public.level_volume_curve, public.balance_zone_members,
                public.meter_devices, public.import_batches, public.import_rows, public.import_errors
  to authenticated;
revoke delete on public.readings, public.tank_level_readings, public.water_assets, public.audit_logs,
                public.profiles, public.areas, public.water_paths, public.measurement_points,
                public.meter_installations, public.balance_zones, public.assignments,
                public.system_settings, public.alerts
  from authenticated;
