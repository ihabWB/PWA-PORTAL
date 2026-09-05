-- =============================================================================
-- 0002  Reference / organisation: areas, profiles, user_areas
-- =============================================================================

create table if not exists public.areas (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'),
  name_ar     text not null,
  name_en     text,
  geom        extensions.geometry(MultiPolygon, 4326),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists areas_geom_gix on public.areas using gist (geom);
select app.ensure_updated_at_trigger('public.areas');

-- Extends auth.users. Role drives RLS everywhere; is_active=false disables a user without deleting.
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id),
  full_name_ar  text not null default '',
  full_name_en  text,
  phone         text,
  role          text not null default 'FIELD_TEAM'
                check (role in ('SUPER_ADMIN','WATER_MANAGEMENT','AREA_MANAGER','FIELD_TEAM')),
  is_active     boolean not null default false,   -- an admin activates new accounts explicitly
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists profiles_role_idx on public.profiles (role) where is_active;
select app.ensure_updated_at_trigger('public.profiles');

-- Area managers / field workers may cover several areas
create table if not exists public.user_areas (
  user_id     uuid not null references public.profiles(id),
  area_id     uuid not null references public.areas(id),
  created_at  timestamptz not null default now(),
  primary key (user_id, area_id)
);
create index if not exists user_areas_area_idx on public.user_areas (area_id);

-- Auto-create a profile for every new auth user (inactive, lowest role, until an admin promotes).
create or replace function app.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name_ar, full_name_en, phone, role, is_active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name_ar', new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'full_name_en',
    new.phone,
    'FIELD_TEAM',
    false
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_auth_user();

-- Backfill profiles for users that already exist (e.g. the test user created in the dashboard)
insert into public.profiles (id, full_name_ar, role, is_active)
select u.id, coalesce(u.raw_user_meta_data ->> 'full_name', ''), 'FIELD_TEAM', false
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);
