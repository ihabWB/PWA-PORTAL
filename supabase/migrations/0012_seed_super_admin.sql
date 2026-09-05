-- =============================================================================
-- 0012  Seed — promote the test user to SUPER_ADMIN
-- Requires the auth user to exist already (created in the Supabase dashboard).
-- =============================================================================

do $$
declare
  v_user_id uuid;
begin
  select id into v_user_id from auth.users where lower(email) = lower('ehabomear@gmail.com') limit 1;

  if v_user_id is null then
    raise exception 'Auth user ehabomear@gmail.com not found. Create it in Authentication → Users, then re-run 0012.';
  end if;

  insert into public.profiles (id, full_name_ar, full_name_en, role, is_active)
  values (v_user_id, 'مدير النظام', 'System administrator', 'SUPER_ADMIN', true)
  on conflict (id) do update
    set role      = 'SUPER_ADMIN',
        is_active = true,
        full_name_ar = case when public.profiles.full_name_ar = '' then excluded.full_name_ar else public.profiles.full_name_ar end,
        full_name_en = coalesce(public.profiles.full_name_en, excluded.full_name_en);

  -- Management sees every area through RLS, but link the admin to HEB so area-scoped
  -- screens (e.g. "my areas") have something to show.
  insert into public.user_areas (user_id, area_id)
  select v_user_id, a.id from public.areas a where a.code = 'HEB'
  on conflict do nothing;

  raise notice 'SUPER_ADMIN profile ready for user %', v_user_id;
end;
$$;
