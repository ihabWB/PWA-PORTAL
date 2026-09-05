-- =============================================================================
-- 0001  Extensions + common helpers
-- Re-runnable. Run in the Supabase SQL Editor in file order.
-- =============================================================================

create extension if not exists postgis    with schema extensions;
create extension if not exists btree_gist with schema extensions;   -- uuid = in EXCLUDE constraints

-- Internal helper schema. Not exposed through the REST API; used by policies, triggers, functions.
create schema if not exists app;
grant usage on schema app to authenticated, service_role;

-- Generic updated_at maintenance
create or replace function app.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Attach the updated_at trigger to a table idempotently
create or replace function app.ensure_updated_at_trigger(p_table regclass)
returns void
language plpgsql
as $$
declare
  v_name text := 'trg_set_updated_at';
begin
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = p_table and t.tgname = v_name and not t.tgisinternal
  ) then
    execute format('create trigger %I before update on %s for each row execute function app.set_updated_at()', v_name, p_table);
  end if;
end;
$$;

-- Deny-by-default hygiene: the anon role must not see any application table.
-- (RLS policies below are all `to authenticated`; this removes the grant layer too.)
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;
alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke all on functions from anon;
