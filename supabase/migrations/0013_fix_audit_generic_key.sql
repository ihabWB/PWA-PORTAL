-- =============================================================================
-- 0013  Fix: app.audit_row() assumed every audited table has an `id` column.
--
-- user_areas (composite PK user_id+area_id) and system_settings (PK `key`) have none, so
-- every INSERT into user_areas — and every UPDATE of a threshold — raised
-- "record new has no field id". This made 0012 fail and roll back.
--
-- Fix: resolve the entity id from the row's JSON when an `id` column exists, and always
-- store the table's full primary key as JSON in the new `entity_key` column. entity_id
-- stays nullable. Re-runnable. After this file, re-run 0012 (it is re-runnable).
-- =============================================================================

alter table public.audit_logs add column if not exists entity_key jsonb;
comment on column public.audit_logs.entity_id  is 'UUID `id` of the row when the table has one; NULL otherwise (see entity_key).';
comment on column public.audit_logs.entity_key is 'Primary-key columns of the audited row as JSON, e.g. {"user_id":..,"area_id":..} or {"key":"timezone"}.';

create or replace function app.audit_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row       jsonb;
  v_entity_id uuid;
  v_key       jsonb;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;

  -- entity_id only when the table has a uuid-shaped `id`
  if v_row ? 'id' then
    begin
      v_entity_id := (v_row ->> 'id')::uuid;
    exception when others then
      v_entity_id := null;
    end;
  end if;

  -- full primary key, whatever its shape
  select jsonb_object_agg(a.attname, v_row -> a.attname)
    into v_key
  from pg_index i
  join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey)
  where i.indrelid = tg_relid and i.indisprimary;

  insert into public.audit_logs (user_id, action, entity_table, entity_id, entity_key, old_value, new_value)
  values (
    auth.uid(),
    tg_op,
    tg_table_name,
    v_entity_id,
    v_key,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- Guard against regressions: fail loudly if an audited table would still break.
do $$
declare
  r record;
begin
  for r in
    select c.relname
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    where t.tgname = 'trg_audit' and not t.tgisinternal
  loop
    if not exists (
      select 1 from pg_index i where i.indrelid = ('public.' || quote_ident(r.relname))::regclass and i.indisprimary
    ) then
      raise exception 'Audited table % has no primary key; audit_row() needs one for entity_key', r.relname;
    end if;
  end loop;
end;
$$;
