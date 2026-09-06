-- =============================================================================
-- 0019  Prerequisites for the real Aleizariya + Saeer topology
--
-- Everything here is independent of the operational data still to be entered, so the
-- catalogue can be filled in once and completely. The balance zones themselves come
-- afterwards, when the real measurement points exist.
--
-- 1. A MAIN_METER may carry a supply type. MM-TJ-06-07 is fed from a neighbouring
--    Israeli system; without this the Saeer screen would show a groundwater + israeli
--    split that does not add up to the total.
-- 2. measurement_points.excluded_from_balance marks a point measured UPSTREAM of a
--    storage node, whose volume is already counted again at the downstream inlet.
--    A trigger refuses to put such a point in any balance zone. This is data, not a
--    code pattern: matching codes ending in -SRC would break the topology-is-data rule.
-- 3. One point may be an INFLOW member of at most ONE zone, enforced by a partial
--    unique index. ARRIVAL in one zone and INFLOW in the next stays legal, which is
--    exactly how the Aleizariya station outlet feeds the Saeer balance.
-- 4. A zero volume that the reading itself explains (the source was stopped) is not an
--    anomaly, and stopped days no longer distort the trailing baseline. Aleizariya
--    Well 3 runs intermittently, so a zero day is normal there — but the rule is
--    general rather than a per-point exception.
--
-- Re-runnable.
-- =============================================================================

-- ---- 1. supply type on a main meter ------------------------------------------
alter table public.water_assets drop constraint if exists water_assets_supply_type_chk;
alter table public.water_assets
  add constraint water_assets_supply_type_chk check (
    (asset_type in ('WELL','SPRING')            and supply_type = 'GROUNDWATER')
    or (asset_type = 'ISRAELI_CONNECTION'       and supply_type = 'ISRAELI')
    -- a main meter may sit on either kind of supply, or on none yet
    or (asset_type = 'MAIN_METER')
    or (asset_type not in ('WELL','SPRING','ISRAELI_CONNECTION','MAIN_METER')
        and supply_type is null)
  );

-- ---- 2. points measured upstream of a storage node ----------------------------
alter table public.measurement_points
  add column if not exists excluded_from_balance boolean not null default false;

comment on column public.measurement_points.excluded_from_balance is
  'Measured upstream of a storage node: the same water is counted again at the downstream '
  'inlet, so this point must never join a balance zone.';

create or replace function app.guard_balance_zone_member()
returns trigger
language plpgsql
as $$
declare
  v_excluded boolean;
  v_code     text;
begin
  if new.measurement_point_id is null then
    return new;
  end if;

  select mp.excluded_from_balance, mp.code into v_excluded, v_code
  from public.measurement_points mp where mp.id = new.measurement_point_id;

  if v_excluded then
    raise exception
      'Measurement point % is measured upstream of a storage node and cannot join a balance zone; '
      'its water is already counted at the downstream inlet', v_code
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_zone_member on public.balance_zone_members;
create trigger trg_guard_zone_member
  before insert or update on public.balance_zone_members
  for each row execute function app.guard_balance_zone_member();

-- ---- 3. one INFLOW membership per point, across every zone --------------------
create unique index if not exists balance_zone_members_single_inflow_uq
  on public.balance_zone_members (measurement_point_id)
  where role = 'INFLOW' and measurement_point_id is not null;

-- ---- 4. a zero the reading explains is not an anomaly -------------------------
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

  -- A source that reported zero AND said it was not running has explained itself.
  -- Flagging it would train operators to ignore the flag.
  if new.volume_m3 = 0
     and new.operational_status in ('STOPPED','MAINTENANCE','DAMAGED') then
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
      -- stopped days describe downtime, not the normal operating range; keeping them
      -- would drag the mean down and flag an ordinary day once the source restarts
      and not (r.volume_m3 = 0
               and r.operational_status in ('STOPPED','MAINTENANCE','DAMAGED'))
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

-- ---- upsert_measurement_point learns the new column ---------------------------
-- The old ten-argument signature is dropped rather than left as an overload: a caller that
-- still used it would silently reset excluded_from_balance to its default.
drop function if exists public.upsert_measurement_point(
  uuid, text, text, text, text, uuid, uuid, uuid, boolean, boolean);

