-- =============================================================================
-- 0008  Access helpers used by RLS policies
-- SECURITY DEFINER so policies never recurse into RLS-protected tables.
-- Every helper returns false/empty for anonymous, inactive or unknown users.
-- =============================================================================

create or replace function app.user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid() and p.is_active
  limit 1;
$$;

create or replace function app.is_super_admin()
returns boolean
language sql
stable
as $$
  select coalesce(app.user_role() = 'SUPER_ADMIN', false);
$$;

-- SUPER_ADMIN or WATER_MANAGEMENT: read everything, manage operational data.
create or replace function app.is_management()
returns boolean
language sql
stable
as $$
  select coalesce(app.user_role() in ('SUPER_ADMIN','WATER_MANAGEMENT'), false);
$$;

create or replace function app.is_area_manager()
returns boolean
language sql
stable
as $$
  select coalesce(app.user_role() = 'AREA_MANAGER', false);
$$;

create or replace function app.is_field_team()
returns boolean
language sql
stable
as $$
  select coalesce(app.user_role() = 'FIELD_TEAM', false);
$$;

-- Areas the current user covers (area managers and field workers)
create or replace function app.user_area_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select ua.area_id from public.user_areas ua where ua.user_id = auth.uid();
$$;

-- Measurement points currently assigned to the user (field team scope)
create or replace function app.assigned_point_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select a.measurement_point_id
  from public.assignments a
  where a.user_id = auth.uid()
    and a.active_from <= app.local_today()
    and (a.active_to is null or a.active_to >= app.local_today());
$$;

create or replace function app.can_access_area(p_area_id uuid)
returns boolean
language sql
stable
as $$
  select app.is_management()
      or (p_area_id is not null and p_area_id in (select app.user_area_ids()));
$$;

-- Point scope: management → all; area manager → points in their areas; field team → assigned points.
create or replace function app.can_access_point(p_point_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select app.is_management()
      or (app.is_area_manager() and exists (
            select 1 from public.measurement_points mp
            where mp.id = p_point_id and mp.area_id in (select app.user_area_ids())))
      or (app.is_field_team() and p_point_id in (select app.assigned_point_ids()));
$$;

-- Asset scope: management → all; area manager → assets in their areas;
-- field team → assets that carry one of their assigned points.
create or replace function app.can_access_asset(p_asset_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select app.is_management()
      or (app.is_area_manager() and exists (
            select 1 from public.water_assets a
            where a.id = p_asset_id and a.area_id in (select app.user_area_ids())))
      or (app.is_field_team() and exists (
            select 1 from public.measurement_points mp
            where mp.asset_id = p_asset_id and mp.id in (select app.assigned_point_ids())));
$$;

-- Lock helpers down: callable by signed-in users only.
revoke all on all functions in schema app from public, anon;
grant execute on all functions in schema app to authenticated, service_role;
alter default privileges in schema app revoke all on functions from public, anon;
alter default privileges in schema app grant execute on functions to authenticated, service_role;
