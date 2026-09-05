-- =============================================================================
-- 0016  Stage 3 support
--   * calculate_zone_balance(): adds per-supply-type source counts, so the Saeer screen can
--     print "آبار جوفية (5 من 7)" — a total never appears without its completeness.
--   * get_daily_entry_tasks(): the morning task list, DERIVED from measurement points +
--     assignments + missing readings. There is deliberately no tasks table.
-- Both are SECURITY INVOKER: the caller's RLS scope decides what they see.
-- Re-runnable.
-- =============================================================================

drop function if exists public.calculate_zone_balance(uuid, date, date);

create function public.calculate_zone_balance(p_zone_id uuid, p_from date, p_to date)
returns table (
  zone_id                     uuid,
  period_from                 date,
  period_to                   date,
  days                        int,
  inflow_m3                   numeric,
  inflow_groundwater_m3       numeric,
  inflow_israeli_m3           numeric,
  outflow_measured_m3         numeric,
  arrival_m3                  numeric,
  opening_storage_m3          numeric,
  closing_storage_m3          numeric,
  storage_change_m3           numeric,
  storage_complete            boolean,
  difference_m3               numeric,
  difference_pct              numeric,
  unmeasured_members          int,
  points_expected             int,
  points_complete             int,
  point_days_expected         int,
  point_days_reported         int,
  sources_total               int,
  sources_operating           int,
  sources_groundwater_total   int,
  sources_groundwater_reported int,
  sources_israeli_total       int,
  sources_israeli_reported    int,
  stopped_sources             jsonb,
  by_role                     jsonb
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
  -- One row per point member: prorated volume over the window + how many days it covered.
  member_stats as (
    select m.id, m.role, m.sign, m.measurement_point_id,
           mp.is_active, mp.expects_daily_reading,
           a.id as asset_id, a.supply_type, a.code as asset_code,
           a.name_ar as asset_name_ar, a.name_en as asset_name_en,
           coalesce(vv.v, 0)              as v,
           coalesce(cc.days_reported, 0)  as days_reported
    from members m
    join public.measurement_points mp on mp.id = m.measurement_point_id
    left join public.water_assets a on a.id = mp.asset_id
    left join lateral (
      select sum(r.volume_m3
                 * (least(r.covers_to, p_to) - greatest(r.covers_from, p_from) + 1)::numeric
                 / r.days_covered) as v
      from public.readings r
      where r.measurement_point_id = m.measurement_point_id
        and not r.is_superseded
        and r.covers_from <= p_to and r.covers_to >= p_from
    ) vv on true
    left join lateral (
      select count(*) as days_reported
      from generate_series(p_from, p_to, interval '1 day') d
      where exists (
        select 1 from public.readings r
        where r.measurement_point_id = m.measurement_point_id
          and not r.is_superseded
          and r.covers_from <= d::date and r.covers_to >= d::date)
    ) cc on true
    where m.measurement_point_id is not null
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
  agg_storage as (
    select (select count(*) from storage_assets) as n,
           sum(opening) as opening, sum(closing) as closing,
           bool_and(opening is not null and closing is not null) as complete
    from storage_assets
  ),
  -- latest operational status of each inflow source within the window
  src_status as (
    select s.asset_id, s.asset_code, s.asset_name_ar, s.asset_name_en, s.supply_type,
           (select r.operational_status
              from public.readings r
              join public.measurement_points mp on mp.id = r.measurement_point_id
             where mp.asset_id = s.asset_id and not r.is_superseded
               and r.operational_status is not null
               and r.covers_from <= p_to and r.covers_to >= p_from
             order by r.covers_to desc, r.entered_at desc limit 1) as status
    from (select distinct asset_id, asset_code, asset_name_ar, asset_name_en, supply_type
            from member_stats where role = 'INFLOW' and asset_id is not null) s
  ),
  agg as (
    select
      coalesce(sum(v * sign) filter (where role = 'INFLOW'), 0)  as inflow,
      coalesce(sum(v * sign) filter (where role = 'OUTFLOW'), 0) as outflow,
      coalesce(sum(v * sign) filter (where role = 'ARRIVAL'), 0) as arrival,
      coalesce(sum(v) filter (where role = 'INFLOW' and supply_type = 'GROUNDWATER'), 0) as gw,
      coalesce(sum(v) filter (where role = 'INFLOW' and supply_type = 'ISRAELI'), 0)     as il,
      count(*) filter (where role = 'INFLOW' and supply_type = 'GROUNDWATER')::int                       as gw_total,
      count(*) filter (where role = 'INFLOW' and supply_type = 'GROUNDWATER' and days_reported > 0)::int as gw_reported,
      count(*) filter (where role = 'INFLOW' and supply_type = 'ISRAELI')::int                           as il_total,
      count(*) filter (where role = 'INFLOW' and supply_type = 'ISRAELI' and days_reported > 0)::int     as il_reported,
      count(*) filter (where is_active and expects_daily_reading)::int                                   as points_expected,
      count(*) filter (where is_active and expects_daily_reading and days_reported = v_days)::int        as points_complete,
      (count(*) filter (where is_active and expects_daily_reading) * v_days)::int                        as point_days_expected,
      coalesce(sum(days_reported) filter (where is_active and expects_daily_reading), 0)::int            as point_days_reported
    from member_stats
  ),
  role_breakdown as (
    select coalesce(jsonb_object_agg(role, jsonb_build_object(
             'points_expected', pe, 'points_complete', pc, 'volume_m3', vv)), '{}'::jsonb) as j
    from (
      select role,
             count(*) filter (where is_active and expects_daily_reading)::int                    as pe,
             count(*) filter (where is_active and expects_daily_reading
                                and days_reported = v_days)::int                                 as pc,
             coalesce(sum(v), 0)                                                                 as vv
      from member_stats
      group by role
    ) x
  )
  select
    p_zone_id, p_from, p_to, v_days,
    round(a.inflow, 2),
    round(a.gw, 2),
    round(a.il, 2),
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
               - case when st.n = 0 then 0 when st.complete then st.closing - st.opening else 0 end)
              / a.inflow * 100, 1)
         else null end,
    (select count(*)::int from members m where m.measurement_quality = 'UNMEASURED'),
    a.points_expected,
    a.points_complete,
    a.point_days_expected,
    a.point_days_reported,
    (select count(*)::int from src_status),
    (select count(*)::int from src_status where status = 'OPERATING'),
    a.gw_total, a.gw_reported, a.il_total, a.il_reported,
    (select coalesce(jsonb_agg(jsonb_build_object(
              'asset_id', asset_id, 'code', asset_code, 'name_ar', asset_name_ar,
              'name_en', asset_name_en, 'status', status) order by asset_code), '[]'::jsonb)
       from src_status where status is not null and status <> 'OPERATING'),
    br.j
  from agg a
  cross join agg_storage st
  cross join role_breakdown br;
