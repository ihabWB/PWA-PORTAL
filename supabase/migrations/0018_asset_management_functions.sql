-- =============================================================================
-- 0018  Stage 5 write path: assets, measurement points, water paths
--
-- Writes go through functions so three rules live in one place instead of in every client:
--   * nothing is deleted — retiring an asset is a status plus operational_end_date;
--   * geometry is built in SQL from longitude/latitude, and a NULL stays NULL: an empty
--     coordinate is more honest than an invented one;
--   * topology is data — adding a path never requires a code change.
--
-- All SECURITY INVOKER: the RLS policies from 0010 decide who may write.
-- Re-runnable.
-- =============================================================================

create or replace function public.upsert_water_asset(
  p_id                     uuid,
  p_code                   text,
  p_name_ar                text,
  p_name_en                text,
  p_asset_type             text,
  p_supply_type            text,
  p_area_id                uuid,
  p_current_status         text,
  p_longitude              double precision,
  p_latitude               double precision,
  p_capacity_m3            numeric,
  p_height_m               numeric,
  p_is_pass_through        boolean,
  p_pass_through_tolerance_pct numeric,
  p_operational_start_date date,
  p_external_reference     text,
  p_description_ar         text,
  p_description_en         text
)
returns uuid
language plpgsql
as $$
declare
  v_geom extensions.geometry(Point, 4326);
  v_id   uuid;
begin
  if p_longitude is not null and p_latitude is not null then
    if p_longitude < -180 or p_longitude > 180 or p_latitude < -90 or p_latitude > 90 then
      raise exception 'Coordinates out of range: %, %', p_longitude, p_latitude using errcode = '22023';
    end if;
    v_geom := extensions.ST_SetSRID(extensions.ST_MakePoint(p_longitude, p_latitude), 4326);
  elsif p_longitude is not null or p_latitude is not null then
    raise exception 'Give both longitude and latitude, or neither' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.water_assets (
      code, name_ar, name_en, asset_type, supply_type, area_id, current_status, geom,
      capacity_m3, height_m, is_pass_through, pass_through_tolerance_pct,
      operational_start_date, external_reference, description_ar, description_en)
    values (
      upper(btrim(p_code)), btrim(p_name_ar), nullif(btrim(coalesce(p_name_en, '')), ''),
      p_asset_type, p_supply_type, p_area_id, coalesce(p_current_status, 'UNKNOWN'), v_geom,
      p_capacity_m3, p_height_m, coalesce(p_is_pass_through, false), p_pass_through_tolerance_pct,
      p_operational_start_date, nullif(btrim(coalesce(p_external_reference, '')), ''),
      nullif(btrim(coalesce(p_description_ar, '')), ''), nullif(btrim(coalesce(p_description_en, '')), ''))
    returning id into v_id;
    return v_id;
  end if;

  update public.water_assets set
    code                       = upper(btrim(p_code)),
    name_ar                    = btrim(p_name_ar),
    name_en                    = nullif(btrim(coalesce(p_name_en, '')), ''),
    asset_type                 = p_asset_type,
    supply_type                = p_supply_type,
    area_id                    = p_area_id,
    current_status             = coalesce(p_current_status, current_status),
    geom                       = v_geom,
    capacity_m3                = p_capacity_m3,
    height_m                   = p_height_m,
    is_pass_through            = coalesce(p_is_pass_through, false),
    pass_through_tolerance_pct = p_pass_through_tolerance_pct,
    operational_start_date     = p_operational_start_date,
    external_reference         = nullif(btrim(coalesce(p_external_reference, '')), ''),
    description_ar             = nullif(btrim(coalesce(p_description_ar, '')), ''),
    description_en             = nullif(btrim(coalesce(p_description_en, '')), '')
  where id = p_id
  returning id into v_id;

  if v_id is null then
    raise exception 'Asset % not found or not writable', p_id using errcode = '42501';
  end if;
  return v_id;
end;
$$;

-- Retiring is the only way an asset leaves service. There is no delete.
create or replace function public.retire_water_asset(
  p_id uuid, p_end_date date, p_status text default 'STOPPED', p_note text default null
)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  if p_status not in ('STOPPED','DAMAGED','MAINTENANCE','UNKNOWN') then
    raise exception 'A retired asset cannot be marked %', p_status using errcode = '22023';
  end if;

  update public.water_assets
     set operational_end_date = coalesce(p_end_date, current_date),
         current_status = p_status,
         description_ar = case
           when p_note is null or btrim(p_note) = '' then description_ar
           else coalesce(description_ar || E'\n', '') || btrim(p_note) end
   where id = p_id
  returning id into v_id;

  if v_id is null then
    raise exception 'Asset % not found or not writable', p_id using errcode = '42501';
  end if;
  return v_id;
end;
$$;

create or replace function public.reinstate_water_asset(p_id uuid, p_status text default 'OPERATING')
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  update public.water_assets
     set operational_end_date = null, current_status = p_status
   where id = p_id
  returning id into v_id;
  if v_id is null then
    raise exception 'Asset % not found or not writable', p_id using errcode = '42501';
  end if;
  return v_id;
end;
$$;

