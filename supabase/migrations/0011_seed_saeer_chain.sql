-- =============================================================================
-- 0011  Seed — the Saeer chain only (Phase 1 vertical slice)
--
-- !! PLACEHOLDER CODES/NAMES !!  Codes ending in -TMP-nn and names containing "(مؤقت)"
-- stand in for the real wells and Israeli connections, whose list was not available
-- when this was written. Replace them (or rename via the asset screens in Stage 5 —
-- codes are data, renaming needs no code change). Coordinates are NULL except Saeer's,
-- which is approximate.
--
-- Re-runnable: assets/points/zones upsert by code; paths/members insert-if-missing.
-- =============================================================================

-- Area ---------------------------------------------------------------------------
insert into public.areas (code, name_ar, name_en)
values ('HEB', 'الخليل', 'Hebron')
on conflict (code) do update set name_ar = excluded.name_ar, name_en = excluded.name_en;

-- Assets -------------------------------------------------------------------------
with area as (select id from public.areas where code = 'HEB')
insert into public.water_assets (code, name_ar, name_en, asset_type, supply_type, area_id, current_status,
                                 is_pass_through, geom, description_ar)
select v.code, v.name_ar, v.name_en, v.asset_type, v.supply_type, area.id, 'UNKNOWN',
       v.is_pass_through, v.geom, v.description_ar
from area,
(values
  -- Wells feeding the main groundwater transmission line (7 placeholders)
  ('W-TMP-01', 'بئر 1 (مؤقت)', 'Well 1 (placeholder)', 'WELL', 'GROUNDWATER', false, null::extensions.geometry, 'بديل مؤقت — يُستبدل بالبئر الحقيقي'),
  ('W-TMP-02', 'بئر 2 (مؤقت)', 'Well 2 (placeholder)', 'WELL', 'GROUNDWATER', false, null, 'بديل مؤقت — يُستبدل بالبئر الحقيقي'),
  ('W-TMP-03', 'بئر 3 (مؤقت)', 'Well 3 (placeholder)', 'WELL', 'GROUNDWATER', false, null, 'بديل مؤقت — يُستبدل بالبئر الحقيقي'),
  ('W-TMP-04', 'بئر 4 (مؤقت)', 'Well 4 (placeholder)', 'WELL', 'GROUNDWATER', false, null, 'بديل مؤقت — يُستبدل بالبئر الحقيقي'),
  ('W-TMP-05', 'بئر 5 (مؤقت)', 'Well 5 (placeholder)', 'WELL', 'GROUNDWATER', false, null, 'بديل مؤقت — يُستبدل بالبئر الحقيقي'),
  ('W-TMP-06', 'بئر 6 (مؤقت)', 'Well 6 (placeholder)', 'WELL', 'GROUNDWATER', false, null, 'بديل مؤقت — يُستبدل بالبئر الحقيقي'),
  ('W-TMP-07', 'بئر 7 (مؤقت)', 'Well 7 (placeholder)', 'WELL', 'GROUNDWATER', false, null, 'بديل مؤقت — يُستبدل بالبئر الحقيقي'),
  -- Israeli connections feeding the line (2 placeholders). Ordinary sources; supply_type = ISRAELI.
  ('IC-TMP-01', 'وصلة إسرائيلية 1 (مؤقت)', 'Israeli connection 1 (placeholder)', 'ISRAELI_CONNECTION', 'ISRAELI', false, null, 'بديل مؤقت — نقرأ عدادنا يوميًا بعد عداد ميكوروت'),
  ('IC-TMP-02', 'وصلة إسرائيلية 2 (مؤقت)', 'Israeli connection 2 (placeholder)', 'ISRAELI_CONNECTION', 'ISRAELI', false, null, 'بديل مؤقت — نقرأ عدادنا يوميًا بعد عداد ميكوروت'),
  -- Saeer intermediate tank: a pass-through buffer (inlet ≈ outlet). Capacity/height unknown → NULL,
  -- so storage stays NULL until real geometry is entered (never invent "1 m = 5,000 m³").
  ('TNK-SAEER', 'الخزان الوسيط — سعير', 'Saeer intermediate tank', 'TANK', null, true,
     extensions.ST_SetSRID(extensions.ST_MakePoint(35.155, 31.595), 4326), 'خزان عبور: الداخل يُضخ فورًا؛ الإحداثيات تقريبية'),
  ('PS-SAEER', 'محطة ضخ سعير', 'Saeer pumping station', 'PUMPING_STATION', null, false,
     extensions.ST_SetSRID(extensions.ST_MakePoint(35.155, 31.595), 4326), 'الإحداثيات تقريبية')
) as v(code, name_ar, name_en, asset_type, supply_type, is_pass_through, geom, description_ar)
on conflict (code) do update
  set name_ar = excluded.name_ar,
      name_en = excluded.name_en,
      is_pass_through = excluded.is_pass_through,
      description_ar = excluded.description_ar;

