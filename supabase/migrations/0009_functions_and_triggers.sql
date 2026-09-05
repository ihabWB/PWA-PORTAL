-- =============================================================================
-- 0009  Server-side logic: audit, storage curve, validation flags, pass-through
--       check, status propagation, missing readings, zone balance
-- All calculations live here so every client gets the same answer.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Audit: written by triggers, never by application code
-- ---------------------------------------------------------------------------
create or replace function app.audit_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity_id uuid;
begin
  if tg_op = 'DELETE' then
    v_entity_id := old.id;
  else
    v_entity_id := new.id;
  end if;

  insert into public.audit_logs (user_id, action, entity_table, entity_id, old_value, new_value)
  values (
    auth.uid(),
    tg_op,
    tg_table_name,
    v_entity_id,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function app.ensure_audit_trigger(p_table regclass, p_events text)
returns void
language plpgsql
as $$
begin
  execute format('drop trigger if exists trg_audit on %s', p_table);
  execute format('create trigger trg_audit after %s on %s for each row execute function app.audit_row()',
                 p_events, p_table);
end;
$$;

select app.ensure_audit_trigger('public.readings',            'insert or update');
select app.ensure_audit_trigger('public.tank_level_readings', 'insert or update');
select app.ensure_audit_trigger('public.water_assets',        'insert or update');
select app.ensure_audit_trigger('public.measurement_points',  'insert or update or delete');
select app.ensure_audit_trigger('public.water_paths',         'insert or update or delete');
select app.ensure_audit_trigger('public.profiles',            'insert or update');
select app.ensure_audit_trigger('public.user_areas',          'insert or delete');
select app.ensure_audit_trigger('public.assignments',         'insert or update or delete');
select app.ensure_audit_trigger('public.balance_zone_members','insert or update or delete');
select app.ensure_audit_trigger('public.system_settings',     'insert or update');

-- ---------------------------------------------------------------------------
-- Alerts: raise once per (type, asset, point, date) while not resolved
-- ---------------------------------------------------------------------------
create or replace function app.raise_alert(
  p_type text, p_severity text,
  p_asset_id uuid, p_point_id uuid, p_reading_id uuid, p_reference_date date,
  p_description_ar text, p_description_en text, p_details jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  select id into v_id
  from public.alerts
  where alert_type = p_type
    and status <> 'RESOLVED'
    and asset_id is not distinct from p_asset_id
    and measurement_point_id is not distinct from p_point_id
    and reference_date is not distinct from p_reference_date
  limit 1;

  if v_id is not null then
    return v_id;   -- already open
  end if;

  insert into public.alerts (alert_type, severity, asset_id, measurement_point_id, reading_id,
                             reference_date, description_ar, description_en, details)
  values (p_type, p_severity, p_asset_id, p_point_id, p_reading_id,
          p_reference_date, p_description_ar, p_description_en, p_details)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- get_storage_m3: level→volume curve with linear interpolation; linear fallback
-- from capacity/height. Never hardcode geometry in application code.
-- ---------------------------------------------------------------------------
create or replace function public.get_storage_m3(p_asset_id uuid, p_level_m numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_points     int;
  v_lo_level   numeric; v_lo_vol numeric;
  v_hi_level   numeric; v_hi_vol numeric;
  v_capacity   numeric; v_height numeric;
begin
  if p_level_m is null then
    return null;
  end if;

  select count(*) into v_points from public.level_volume_curve where asset_id = p_asset_id;

  if v_points >= 2 then
    select level_m, volume_m3 into v_lo_level, v_lo_vol
    from public.level_volume_curve
    where asset_id = p_asset_id and level_m <= p_level_m
    order by level_m desc limit 1;

    select level_m, volume_m3 into v_hi_level, v_hi_vol
    from public.level_volume_curve
    where asset_id = p_asset_id and level_m >= p_level_m
    order by level_m asc limit 1;

    if v_lo_level is null then
      -- below the first curve point: interpolate from the origin
      if v_hi_level = 0 then return v_hi_vol; end if;
      return round(v_hi_vol * p_level_m / v_hi_level, 2);
    elsif v_hi_level is null then
      -- above the last curve point: extrapolate along the last segment
      select level_m, volume_m3 into v_hi_level, v_hi_vol
      from public.level_volume_curve
      where asset_id = p_asset_id and level_m < v_lo_level
      order by level_m desc limit 1;
      if v_hi_level is null or v_lo_level = v_hi_level then return v_lo_vol; end if;
      return round(v_lo_vol + (v_lo_vol - v_hi_vol) * (p_level_m - v_lo_level) / (v_lo_level - v_hi_level), 2);
    elsif v_lo_level = v_hi_level then
      return v_lo_vol;
    else
      return round(v_lo_vol + (v_hi_vol - v_lo_vol) * (p_level_m - v_lo_level) / (v_hi_level - v_lo_level), 2);
    end if;
  end if;

  -- Linear fallback
  select capacity_m3, height_m into v_capacity, v_height from public.water_assets where id = p_asset_id;
  if v_capacity is null or v_height is null or v_height = 0 then
    return null;   -- geometry unknown: store the level, leave storage null (never invent a number)
  end if;
  return round(p_level_m * v_capacity / v_height, 2);
end;
$$;

create or replace function app.tank_levels_compute_storage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_capacity numeric;
begin
  new.storage_m3 := public.get_storage_m3(new.asset_id, new.level_m);
  select capacity_m3 into v_capacity from public.water_assets where id = new.asset_id;
  if new.storage_m3 is not null and v_capacity is not null and v_capacity > 0 then
    new.percentage_full := round(new.storage_m3 / v_capacity * 100, 2);
  else
    new.percentage_full := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_tank_levels_compute_storage on public.tank_level_readings;
create trigger trg_tank_levels_compute_storage before insert on public.tank_level_readings
  for each row execute function app.tank_levels_compute_storage();

-- ---------------------------------------------------------------------------
-- flag_abnormal_reading: compare against the point's trailing mean/σ of daily volume.
-- FLAGS ONLY. Never rejects, never deletes. Inputs of the decision are stored in notes.
-- ---------------------------------------------------------------------------
create or replace function app.flag_abnormal_reading()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window  int     := app.setting_numeric('abnormal_reading_window', 30)::int;
  v_min     int     := app.setting_numeric('abnormal_reading_min_samples', 7)::int;
  v_sigma   numeric := app.setting_numeric('abnormal_reading_sigma', 3);
  v_daily   numeric;
  v_n       int;
  v_mean    numeric;
  v_sd      numeric;
  v_flag    boolean := false;
begin
  if new.is_superseded or new.validation_status <> 'OK' then
    return new;
  end if;

  v_daily := new.volume_m3 / (new.covers_to - new.covers_from + 1);

  select count(*), avg(d), stddev_samp(d)
    into v_n, v_mean, v_sd
  from (
    select r.volume_m3 / r.days_covered as d
    from public.readings r
    where r.measurement_point_id = new.measurement_point_id
      and not r.is_superseded
      and r.id is distinct from new.supersedes_id
      and r.covers_to < new.covers_from
    order by r.covers_from desc
    limit v_window
  ) s;

  if v_n >= v_min then
    if v_sd is not null and v_sd > 0 then
      v_flag := abs(v_daily - v_mean) > v_sigma * v_sd;
    elsif v_mean is not null and v_mean > 0 then
      v_flag := abs(v_daily - v_mean) / v_mean > 0.5;   -- flat history, large jump
    end if;
  end if;

  if v_flag then
    new.validation_status := 'FLAGGED';
    new.validation_notes  := format(
      'AUTO: daily %s m³ vs trailing mean %s ± %s m³ (n=%s, threshold %s σ)',
      round(v_daily, 1), round(v_mean, 1), round(coalesce(v_sd, 0), 1), v_n, v_sigma);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_readings_flag_abnormal on public.readings;
create trigger trg_readings_flag_abnormal before insert on public.readings
  for each row execute function app.flag_abnormal_reading();

-- ---------------------------------------------------------------------------
-- After a reading is stored: alerts + denormalised asset status + pass-through check
-- ---------------------------------------------------------------------------
create or replace function app.readings_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_point   public.measurement_points%rowtype;
  v_asset   public.water_assets%rowtype;
  v_in      numeric;
  v_out     numeric;
  v_base    numeric;
  v_pct     numeric;
  v_tol     numeric;
begin
  if new.is_superseded then
    return new;
  end if;

  select * into v_point from public.measurement_points where id = new.measurement_point_id;

  -- 1. Abnormal reading → alert
  if new.validation_status = 'FLAGGED' then
    perform app.raise_alert(
      'ABNORMAL_READING', 'WARNING',
      v_point.asset_id, new.measurement_point_id, new.id, new.covers_from,
      format('قراءة غير طبيعية عند %s ليوم %s: %s م³', v_point.name_ar, to_char(new.covers_from, 'DD/MM/YYYY'), new.volume_m3),
      format('Abnormal reading at %s for %s: %s m³', coalesce(v_point.name_en, v_point.code), to_char(new.covers_from, 'YYYY-MM-DD'), new.volume_m3),
      jsonb_build_object('volume_m3', new.volume_m3, 'days_covered', new.covers_to - new.covers_from + 1,
                         'validation_notes', new.validation_notes));
  end if;

  if v_point.asset_id is null then
    return new;
  end if;
  select * into v_asset from public.water_assets where id = v_point.asset_id;

  -- 2. Operational status lives on the reading; the asset keeps a denormalised CURRENT status
  --    for map rendering only. Update it when this reading is the latest for the asset.
  if new.operational_status is not null and not exists (
       select 1
       from public.readings r
       join public.measurement_points mp on mp.id = r.measurement_point_id
       where mp.asset_id = v_asset.id
         and not r.is_superseded
         and r.operational_status is not null
         and r.id <> new.id
         and r.covers_to > new.covers_to
  ) then
    update public.water_assets
       set current_status = new.operational_status
     where id = v_asset.id and current_status <> new.operational_status;

    if v_asset.asset_type in ('WELL','ISRAELI_CONNECTION') then
      if new.operational_status in ('STOPPED','DAMAGED') then
        perform app.raise_alert('SOURCE_STOPPED', 'WARNING', v_asset.id, null, new.id, new.covers_to,
          format('المصدر %s متوقف (%s) بتاريخ %s', v_asset.name_ar, new.operational_status, to_char(new.covers_to, 'DD/MM/YYYY')),
          format('Source %s is %s on %s', coalesce(v_asset.name_en, v_asset.code), new.operational_status, to_char(new.covers_to, 'YYYY-MM-DD')),
          jsonb_build_object('operational_status', new.operational_status));
      elsif new.operational_status = 'MAINTENANCE' then
        perform app.raise_alert('SOURCE_MAINTENANCE', 'INFO', v_asset.id, null, new.id, new.covers_to,
          format('المصدر %s في الصيانة بتاريخ %s', v_asset.name_ar, to_char(new.covers_to, 'DD/MM/YYYY')),
          format('Source %s under maintenance on %s', coalesce(v_asset.name_en, v_asset.code), to_char(new.covers_to, 'YYYY-MM-DD')),
          jsonb_build_object('operational_status', new.operational_status));
      end if;
    end if;
  end if;

  -- 3. Pass-through buffer: inlet and outlet for the same period must agree within tolerance.
  --    Threshold is data: asset override, else system_settings.pass_through_mismatch_pct.
  if v_asset.is_pass_through and v_point.point_type in ('TANK_INLET_METER','TANK_OUTLET_METER') then
    select sum(r.volume_m3) into v_in
    from public.readings r
    join public.measurement_points mp on mp.id = r.measurement_point_id
    where mp.asset_id = v_asset.id and mp.point_type = 'TANK_INLET_METER'
      and not r.is_superseded and r.covers_from = new.covers_from and r.covers_to = new.covers_to;

    select sum(r.volume_m3) into v_out
    from public.readings r
    join public.measurement_points mp on mp.id = r.measurement_point_id
    where mp.asset_id = v_asset.id and mp.point_type = 'TANK_OUTLET_METER'
      and not r.is_superseded and r.covers_from = new.covers_from and r.covers_to = new.covers_to;

    if v_in is not null and v_out is not null then
      v_base := greatest(v_in, v_out);
      if v_base > 0 then
        v_pct := abs(v_in - v_out) / v_base * 100;
        v_tol := coalesce(v_asset.pass_through_tolerance_pct, app.setting_numeric('pass_through_mismatch_pct', 3));
        if v_pct > v_tol then
          perform app.raise_alert('PASS_THROUGH_MISMATCH', 'WARNING', v_asset.id, null, new.id, new.covers_from,
            format('فرق %s٪ بين الداخل (%s م³) والخارج (%s م³) في %s ليوم %s — الحد %s٪',
                   round(v_pct, 1), v_in, v_out, v_asset.name_ar, to_char(new.covers_from, 'DD/MM/YYYY'), v_tol),
            format('%s%% mismatch between inlet (%s m³) and outlet (%s m³) at %s for %s — threshold %s%%',
                   round(v_pct, 1), v_in, v_out, coalesce(v_asset.name_en, v_asset.code), to_char(new.covers_from, 'YYYY-MM-DD'), v_tol),
            jsonb_build_object('inlet_m3', v_in, 'outlet_m3', v_out, 'difference_pct', round(v_pct, 2),
                               'threshold_pct', v_tol, 'covers_from', new.covers_from, 'covers_to', new.covers_to));
        end if;
      end if;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_readings_after_insert on public.readings;
create trigger trg_readings_after_insert after insert on public.readings
  for each row execute function app.readings_after_insert();

-- ---------------------------------------------------------------------------
-- get_missing_readings: active points expecting a daily reading with no non-superseded
-- row covering the day. SECURITY INVOKER → the caller's RLS scope applies.
-- ---------------------------------------------------------------------------
create or replace function public.get_missing_readings(p_from date, p_to date, p_area_id uuid default null)
returns table (
  measurement_point_id  uuid,
  code                  text,
  name_ar               text,
  name_en               text,
  area_id               uuid,
  asset_id              uuid,
  missing_date          date,
  assigned_user_id      uuid,
  assigned_user_name_ar text
)
language sql
stable
as $$
  select mp.id, mp.code, mp.name_ar, mp.name_en, mp.area_id, mp.asset_id,
         d::date,
         a.user_id,
         p.full_name_ar
  from public.measurement_points mp
  cross join generate_series(p_from, p_to, interval '1 day') d
  left join lateral (
    select asg.user_id
    from public.assignments asg
    where asg.measurement_point_id = mp.id
      and asg.active_from <= d::date
      and (asg.active_to is null or asg.active_to >= d::date)
    order by asg.active_from desc
    limit 1
  ) a on true
  left join public.profiles p on p.id = a.user_id
  where mp.is_active
    and mp.expects_daily_reading
    and (p_area_id is null or mp.area_id = p_area_id)
    and not exists (
      select 1 from public.readings r
      where r.measurement_point_id = mp.id
        and not r.is_superseded
        and r.covers_from <= d::date
        and r.covers_to   >= d::date
    )
  order by d, mp.code;
$$;

-- ---------------------------------------------------------------------------
-- calculate_zone_balance: inflow, measured outflow, arrival, storage change,
-- difference (= unexplained) AND data completeness. Readings spanning the range
-- boundary are prorated by overlapping days. SECURITY INVOKER.
-- ---------------------------------------------------------------------------
create or replace function public.calculate_zone_balance(p_zone_id uuid, p_from date, p_to date)
returns table (
  zone_id                 uuid,
  period_from             date,
  period_to               date,
  days                    int,
  inflow_m3               numeric,
  inflow_groundwater_m3   numeric,
  inflow_israeli_m3       numeric,
  outflow_measured_m3     numeric,
  arrival_m3              numeric,
  opening_storage_m3      numeric,
  closing_storage_m3      numeric,
  storage_change_m3       numeric,
  storage_complete        boolean,
  difference_m3           numeric,
  difference_pct          numeric,
  unmeasured_members      int,
  points_expected         int,
  points_complete         int,
  point_days_expected     int,
  point_days_reported     int,
  sources_total           int,
  sources_operating       int,
  stopped_sources         jsonb,
  by_role                 jsonb
)
language plpgsql
stable
as $$
declare
  v_days int := p_to - p_from + 1;
begin
  if p_to < p_from then
    raise exception 'p_to must be >= p_from' using errcode = '22023';
  end if;

  return query
  with members as (
    select m.id, m.role, m.measurement_quality, m.sign, m.measurement_point_id, m.asset_id
    from public.balance_zone_members m
    where m.zone_id = p_zone_id
  ),
  -- prorated volume per member point over the period
  vol as (
    select m.id as member_id, m.role, m.sign, m.measurement_point_id,
           coalesce(sum(r.volume_m3
                        * (least(r.covers_to, p_to) - greatest(r.covers_from, p_from) + 1)::numeric
                        / r.days_covered), 0) as v
    from members m
    left join public.readings r
      on r.measurement_point_id = m.measurement_point_id
     and not r.is_superseded
     and r.covers_from <= p_to and r.covers_to >= p_from
    where m.measurement_point_id is not null
    group by m.id, m.role, m.sign, m.measurement_point_id
  ),
  -- completeness per member point: number of days in range covered by a reading
  cov as (
    select m.id as member_id, m.role,
           count(*) filter (where exists (
             select 1 from public.readings r
             where r.measurement_point_id = m.measurement_point_id
               and not r.is_superseded
               and r.covers_from <= d::date and r.covers_to >= d::date)) as days_reported
    from members m
    join public.measurement_points mp on mp.id = m.measurement_point_id
    cross join generate_series(p_from, p_to, interval '1 day') d
    where mp.is_active and mp.expects_daily_reading
    group by m.id, m.role
  ),
  -- supply split for INFLOW members
  supply as (
    select v.member_id, a.supply_type, a.id as asset_id, a.code, a.name_ar, a.name_en
    from vol v
    join public.measurement_points mp on mp.id = v.measurement_point_id
    left join public.water_assets a on a.id = mp.asset_id
    where v.role = 'INFLOW'
  ),
  -- latest operational status per inflow source within the period
  src_status as (
    select s.asset_id, s.code, s.name_ar, s.name_en,
           (select r.operational_status
              from public.readings r
              join public.measurement_points mp on mp.id = r.measurement_point_id
             where mp.asset_id = s.asset_id and not r.is_superseded
               and r.operational_status is not null
               and r.covers_from <= p_to and r.covers_to >= p_from
             order by r.covers_to desc, r.entered_at desc limit 1) as status
    from (select distinct asset_id, code, name_ar, name_en from supply where asset_id is not null) s
  ),
  storage_assets as (
    select m.asset_id,
           (select t.storage_m3 from public.tank_level_readings t
             where t.asset_id = m.asset_id and not t.is_superseded and t.reading_date < p_from
             order by t.reading_date desc, t.reading_time desc limit 1) as opening,
           (select t.storage_m3 from public.tank_level_readings t
             where t.asset_id = m.asset_id and not t.is_superseded and t.reading_date <= p_to
             order by t.reading_date desc, t.reading_time desc limit 1) as closing
    from members m where m.role = 'STORAGE'
  ),
  agg as (
    select
      coalesce(sum(v.v * v.sign) filter (where v.role = 'INFLOW'), 0)  as inflow,
      coalesce(sum(v.v * v.sign) filter (where v.role = 'OUTFLOW'), 0) as outflow,
      coalesce(sum(v.v * v.sign) filter (where v.role = 'ARRIVAL'), 0) as arrival
    from vol v
  ),
  agg_supply as (
    select
      coalesce(sum(v.v) filter (where s.supply_type = 'GROUNDWATER'), 0) as gw,
      coalesce(sum(v.v) filter (where s.supply_type = 'ISRAELI'), 0)     as il
    from vol v join supply s on s.member_id = v.member_id
  ),
  agg_storage as (
    select
      (select count(*) from storage_assets) as n,
      sum(opening) as opening,
      sum(closing) as closing,
      bool_and(opening is not null and closing is not null) as complete
    from storage_assets
  ),
  agg_cov as (
    select
      count(*)::int                                            as points_expected,
      (count(*) filter (where days_reported = v_days))::int    as points_complete,
      (count(*) * v_days)::int                                 as point_days_expected,
      coalesce(sum(days_reported), 0)::int                     as point_days_reported
    from cov
  ),
  role_breakdown as (
    select coalesce(jsonb_object_agg(role, jsonb_build_object(
             'points_expected', pe, 'points_complete', pc, 'volume_m3', vv)), '{}'::jsonb) as j
    from (
      select m.role,
             count(distinct c.member_id)                                             as pe,
             count(distinct c.member_id) filter (where c.days_reported = v_days)     as pc,
             coalesce(sum(distinct_v.v), 0)                                          as vv
      from members m
      left join cov c on c.member_id = m.id
      left join (select member_id, v from vol) distinct_v on distinct_v.member_id = m.id
      where m.measurement_point_id is not null
      group by m.role
    ) x
  )
  select
    p_zone_id,
    p_from,
    p_to,
    v_days,
    round(a.inflow, 2),
    round(sp.gw, 2),
    round(sp.il, 2),
    round(a.outflow, 2),
    round(a.arrival, 2),
    st.opening,
    st.closing,
    case when st.n = 0 then 0 when st.complete then st.closing - st.opening else null end,
    case when st.n = 0 then true else coalesce(st.complete, false) end,
    round(a.inflow - a.outflow - a.arrival
          - case when st.n = 0 then 0 when st.complete then st.closing - st.opening else 0 end, 2),
    case when a.inflow > 0
         then round((a.inflow - a.outflow - a.arrival
               - case when st.n = 0 then 0 when st.complete then st.closing - st.opening else 0 end) / a.inflow * 100, 1)
         else null end,
    (select count(*)::int from members m where m.measurement_quality = 'UNMEASURED'),
    c.points_expected,
    c.points_complete,
    c.point_days_expected,
    c.point_days_reported,
    (select count(*)::int from src_status),
    (select count(*)::int from src_status where status = 'OPERATING'),
    (select coalesce(jsonb_agg(jsonb_build_object('asset_id', asset_id, 'code', code, 'name_ar', name_ar,
                                                  'name_en', name_en, 'status', status)
                               order by code), '[]'::jsonb)
       from src_status where status is not null and status <> 'OPERATING'),
    br.j
  from agg a
  cross join agg_supply sp
  cross join agg_storage st
  cross join agg_cov c
  cross join role_breakdown br;
end;
$$;

grant execute on function public.get_storage_m3(uuid, numeric)               to authenticated;
grant execute on function public.get_missing_readings(date, date, uuid)      to authenticated;
grant execute on function public.calculate_zone_balance(uuid, date, date)    to authenticated;
revoke execute on function public.get_storage_m3(uuid, numeric)              from anon, public;
revoke execute on function public.get_missing_readings(date, date, uuid)     from anon, public;
revoke execute on function public.calculate_zone_balance(uuid, date, date)   from anon, public;