create function public.upsert_measurement_point(
  p_id                    uuid,
  p_code                  text,
  p_name_ar               text,
  p_name_en               text,
  p_point_type            text,
  p_asset_id              uuid,
  p_water_path_id         uuid,
  p_area_id               uuid,
  p_expects_daily_reading boolean,
  p_is_active             boolean,
  p_excluded_from_balance boolean default false
)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  if p_asset_id is null and p_water_path_id is null then
    raise exception 'A measurement point must sit on an asset or on a water path' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.measurement_points (
      code, name_ar, name_en, point_type, asset_id, water_path_id, area_id,
      expects_daily_reading, is_active, excluded_from_balance)
    values (
      upper(btrim(p_code)), btrim(p_name_ar), nullif(btrim(coalesce(p_name_en, '')), ''),
      p_point_type, p_asset_id, p_water_path_id, p_area_id,
      coalesce(p_expects_daily_reading, true), coalesce(p_is_active, true),
      coalesce(p_excluded_from_balance, false))
    returning id into v_id;
    return v_id;
  end if;

  update public.measurement_points set
    code                  = upper(btrim(p_code)),
    name_ar               = btrim(p_name_ar),
    name_en               = nullif(btrim(coalesce(p_name_en, '')), ''),
    point_type            = p_point_type,
    asset_id              = p_asset_id,
    water_path_id         = p_water_path_id,
    area_id               = p_area_id,
    expects_daily_reading = coalesce(p_expects_daily_reading, true),
    is_active             = coalesce(p_is_active, true),
    excluded_from_balance = coalesce(p_excluded_from_balance, false)
  where id = p_id
  returning id into v_id;

  if v_id is null then
    raise exception 'Measurement point % not found or not writable', p_id using errcode = '42501';
  end if;
  return v_id;
end;
$$;

-- get_asset_points exposes the flag so the screens can show it.
-- Dropped first: adding a column changes the return type, which CREATE OR REPLACE refuses.
drop function if exists public.get_asset_points(uuid);

create function public.get_asset_points(p_asset_id uuid)
returns table (
  id                    uuid,
  code                  text,
  name_ar               text,
  name_en               text,
  point_type            text,
  expects_daily_reading boolean,
  is_active             boolean,
  excluded_from_balance boolean,
  is_placeholder        boolean,
  reading_count         bigint,
  last_reading_date     date
)
language sql
stable
as $$
  select mp.id, mp.code, mp.name_ar, mp.name_en, mp.point_type,
         mp.expects_daily_reading, mp.is_active, mp.excluded_from_balance,
         mp.code like '%TMP%',
         (select count(*) from public.readings r
           where r.measurement_point_id = mp.id and not r.is_superseded),
         (select max(r.covers_to) from public.readings r
           where r.measurement_point_id = mp.id and not r.is_superseded)
  from public.measurement_points mp
  where mp.asset_id = p_asset_id
  order by mp.point_type, mp.code;
$$;

grant execute on function
  public.upsert_measurement_point(uuid, text, text, text, text, uuid, uuid, uuid, boolean, boolean, boolean),
  public.get_asset_points(uuid)
to authenticated;

-- ---- the catalogue must return external_reference ----------------------------
-- Without it the asset form would load an empty field and silently blank the official
-- well number on the next save.
drop function if exists public.get_asset_catalogue(boolean);

create function public.get_asset_catalogue(p_include_retired boolean default true)
returns table (
  id                    uuid,
  code                  text,
  name_ar               text,
  name_en               text,
  asset_type            text,
  supply_type           text,
  area_id               uuid,
  area_name_ar          text,
  current_status        text,
  longitude             double precision,
  latitude              double precision,
  capacity_m3           numeric,
  height_m              numeric,
  is_pass_through       boolean,
  external_reference    text,
  description_ar        text,
  operational_start_date date,
  operational_end_date  date,
  is_retired            boolean,
  is_placeholder        boolean,
  point_count           bigint,
  reading_count         bigint
)
language sql
stable
as $$
  select a.id, a.code, a.name_ar, a.name_en, a.asset_type, a.supply_type,
         a.area_id, ar.name_ar,
         a.current_status,
         case when a.geom is null then null else extensions.ST_X(a.geom) end,
         case when a.geom is null then null else extensions.ST_Y(a.geom) end,
         a.capacity_m3, a.height_m, a.is_pass_through,
         a.external_reference, a.description_ar,
         a.operational_start_date, a.operational_end_date,
         a.operational_end_date is not null,
         a.code like '%TMP%',
         (select count(*) from public.measurement_points mp where mp.asset_id = a.id),
         (select count(*) from public.readings r
           join public.measurement_points mp on mp.id = r.measurement_point_id
          where mp.asset_id = a.id and not r.is_superseded)
  from public.water_assets a
  left join public.areas ar on ar.id = a.area_id
  where p_include_retired or a.operational_end_date is null
  order by a.asset_type, a.code;
$$;

grant execute on function public.get_asset_catalogue(boolean) to authenticated;
revoke execute on function public.get_asset_catalogue(boolean) from anon, public;
