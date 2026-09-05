-- =============================================================================
-- 0005  Readings and tank levels — immutable, superseded never edited or deleted
-- =============================================================================

create table if not exists public.readings (
  id                    uuid primary key default gen_random_uuid(),   -- client may supply its own UUID (offline-ready)
  measurement_point_id  uuid not null references public.measurement_points(id),
  covers_from           date not null,
  covers_to             date not null check (covers_to >= covers_from),
  days_covered          int  generated always as (covers_to - covers_from + 1) stored,
  volume_m3             numeric not null check (volume_m3 >= 0),
  cumulative_index      numeric check (cumulative_index is null or cumulative_index >= 0),
  entry_basis           text not null check (entry_basis in ('METER_DISPLAY','METER_DIFF','PUMP_HOURS','ESTIMATE')),
  operational_status    text check (operational_status is null or operational_status in
                          ('OPERATING','PARTIALLY_OPERATING','STOPPED','MAINTENANCE','DAMAGED','UNKNOWN')),
  pump_hours            numeric check (pump_hours is null or pump_hours >= 0),
  validation_status     text not null default 'OK'
                        check (validation_status in ('OK','FLAGGED','UNDER_REVIEW','REVIEWED')),
  validation_notes      text,
  supersedes_id         uuid references public.readings(id),
  is_superseded         boolean not null default false,
  entered_by            uuid references public.profiles(id) default auth.uid(),
  entered_at            timestamptz not null default now(),
  notes                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  check (supersedes_id is null or supersedes_id <> id)
);
create index if not exists readings_point_date_idx on public.readings (measurement_point_id, covers_from desc);
create index if not exists readings_covers_idx     on public.readings (covers_from, covers_to) where not is_superseded;
create index if not exists readings_flagged_idx    on public.readings (validation_status) where validation_status <> 'OK' and not is_superseded;
create index if not exists readings_supersedes_idx on public.readings (supersedes_id) where supersedes_id is not null;
create unique index if not exists readings_point_from_active_uq
  on public.readings (measurement_point_id, covers_from) where not is_superseded;
select app.ensure_updated_at_trigger('public.readings');

-- Stronger than the unique index: non-superseded readings on one point may not overlap in time.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'readings_no_overlap_active') then
    alter table public.readings
      add constraint readings_no_overlap_active
      exclude using gist (
        measurement_point_id with =,
        daterange(covers_from, covers_to, '[]') with &&
      ) where (not is_superseded);
  end if;
end;
$$;

create table if not exists public.tank_level_readings (
  id               uuid primary key default gen_random_uuid(),
  asset_id         uuid not null references public.water_assets(id),
  reading_date     date not null,
  reading_time     timestamptz not null default now(),
  level_m          numeric not null check (level_m >= 0),
  storage_m3       numeric,          -- computed server-side (trigger) from curve or linear fallback
  percentage_full  numeric,          -- computed server-side; inputs (level, capacity) remain stored
  supersedes_id    uuid references public.tank_level_readings(id),
  is_superseded    boolean not null default false,
  entered_by       uuid references public.profiles(id) default auth.uid(),
  entered_at       timestamptz not null default now(),
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (supersedes_id is null or supersedes_id <> id)
);
create index if not exists tank_level_readings_asset_date_idx on public.tank_level_readings (asset_id, reading_date desc);
create unique index if not exists tank_level_readings_asset_date_active_uq
  on public.tank_level_readings (asset_id, reading_date) where not is_superseded;
select app.ensure_updated_at_trigger('public.tank_level_readings');

-- ---------------------------------------------------------------------------
-- Immutability: historical rows are never edited. Only validation state and the
-- superseded flag may change (management action, audited). DELETE is impossible.
-- ---------------------------------------------------------------------------
create or replace function app.readings_guard_update()
returns trigger
language plpgsql
as $$
begin
  if new.id <> old.id
     or new.measurement_point_id <> old.measurement_point_id
     or new.covers_from <> old.covers_from
     or new.covers_to <> old.covers_to
     or new.volume_m3 <> old.volume_m3
     or new.cumulative_index is distinct from old.cumulative_index
     or new.entry_basis <> old.entry_basis
     or new.operational_status is distinct from old.operational_status
     or new.pump_hours is distinct from old.pump_hours
     or new.supersedes_id is distinct from old.supersedes_id
     or new.entered_by is distinct from old.entered_by
     or new.entered_at <> old.entered_at
     or new.notes is distinct from old.notes
  then
    raise exception 'Readings are immutable. Insert a correcting row with supersedes_id instead.'
      using errcode = 'P0001';
  end if;
  if old.is_superseded and not new.is_superseded then
    raise exception 'A superseded reading cannot be un-superseded.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_readings_guard_update on public.readings;
