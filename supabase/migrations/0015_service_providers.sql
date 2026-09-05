-- =============================================================================
-- 0015  Service providers (route take-offs) — schema support + placeholder seed
--
-- Answer to "do the CHECK constraints already allow these?": NO, they did not.
--   0003  asset_type  in (WELL, ISRAELI_CONNECTION, TANK, RESERVOIR, PUMPING_STATION, MAIN_METER)
--   0004  point_type  in (SOURCE_METER, TRANSFER_METER, TANK_INLET_METER, TANK_OUTLET_METER)
-- SERVICE_PROVIDER_METER appeared only in a comment. Both constraints are widened here.
--
-- Route take-offs are billed monthly, never read daily. Deriving a daily figure by dividing
-- a monthly bill would be an estimate presented as a measurement and would corrupt the daily
-- balance. So:
--   * their measurement points carry expects_daily_reading = false — they never appear in the
--     daily task list and never count against daily data completeness;
--   * they are NOT members of SAEER-TRANSIT, so the daily difference stays "unexplained";
--   * a future monthly reading spans its billing period through covers_from/covers_to with
--     entry_basis = 'ESTIMATE'. Nothing in the schema blocks that; the monthly balance itself
--     is a later feature and is not built here.
--
-- Re-runnable.
-- =============================================================================

-- ---- widen the two CHECK constraints ----------------------------------------
alter table public.water_assets drop constraint if exists water_assets_asset_type_check;
alter table public.water_assets
  add constraint water_assets_asset_type_check check (asset_type in
    ('WELL','ISRAELI_CONNECTION','TANK','RESERVOIR','PUMPING_STATION','MAIN_METER','SERVICE_PROVIDER'));

alter table public.measurement_points drop constraint if exists measurement_points_point_type_check;
alter table public.measurement_points
  add constraint measurement_points_point_type_check check (point_type in
    ('SOURCE_METER','TRANSFER_METER','TANK_INLET_METER','TANK_OUTLET_METER','SERVICE_PROVIDER_METER'));
-- CONSUMER_METER stays out until Phase 2 needs it; widening again is a one-line migration.

-- water_assets_supply_type_chk already allows SERVICE_PROVIDER with a NULL supply_type
-- (its third branch covers every type that is neither WELL nor ISRAELI_CONNECTION).

-- ---- placeholder seed --------------------------------------------------------
-- !! PLACEHOLDER NAMES !!  Real service providers are entered through the asset screens
-- in Stage 5; codes and names are data and need no code change to replace.
with area as (select id from public.areas where code = 'HEB')
insert into public.water_assets (code, name_ar, name_en, asset_type, area_id, current_status, description_ar)
select v.code, v.name_ar, v.name_en, 'SERVICE_PROVIDER', area.id, 'OPERATING', v.description_ar
from area,
(values
  ('SP-TMP-01', 'مزوّد خدمة 1 (مؤقت)', 'Service provider 1 (placeholder)', 'مسحوبات على الطريق — فوترة شهرية، لا قراءة يومية'),
  ('SP-TMP-02', 'مزوّد خدمة 2 (مؤقت)', 'Service provider 2 (placeholder)', 'مسحوبات على الطريق — فوترة شهرية، لا قراءة يومية'),
  ('SP-TMP-03', 'مزوّد خدمة 3 (مؤقت)', 'Service provider 3 (placeholder)', 'مسحوبات على الطريق — فوترة شهرية، لا قراءة يومية')
) as v(code, name_ar, name_en, description_ar)
on conflict (code) do update
  set name_ar = excluded.name_ar, name_en = excluded.name_en, description_ar = excluded.description_ar;

with area as (select id from public.areas where code = 'HEB')
insert into public.measurement_points (code, name_ar, name_en, point_type, asset_id, area_id, expects_daily_reading)
select v.code, v.name_ar, v.name_en, 'SERVICE_PROVIDER_METER', a.id, area.id, false
from area,
(values
  ('MP-SP-TMP-01', 'SP-TMP-01', 'عداد مزوّد خدمة 1 (مؤقت)', 'Service provider 1 meter (placeholder)'),
  ('MP-SP-TMP-02', 'SP-TMP-02', 'عداد مزوّد خدمة 2 (مؤقت)', 'Service provider 2 meter (placeholder)'),
  ('MP-SP-TMP-03', 'SP-TMP-03', 'عداد مزوّد خدمة 3 (مؤقت)', 'Service provider 3 meter (placeholder)')
) as v(code, asset_code, name_ar, name_en)
join public.water_assets a on a.code = v.asset_code
on conflict (code) do update
  set name_ar = excluded.name_ar,
      name_en = excluded.name_en,
      point_type = excluded.point_type,
      expects_daily_reading = false;

-- Deliberately NOT added to any balance_zone: the daily Saeer balance must keep showing the
-- take-offs inside "unexplained" rather than absorbing an estimate.
do $$
declare
  v_n int;
begin
  select count(*) into v_n
  from public.balance_zone_members bzm
  join public.measurement_points mp on mp.id = bzm.measurement_point_id
  where mp.point_type = 'SERVICE_PROVIDER_METER';

  if v_n > 0 then
    raise exception 'Service-provider meters must not be members of a daily balance zone (found %)', v_n;
  end if;
end;
$$;
