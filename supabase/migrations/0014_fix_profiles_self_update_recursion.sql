-- =============================================================================
-- 0014  Fix: infinite recursion in the profiles self-update policy (42P17)
--
-- `profiles_update_self` (shipped in 0010) validated the new row with subqueries on
-- public.profiles itself:
--
--     with check (id = auth.uid()
--                 and role      = (select p.role      from public.profiles p where p.id = auth.uid())
--                 and is_active = (select p.is_active from public.profiles p where p.id = auth.uid()))
--
-- Evaluating those subqueries requires applying the SELECT policy on profiles while the
-- policies for profiles are already being expanded, so PostgreSQL aborts with
-- "42P17 infinite recursion detected in policy for relation profiles".
--
-- Consequence: a user could not update their OWN profile at all — changing a phone number
-- or display name failed with the same 42P17. The functional test hid this because it only
-- asserted "an exception was raised" for the privilege-escalation attempt.
--
-- Reproduced and fixed against PostgreSQL 18 before shipping:
--   before — self-update of phone/name: 42P17;  escalation attempt: 42P17
--   after  — self-update of phone/name: succeeds; escalation attempt: 42501
--
-- Fix: read the stored role/is_active through SECURITY DEFINER helpers, which are opaque to
-- the policy expander, instead of querying the table inside its own policy.
-- Re-runnable.
-- =============================================================================

-- Stored role of the current user, regardless of is_active.
-- Distinct from app.user_role(), which returns NULL for a deactivated account.
create or replace function app.self_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.role from public.profiles p where p.id = auth.uid();
$$;

create or replace function app.self_is_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p.is_active from public.profiles p where p.id = auth.uid();
$$;

revoke all on function app.self_role(), app.self_is_active() from public, anon;
grant execute on function app.self_role(), app.self_is_active() to authenticated, service_role;

-- A user may edit their own name/phone, but never their own role or activation state.
-- If the profile row is missing, both helpers return NULL, the comparison is NULL,
-- and the update is refused — deny by default.
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role      = app.self_role()
    and is_active = app.self_is_active()
  );

-- Guard against reintroducing the pattern: no policy on profiles may query profiles.
do $$
declare
  v_bad text;
begin
  select string_agg(pol.polname, ', ')
    into v_bad
  from pg_policy pol
  where pol.polrelid = 'public.profiles'::regclass
    and (coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') like '%public.profiles%'
      or coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') like '%public.profiles%');

  if v_bad is not null then
    raise exception 'Policy(ies) % on public.profiles query public.profiles and will recurse (42P17)', v_bad;
  end if;
end;
$$;
