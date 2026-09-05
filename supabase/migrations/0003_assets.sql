-- =============================================================================
-- 0003  Assets: water_assets, level_volume_curve, water_paths
-- Assets are NEVER deleted. Decommission = current_status + operational_end_date.
-- =============================================================================

create table if not exists public.water_assets (
  id                      uuid primary key default gen_random_uuid(),
  code                    text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  name_ar                 text not null,
  name_en                 text,
  asset_type              text not null check (asset_type in
                            ('WELL','ISRAELI_CONNECTION','TANK','RESERVOIR','PUMPING_STATION','MAIN_METER')),
  supply_type             text check (supply_type in ('GROUNDWATER','ISRAELI')),
  area_id                 uuid references public.areas(id),
  current_status          text not null default 'UNKNOWN' check (current_status in
                            ('OPERATING','PARTIALLY_OPERATING','STOPPED','MAINTENANCE','DAMAGED','UNKNOWN')),
  geom                    extensions.geometry(Point, 4326),
  capacity_m3             numeric check (capacity_m3 is null or capacity_m3 > 0),
  height_m                numeric check (height_m is null or height_m > 0),
  -- Pass-through (transit) buffer: inlet and outlet volumes are expected to agree.
  -- Saeer intermediate tank is the first instance. Threshold is data (see system_settings),
  -- optionally overridden per asset here.
  is_pass_through             boolean not null default false,
  pass_through_tolerance_pct  numeric check (pass_through_tolerance_pct is null or pass_through_tolerance_pct >= 0),
  operational_start_date  date,
  operational_end_date    date check (operational_end_date is null or operational_start_date is null
                                       or operational_end_date >= operational_start_date),
  external_reference      text,     -- reserved for future bill matching (Israeli connections)
  description_ar          text,
  description_en          text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint water_assets_supply_type_chk check (
    (asset_type = 'ISRAELI_CONNECTION' and supply_type = 'ISRAELI')
    or (asset_type = 'WELL' and supply_type = 'GROUNDWATER')
    or (asset_type not in ('WELL','ISRAELI_CONNECTION'))
  )
);
create index if not exists water_assets_geom_gix   on public.water_assets using gist (geom);
create index if not exists water_assets_type_idx   on public.water_assets (asset_type);
create index if not exists water_assets_area_idx   on public.water_assets (area_id);
create index if not exists water_assets_status_idx on public.water_assets (current_status);
select app.ensure_updated_at_trigger('public.water_assets');

-- Non-linear tank geometry. If no rows exist for an asset, storage falls back to linear
-- (capacity_m3 / height_m). NEVER hardcode "1 m = N m³" in application code.
create table if not exists public.level_volume_curve (
  id          uuid primary key default gen_random_uuid(),
  asset_id    uuid not null references public.water_assets(id),
  level_m     numeric not null check (level_m >= 0),
  volume_m3   numeric not null check (volume_m3 >= 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (asset_id, level_m)
);
select app.ensure_updated_at_trigger('public.level_volume_curve');

-- Topology is DATA. Adding a well, connection, reservoir or meter never requires a code change.
create table if not exists public.water_paths (
  id               uuid primary key default gen_random_uuid(),
  from_asset_id    uuid not null references public.water_assets(id),
  to_asset_id      uuid not null references public.water_assets(id),
  connection_type  text not null default 'PIPELINE',
  sequence_order   int,
  active_from      date not null default current_date,
  active_to        date check (active_to is null or active_to >= active_from),
  name_ar          text,
  name_en          text,
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (from_asset_id <> to_asset_id)
);
create index if not exists water_paths_from_idx on public.water_paths (from_asset_id);
create index if not exists water_paths_to_idx   on public.water_paths (to_asset_id);
select app.ensure_updated_at_trigger('public.water_paths');

-- Hard rule 1: assets are never deleted (RLS has no DELETE policy; this is defence in depth).
create or replace function app.prevent_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Rows in % are never deleted. Supersede the row or change its status.', tg_table_name
    using errcode = 'P0001';
end;
$$;

drop trigger if exists trg_no_delete on public.water_assets;
create trigger trg_no_delete before delete on public.water_assets
  for each row execute function app.prevent_delete();