create trigger trg_readings_guard_update before update on public.readings
  for each row execute function app.readings_guard_update();

drop trigger if exists trg_no_delete on public.readings;
create trigger trg_no_delete before delete on public.readings
  for each row execute function app.prevent_delete();

create or replace function app.tank_levels_guard_update()
returns trigger
language plpgsql
as $$
begin
  if new.id <> old.id
     or new.asset_id <> old.asset_id
     or new.reading_date <> old.reading_date
     or new.reading_time <> old.reading_time
     or new.level_m <> old.level_m
     or new.storage_m3 is distinct from old.storage_m3
     or new.percentage_full is distinct from old.percentage_full
     or new.supersedes_id is distinct from old.supersedes_id
     or new.entered_by is distinct from old.entered_by
     or new.entered_at <> old.entered_at
     or new.notes is distinct from old.notes
  then
    raise exception 'Tank level readings are immutable. Insert a correcting row with supersedes_id instead.'
      using errcode = 'P0001';
  end if;
  if old.is_superseded and not new.is_superseded then
    raise exception 'A superseded level reading cannot be un-superseded.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_tank_levels_guard_update on public.tank_level_readings;
create trigger trg_tank_levels_guard_update before update on public.tank_level_readings
  for each row execute function app.tank_levels_guard_update();

drop trigger if exists trg_no_delete on public.tank_level_readings;
create trigger trg_no_delete before delete on public.tank_level_readings
  for each row execute function app.prevent_delete();

-- ---------------------------------------------------------------------------
-- Supersede: inserting a correction marks the old row superseded. SECURITY DEFINER so a
-- FIELD_TEAM user (INSERT-only) can correct their own entry without UPDATE rights.
-- ---------------------------------------------------------------------------
create or replace function app.readings_apply_supersede()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.readings%rowtype;
begin
  if new.supersedes_id is null then
    return new;
  end if;
  select * into v_old from public.readings where id = new.supersedes_id;
  if not found then
    raise exception 'supersedes_id % does not exist', new.supersedes_id using errcode = '23503';
  end if;
  if v_old.measurement_point_id <> new.measurement_point_id then
    raise exception 'A correction must be on the same measurement point as the reading it supersedes'
      using errcode = 'P0001';
  end if;
  if v_old.is_superseded then
    raise exception 'Reading % is already superseded', new.supersedes_id using errcode = 'P0001';
  end if;
  update public.readings set is_superseded = true where id = new.supersedes_id;
  return new;
end;
$$;

drop trigger if exists trg_readings_apply_supersede on public.readings;
create trigger trg_readings_apply_supersede before insert on public.readings
  for each row execute function app.readings_apply_supersede();

create or replace function app.tank_levels_apply_supersede()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.tank_level_readings%rowtype;
begin
  if new.supersedes_id is null then
    return new;
  end if;
  select * into v_old from public.tank_level_readings where id = new.supersedes_id;
  if not found then
    raise exception 'supersedes_id % does not exist', new.supersedes_id using errcode = '23503';
  end if;
  if v_old.asset_id <> new.asset_id then
    raise exception 'A correction must be on the same asset as the level it supersedes' using errcode = 'P0001';
  end if;
  if v_old.is_superseded then
    raise exception 'Level reading % is already superseded', new.supersedes_id using errcode = 'P0001';
  end if;
  update public.tank_level_readings set is_superseded = true where id = new.supersedes_id;
  return new;
end;
$$;

drop trigger if exists trg_tank_levels_apply_supersede on public.tank_level_readings;
create trigger trg_tank_levels_apply_supersede before insert on public.tank_level_readings
  for each row execute function app.tank_levels_apply_supersede();
