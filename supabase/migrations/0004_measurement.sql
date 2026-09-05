-- =============================================================================
-- 0004  Measurement: measurement_points (permanent), meter_devices, meter_installations
-- Readings attach to measurement points, NEVER to meters.
-- =============================================================================

create table if not exists public.measurement_points (
  id                      uuid primary key default gen_random_uuid(),
  code                    text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  name_ar                 text not null,
  name_en                 text,
  point_type              text not null check (point_type in
                            ('SOURCE_METER','TRANSFER_METER','TANK_INLET_METER','TANK_OUTLET_METER')),
                          -- future: SERVICE_PROVIDER_METER, CONSUMER_METER
  asset_id                uuid references public.water_assets(id),
  water_path_id           uuid references public.water_paths(id),
  unit                    text not null default 'm3',
  is_active               boolean not null default true,
  expects_daily_reading   boolean not null default true,   -- drives missing-reading detection
  area_id                 uuid references public.areas(id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check (asset_id is not null or water_path_id is not null)
);
-- An asset MAY have many points; a path MAY have many. Never assume 1:1.
create index if not exists measurement_points_asset_idx on public.measurement_points (asset_id);
create index if not exists measurement_points_path_idx  on public.measurement_points (water_path_id);
create index if not exists measurement_points_area_idx  on public.measurement_points (area_id);
create index if not exists measurement_points_daily_idx on public.measurement_points (expects_daily_reading)
  where is_active;
select app.ensure_updated_at_trigger('public.measurement_points');

-- Physical hardware. Replaceable.
create table if not exists public.meter_devices (
  id             uuid primary key default gen_random_uuid(),
  serial_number  text not null unique,
  manufacturer   text,
  model          text,
  digit_count    int check (digit_count is null or digit_count between 1 and 12),
  multiplier     numeric not null default 1 check (multiplier > 0),
  status         text not null default 'IN_SERVICE'
                 check (status in ('IN_STOCK','IN_SERVICE','REMOVED','FAULTY','SCRAPPED')),
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
select app.ensure_updated_at_trigger('public.meter_devices');

-- Which device sat on which point, from when to when.
create table if not exists public.meter_installations (
  id                    uuid primary key default gen_random_uuid(),
  measurement_point_id  uuid not null references public.measurement_points(id),
  meter_device_id       uuid not null references public.meter_devices(id),
  installed_at          date not null,
  removed_at            date check (removed_at is null or removed_at >= installed_at),
  index_at_install      numeric check (index_at_install is null or index_at_install >= 0),
  index_at_removal      numeric check (index_at_removal is null or index_at_removal >= 0),
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists meter_installations_point_idx  on public.meter_installations (measurement_point_id);
create index if not exists meter_installations_device_idx on public.meter_installations (meter_device_id);
select app.ensure_updated_at_trigger('public.meter_installations');

-- No two overlapping installations on one point; a device is in one place at a time.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'meter_installations_no_overlap_point') then
    alter table public.meter_installations
      add constraint meter_installations_no_overlap_point
      exclude using gist (
        measurement_point_id with =,
        daterange(installed_at, coalesce(removed_at, 'infinity'::date), '[]') with &&
      );
  end if;
  if not exists (select 1 from pg_constraint where conname = 'meter_installations_no_overlap_device') then
    alter table public.meter_installations
      add constraint meter_installations_no_overlap_device
      exclude using gist (
        meter_device_id with =,
        daterange(installed_at, coalesce(removed_at, 'infinity'::date), '[]') with &&
      );
  end if;
end;
$$;