-- Measurement points -------------------------------------------------------------
-- One SOURCE_METER per source; Saeer tank gets SEPARATE inlet and outlet meters (never merged).
with area as (select id from public.areas where code = 'HEB')
insert into public.measurement_points (code, name_ar, name_en, point_type, asset_id, area_id, expects_daily_reading)
select v.code, v.name_ar, v.name_en, v.point_type, a.id, area.id, true
from area,
(values
  ('MP-W-TMP-01',     'W-TMP-01',  'عداد بئر 1 (مؤقت)',              'Well 1 meter (placeholder)',        'SOURCE_METER'),
  ('MP-W-TMP-02',     'W-TMP-02',  'عداد بئر 2 (مؤقت)',              'Well 2 meter (placeholder)',        'SOURCE_METER'),
  ('MP-W-TMP-03',     'W-TMP-03',  'عداد بئر 3 (مؤقت)',              'Well 3 meter (placeholder)',        'SOURCE_METER'),
  ('MP-W-TMP-04',     'W-TMP-04',  'عداد بئر 4 (مؤقت)',              'Well 4 meter (placeholder)',        'SOURCE_METER'),
  ('MP-W-TMP-05',     'W-TMP-05',  'عداد بئر 5 (مؤقت)',              'Well 5 meter (placeholder)',        'SOURCE_METER'),
  ('MP-W-TMP-06',     'W-TMP-06',  'عداد بئر 6 (مؤقت)',              'Well 6 meter (placeholder)',        'SOURCE_METER'),
  ('MP-W-TMP-07',     'W-TMP-07',  'عداد بئر 7 (مؤقت)',              'Well 7 meter (placeholder)',        'SOURCE_METER'),
  ('MP-IC-TMP-01',    'IC-TMP-01', 'عداد الوصلة الإسرائيلية 1 (مؤقت)', 'Israeli conn. 1 meter (placeholder)', 'SOURCE_METER'),
  ('MP-IC-TMP-02',    'IC-TMP-02', 'عداد الوصلة الإسرائيلية 2 (مؤقت)', 'Israeli conn. 2 meter (placeholder)', 'SOURCE_METER'),
  ('MP-TNK-SAEER-IN', 'TNK-SAEER', 'عداد مدخل خزان سعير',            'Saeer tank inlet meter',            'TANK_INLET_METER'),
  ('MP-TNK-SAEER-OUT','TNK-SAEER', 'عداد مخرج خزان سعير',            'Saeer tank outlet meter',           'TANK_OUTLET_METER')
) as v(code, asset_code, name_ar, name_en, point_type)
join public.water_assets a on a.code = v.asset_code
on conflict (code) do update
  set name_ar = excluded.name_ar,
      name_en = excluded.name_en,
      point_type = excluded.point_type,
      asset_id = excluded.asset_id;

-- Water paths (topology as data) ---------------------------------------------------
-- Every source injects into the main transmission line, which ends at the Saeer tank.
-- The line itself is NOT modelled pipe by pipe (SPEC §3.6): one logical path per source.
insert into public.water_paths (from_asset_id, to_asset_id, connection_type, sequence_order, name_ar, name_en)
select s.id, t.id, 'TRANSMISSION_MAIN', row_number() over (order by s.code),
       'خط النقل الرئيسي — ' || s.name_ar, 'Main transmission line — ' || coalesce(s.name_en, s.code)
from public.water_assets s
join public.water_assets t on t.code = 'TNK-SAEER'
where s.asset_type in ('WELL','ISRAELI_CONNECTION')
  and s.code in ('W-TMP-01','W-TMP-02','W-TMP-03','W-TMP-04','W-TMP-05','W-TMP-06','W-TMP-07','IC-TMP-01','IC-TMP-02')
  and not exists (select 1 from public.water_paths p where p.from_asset_id = s.id and p.to_asset_id = t.id);

-- Tank → pumping station (onward pumping; the Halahoul leg is added in Stage 8)
insert into public.water_paths (from_asset_id, to_asset_id, connection_type, sequence_order, name_ar, name_en)
select t.id, ps.id, 'INTERNAL', 100, 'خزان سعير ← محطة ضخ سعير', 'Saeer tank → Saeer pumping station'
from public.water_assets t
join public.water_assets ps on ps.code = 'PS-SAEER'
where t.code = 'TNK-SAEER'
  and not exists (select 1 from public.water_paths p where p.from_asset_id = t.id and p.to_asset_id = ps.id);

-- Balance zone: Saeer transit -------------------------------------------------------
-- INFLOW  = all sources; ARRIVAL = Saeer inlet meter; no STORAGE term (transit node).
-- OUTFLOW (route take-offs) has no metered points yet → the difference is shown as "unexplained".
insert into public.balance_zones (code, name_ar, name_en, description)
values ('SAEER-TRANSIT', 'الواصل إلى الخزان الوسيط — سعير', 'Arrivals at Saeer intermediate tank',
        'المضخوخ من كل المصادر مقابل الواصل إلى مدخل خزان سعير. الفرق = مسحوبات الطريق + فواقد + أخطاء إدخال.')
on conflict (code) do update set name_ar = excluded.name_ar, name_en = excluded.name_en, description = excluded.description;

insert into public.balance_zone_members (zone_id, measurement_point_id, role, measurement_quality, sign)
select z.id, mp.id, 'INFLOW', 'MEASURED', 1
from public.balance_zones z
join public.measurement_points mp on mp.point_type = 'SOURCE_METER'
join public.water_assets a on a.id = mp.asset_id and a.asset_type in ('WELL','ISRAELI_CONNECTION')
where z.code = 'SAEER-TRANSIT'
on conflict (zone_id, measurement_point_id) where measurement_point_id is not null do nothing;

insert into public.balance_zone_members (zone_id, measurement_point_id, role, measurement_quality, sign)
select z.id, mp.id, 'ARRIVAL', 'MEASURED', 1
from public.balance_zones z
join public.measurement_points mp on mp.code = 'MP-TNK-SAEER-IN'
where z.code = 'SAEER-TRANSIT'
on conflict (zone_id, measurement_point_id) where measurement_point_id is not null do nothing;
