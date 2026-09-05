-- =============================================================================
-- 0006  Topology & balance: balance_zones, balance_zone_members
-- =============================================================================

create table if not exists public.balance_zones (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  name_ar      text not null,
  name_en      text,
  description  text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
select app.ensure_updated_at_trigger('public.balance_zones');

-- Roles:
--   INFLOW   water entering the zone (sources)                   → measurement point
--   OUTFLOW  measured take-offs leaving the zone along the route   → measurement point
--   ARRIVAL  water reaching the zone's destination node            → measurement point
--            (Saeer inlet meter). Kept separate from OUTFLOW so the screen can show
--            "arrival" and "measured take-offs" as distinct lines.  [extension of SPEC §4]
--   STORAGE  a tank/reservoir whose level change enters the balance → asset
--            (not needed for a transit node like Saeer; used by Halahoul in Stage 8)
-- measurement_quality is essential: without it every report shows a huge unexplained gap.
create table if not exists public.balance_zone_members (
  id                    uuid primary key default gen_random_uuid(),
  zone_id               uuid not null references public.balance_zones(id),
  measurement_point_id  uuid references public.measurement_points(id),
  asset_id              uuid references public.water_assets(id),
  role                  text not null check (role in ('INFLOW','OUTFLOW','ARRIVAL','STORAGE')),
  measurement_quality   text not null default 'MEASURED'
                        check (measurement_quality in ('MEASURED','ESTIMATED','UNMEASURED')),
  sign                  int not null default 1 check (sign in (-1, 1)),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  check (
    (role = 'STORAGE' and asset_id is not null and measurement_point_id is null)
    or (role <> 'STORAGE' and measurement_point_id is not null and asset_id is null)
  )
);
create index if not exists balance_zone_members_zone_idx  on public.balance_zone_members (zone_id);
create index if not exists balance_zone_members_point_idx on public.balance_zone_members (measurement_point_id);
create unique index if not exists balance_zone_members_zone_point_uq
  on public.balance_zone_members (zone_id, measurement_point_id) where measurement_point_id is not null;
create unique index if not exists balance_zone_members_zone_asset_uq
  on public.balance_zone_members (zone_id, asset_id) where asset_id is not null;
select app.ensure_updated_at_trigger('public.balance_zone_members');