end;
$$;

-- ---------------------------------------------------------------------------
-- get_daily_entry_tasks: what this user must enter for one operational day.
-- Derived, never stored. Points already entered come back with their reading attached
-- so the UI can tick them off. Service-provider meters (expects_daily_reading = false)
-- are excluded by design — they are billed monthly, not read daily.
-- ---------------------------------------------------------------------------
create or replace function public.get_daily_entry_tasks(p_date date)
returns table (
  measurement_point_id  uuid,
  code                  text,
  name_ar               text,
  name_en               text,
  point_type            text,
  asset_id              uuid,
  asset_code            text,
  asset_name_ar         text,
  asset_type            text,
  supply_type           text,
  area_id               uuid,
  is_assigned           boolean,
  reading_id            uuid,
  volume_m3             numeric,
  operational_status    text,
  entry_basis           text,
  validation_status     text,
  entered_at            timestamptz
)
language sql
stable
as $$
  select mp.id, mp.code, mp.name_ar, mp.name_en, mp.point_type,
         a.id, a.code, a.name_ar, a.asset_type, a.supply_type, mp.area_id,
         mp.id in (select app.assigned_point_ids()),
         r.id, r.volume_m3, r.operational_status, r.entry_basis, r.validation_status, r.entered_at
  from public.measurement_points mp
  left join public.water_assets a on a.id = mp.asset_id
  left join lateral (
    select r.id, r.volume_m3, r.operational_status, r.entry_basis, r.validation_status, r.entered_at
    from public.readings r
    where r.measurement_point_id = mp.id
      and not r.is_superseded
      and r.covers_from <= p_date and r.covers_to >= p_date
    order by r.entered_at desc
    limit 1
  ) r on true
  where mp.is_active
    and mp.expects_daily_reading
  order by (r.id is not null), a.asset_type nulls last, mp.code;
$$;

grant execute on function public.calculate_zone_balance(uuid, date, date) to authenticated;
grant execute on function public.get_daily_entry_tasks(date)              to authenticated;
revoke execute on function public.calculate_zone_balance(uuid, date, date) from anon, public;
revoke execute on function public.get_daily_entry_tasks(date)             from anon, public;