create or replace function public.upsert_measurement_point(
  p_id                    uuid,
  p_code                  text,
  p_name_ar               text,
  p_name_en               text,
  p_point_type            text,
  p_asset_id              uuid,
  p_water_path_id         uuid,
  p_area_id               uuid,
  p_expects_daily_reading boolean,
  p_is_active             boolean
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
      expects_daily_reading, is_active)
    values (
      upper(btrim(p_code)), btrim(p_name_ar), nullif(btrim(coalesce(p_name_en, '')), ''),
      p_point_type, p_asset_id, p_water_path_id, p_area_id,
      coalesce(p_expects_daily_reading, true), coalesce(p_is_active, true))
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
    is_active             = coalesce(p_is_active, true)
  where id = p_id
  returning id into v_id;

  if v_id is null then
    raise exception 'Measurement point % not found or not writable', p_id using errcode = '42501';
  end if;
  return v_id;
end;
$$;

create or replace function public.upsert_water_path(
  p_id              uuid,
  p_from_asset_id   uuid,
  p_to_asset_id     uuid,
  p_connection_type text,
  p_sequence_order  int,
  p_name_ar         text,
  p_name_en         text,
  p_active_from     date,
  p_active_to       date,
  p_notes           text
)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  if p_from_asset_id = p_to_asset_id then
    raise exception 'A path cannot start and end at the same asset' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.water_paths (
      from_asset_id, to_asset_id, connection_type, sequence_order,
      name_ar, name_en, active_from, active_to, notes)
    values (
      p_from_asset_id, p_to_asset_id, coalesce(nullif(btrim(coalesce(p_connection_type, '')), ''), 'PIPELINE'),
      p_sequence_order, nullif(btrim(coalesce(p_name_ar, '')), ''),
      nullif(btrim(coalesce(p_name_en, '')), ''),
      coalesce(p_active_from, current_date), p_active_to,
      nullif(btrim(coalesce(p_notes, '')), ''))
    returning id into v_id;
    return v_id;
  end if;

  update public.water_paths set
    from_asset_id   = p_from_asset_id,
    to_asset_id     = p_to_asset_id,
    connection_type = coalesce(nullif(btrim(coalesce(p_connection_type, '')), ''), 'PIPELINE'),
    sequence_order  = p_sequence_order,
    name_ar         = nullif(btrim(coalesce(p_name_ar, '')), ''),
    name_en         = nullif(btrim(coalesce(p_name_en, '')), ''),
    active_from     = coalesce(p_active_from, active_from),
    active_to       = p_active_to,
    notes           = nullif(btrim(coalesce(p_notes, '')), '')
  where id = p_id
  returning id into v_id;

  if v_id is null then
    raise exception 'Water path % not found or not writable', p_id using errcode = '42501';
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Read helpers for the asset detail screen
-- ---------------------------------------------------------------------------
create or replace function public.get_asset_points(p_asset_id uuid)
returns table (
  id                    uuid,
  code                  text,
  name_ar               text,
  name_en               text,
  point_type            text,
  expects_daily_reading boolean,
  is_active             boolean,
  is_placeholder        boolean,
  reading_count         bigint,
  last_reading_date     date
)
language sql
stable
as $$
  select mp.id, mp.code, mp.name_ar, mp.name_en, mp.point_type,
         mp.expects_daily_reading, mp.is_active, mp.code like '%TMP%',
         (select count(*) from public.readings r
           where r.measurement_point_id = mp.id and not r.is_superseded),
         (select max(r.covers_to) from public.readings r
           where r.measurement_point_id = mp.id and not r.is_superseded)
  from public.measurement_points mp
  where mp.asset_id = p_asset_id
  order by mp.point_type, mp.code;
$$;

create or replace function public.get_asset_paths(p_asset_id uuid)
returns table (
  id              uuid,
  direction       text,
  other_asset_id  uuid,
  other_code      text,
  other_name_ar   text,
  connection_type text,
  sequence_order  int,
  name_ar         text,
  active_from     date,
  active_to       date,
  is_active       boolean
)
language sql
stable
as $$
  select p.id, 'OUT'::text, b.id, b.code, b.name_ar,
         p.connection_type, p.sequence_order, p.name_ar, p.active_from, p.active_to,
         p.active_to is null or p.active_to >= current_date
  from public.water_paths p
  join public.water_assets b on b.id = p.to_asset_id
  where p.from_asset_id = p_asset_id
  union all
  select p.id, 'IN'::text, a.id, a.code, a.name_ar,
         p.connection_type, p.sequence_order, p.name_ar, p.active_from, p.active_to,
         p.active_to is null or p.active_to >= current_date
  from public.water_paths p
  join public.water_assets a on a.id = p.from_asset_id
  where p.to_asset_id = p_asset_id
  order by 2, 6, 5;
$$;

grant execute on function
  public.upsert_water_asset(uuid, text, text, text, text, text, uuid, text, double precision,
                            double precision, numeric, numeric, boolean, numeric, date, text, text, text),
  public.retire_water_asset(uuid, date, text, text),
  public.reinstate_water_asset(uuid, text),
  public.upsert_measurement_point(uuid, text, text, text, text, uuid, uuid, uuid, boolean, boolean),
  public.upsert_water_path(uuid, uuid, uuid, text, int, text, text, date, date, text),
  public.get_asset_points(uuid),
  public.get_asset_paths(uuid)
to authenticated;
