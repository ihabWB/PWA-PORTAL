-- =============================================================================
-- 0017  Widen asset_type and point_type once, for every type the spec anticipates
--
-- 0015 widened these constraints one value at a time. Every future type in the spec is
-- added here in a single pass so adding a DMA, a valve, a pressure point or a consumer
-- meter is a data entry, not a migration. Adding the VALUE does not build the Phase 2/3
-- feature; it only stops the schema from blocking it.
--
-- Re-runnable.
-- =============================================================================

alter table public.water_assets drop constraint if exists water_assets_asset_type_check;
alter table public.water_assets
  add constraint water_assets_asset_type_check check (asset_type in (
    -- Phase 1
    'WELL','ISRAELI_CONNECTION','TANK','RESERVOIR','PUMPING_STATION','MAIN_METER','SERVICE_PROVIDER',
    -- anticipated later; no feature is built for these yet
    'DMA','VALVE','PRESSURE_POINT','BOOSTER_STATION','TREATMENT_PLANT','SPRING','TANKER_FILLING_POINT'
  ));

alter table public.measurement_points drop constraint if exists measurement_points_point_type_check;
alter table public.measurement_points
  add constraint measurement_points_point_type_check check (point_type in (
    -- Phase 1
    'SOURCE_METER','TRANSFER_METER','TANK_INLET_METER','TANK_OUTLET_METER','SERVICE_PROVIDER_METER',
    -- anticipated later
    'CONSUMER_METER','DMA_INLET_METER','DMA_OUTLET_METER','PRESSURE_SENSOR','FLOW_SENSOR'
  ));

-- Asset types that are not water sources must not carry a supply_type, and the two source
-- types must. Restated here because 0003 wrote it against the narrower type list.
alter table public.water_assets drop constraint if exists water_assets_supply_type_chk;
alter table public.water_assets
  add constraint water_assets_supply_type_chk check (
    (asset_type = 'ISRAELI_CONNECTION' and supply_type = 'ISRAELI')
    or (asset_type in ('WELL','SPRING') and supply_type = 'GROUNDWATER')
    or (asset_type not in ('WELL','SPRING','ISRAELI_CONNECTION') and supply_type is null)
  );

-- Water paths: connection_type is free text today. Keep it free (topology is data), but
-- reject blanks so the editor cannot store an empty relationship label.
alter table public.water_paths drop constraint if exists water_paths_connection_type_check;
alter table public.water_paths
  add constraint water_paths_connection_type_check check (length(btrim(connection_type)) > 0);

-- ---------------------------------------------------------------------------
-- Placeholder inventory: everything the Saeer seed created with a temporary code.
-- Stage 5 uses this to make replacing seed rows deliberate instead of accidental.
-- ---------------------------------------------------------------------------
create or replace function public.get_placeholder_rows()
returns table (
  entity          text,
  id              uuid,
  code            text,
  name_ar         text,
  name_en         text,
  kind            text,
  has_geometry    boolean,
  reading_count   bigint,
  parent_asset_id uuid,
  detail          text
)
language sql
stable
as $$
  select 'ASSET'::text, a.id, a.code, a.name_ar, a.name_en, a.asset_type,
         a.geom is not null,
         (select count(*) from public.readings r
           join public.measurement_points mp on mp.id = r.measurement_point_id
          where mp.asset_id = a.id and not r.is_superseded),
         a.id,
         a.description_ar
  from public.water_assets a
  where a.code like '%TMP%'
  union all
  select 'MEASUREMENT_POINT'::text, mp.id, mp.code, mp.name_ar, mp.name_en, mp.point_type,
         null::boolean,
         (select count(*) from public.readings r
           where r.measurement_point_id = mp.id and not r.is_superseded),
         mp.asset_id,
         (select a.code from public.water_assets a where a.id = mp.asset_id)
  from public.measurement_points mp
  where mp.code like '%TMP%'
  order by 1, 3;
$$;

grant execute on function public.get_placeholder_rows() to authenticated;
revoke execute on function public.get_placeholder_rows() from anon, public;

-- ---------------------------------------------------------------------------
-- Asset catalogue for the management screens: assets with their point counts and
-- whether they still carry a placeholder code. SECURITY INVOKER — RLS applies.
-- ---------------------------------------------------------------------------
create or replace function public.get_asset_catalogue(p_include_retired boolean default true)
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
