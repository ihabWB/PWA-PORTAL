-- =============================================================================
-- 0007  Operations: assignments, alerts, system_settings, audit_logs, import staging
-- =============================================================================

-- Daily task lists are DERIVED from assignments + expects_daily_reading + missing readings.
-- There is deliberately no tasks table.
create table if not exists public.assignments (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.profiles(id),
  measurement_point_id  uuid not null references public.measurement_points(id),
  active_from           date not null default current_date,
  active_to             date check (active_to is null or active_to >= active_from),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists assignments_user_idx  on public.assignments (user_id);
create index if not exists assignments_point_idx on public.assignments (measurement_point_id);
select app.ensure_updated_at_trigger('public.assignments');

-- Thresholds and operational parameters live here as DATA, never in code.
create table if not exists public.system_settings (
  key             text primary key check (key ~ '^[a-z][a-z0-9_]{1,63}$'),
  value           jsonb not null,
  description_ar  text,
  description_en  text,
  updated_by      uuid references public.profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
select app.ensure_updated_at_trigger('public.system_settings');

insert into public.system_settings (key, value, description_ar, description_en) values
  ('timezone', '"Asia/Hebron"',
   'المنطقة الزمنية لحساب حدود اليوم التشغيلي', 'Timezone used for operational-day boundaries'),
  ('pass_through_mismatch_pct', '3',
   'الحد الافتراضي (٪) للفرق اليومي بين الداخل والخارج في الخزانات العابرة قبل إطلاق تنبيه',
   'Default daily inlet/outlet mismatch (%) for pass-through tanks before an alert is raised'),
  ('abnormal_reading_sigma', '3',
   'عدد الانحرافات المعيارية عن المتوسط المتحرك التي تُعلِّم القراءة كغير طبيعية',
   'Standard deviations from the trailing mean that flag a reading as abnormal'),
  ('abnormal_reading_window', '30',
   'عدد القراءات السابقة المستخدمة في حساب المتوسط المتحرك', 'Trailing readings used for the mean/σ'),
  ('abnormal_reading_min_samples', '7',
   'أقل عدد قراءات سابقة قبل تفعيل كشف القراءات غير الطبيعية', 'Minimum prior readings before flagging is active')
on conflict (key) do nothing;

create or replace function app.setting_numeric(p_key text, p_default numeric)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (value #>> '{}')::numeric from public.system_settings where key = p_key), p_default);
$$;

create or replace function app.setting_text(p_key text, p_default text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select value #>> '{}' from public.system_settings where key = p_key), p_default);
$$;

-- Today's calendar date in the operational timezone (DST-safe).
create or replace function app.local_today()
returns date
language sql
stable
as $$
  select (now() at time zone app.setting_text('timezone', 'Asia/Hebron'))::date;
$$;

create table if not exists public.alerts (
  id                    uuid primary key default gen_random_uuid(),
  alert_type            text not null check (alert_type in
                          ('MISSING_READING','ABNORMAL_READING','SOURCE_STOPPED','SOURCE_MAINTENANCE',
                           'LOW_RESERVOIR_LEVEL','HIGH_RESERVOIR_LEVEL','WATER_BALANCE_DISCREPANCY',
                           'DATA_VALIDATION_ERROR','PASS_THROUGH_MISMATCH')),
  severity              text not null check (severity in ('INFO','WARNING','CRITICAL')),
  status                text not null default 'OPEN' check (status in ('OPEN','ACKNOWLEDGED','RESOLVED')),
  asset_id              uuid references public.water_assets(id),
  measurement_point_id  uuid references public.measurement_points(id),
  reading_id            uuid references public.readings(id),
  reference_date        date,
  description_ar        text not null,
  description_en        text,
  details               jsonb,        -- the inputs behind the alert (values, thresholds) — never a bare derived number
  created_at            timestamptz not null default now(),
  acknowledged_by       uuid references public.profiles(id),
  acknowledged_at       timestamptz,
  resolved_by           uuid references public.profiles(id),
  resolved_at           timestamptz,
  resolution_notes      text,
  updated_at            timestamptz not null default now()
);
create index if not exists alerts_open_idx        on public.alerts (status, severity, created_at desc) where status <> 'RESOLVED';
create index if not exists alerts_asset_idx       on public.alerts (asset_id);
create index if not exists alerts_point_idx       on public.alerts (measurement_point_id);
create index if not exists alerts_ref_date_idx    on public.alerts (reference_date);
create unique index if not exists alerts_open_dedupe_uq
  on public.alerts (alert_type, coalesce(asset_id, '00000000-0000-0000-0000-000000000000'::uuid),
                    coalesce(measurement_point_id, '00000000-0000-0000-0000-000000000000'::uuid),
                    coalesce(reference_date, '0001-01-01'::date))
  where status <> 'RESOLVED';
select app.ensure_updated_at_trigger('public.alerts');

-- Written by database triggers only, so nothing can bypass it.
create table if not exists public.audit_logs (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid,                     -- auth.uid() at the time; may be null for system jobs
  action        text not null check (action in ('INSERT','UPDATE','DELETE')),
  entity_table  text not null,
  entity_id     uuid,
  old_value     jsonb,
  new_value     jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists audit_logs_entity_idx on public.audit_logs (entity_table, entity_id, created_at desc);
create index if not exists audit_logs_user_idx   on public.audit_logs (user_id, created_at desc);

drop trigger if exists trg_no_delete on public.audit_logs;
create trigger trg_no_delete before delete on public.audit_logs
  for each row execute function app.prevent_delete();

-- Excel import staging (Stage 9 uses it; schema fixed now so nothing blocks it).
create table if not exists public.import_batches (
  id            uuid primary key default gen_random_uuid(),
  entity_type   text not null check (entity_type in ('WATER_ASSETS','MEASUREMENT_POINTS','READINGS','TANK_LEVELS')),
  file_name     text not null,
  status        text not null default 'UPLOADED'
                check (status in ('UPLOADED','PARSED','VALIDATED','COMMITTED','REJECTED')),
  row_count     int not null default 0,
  valid_count   int not null default 0,
  error_count   int not null default 0,
  uploaded_by   uuid references public.profiles(id) default auth.uid(),
  committed_at  timestamptz,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
select app.ensure_updated_at_trigger('public.import_batches');

create table if not exists public.import_rows (
  id          uuid primary key default gen_random_uuid(),
  batch_id    uuid not null references public.import_batches(id),
  row_number  int not null,
  raw_row     jsonb not null,
  status      text not null default 'PENDING' check (status in ('PENDING','VALID','INVALID','COMMITTED')),
  created_at  timestamptz not null default now(),
  unique (batch_id, row_number)
);

create table if not exists public.import_errors (
  id           uuid primary key default gen_random_uuid(),
  batch_id     uuid not null references public.import_batches(id),
  row_number   int,
  column_name  text,
  error_code   text not null,
  message_ar   text not null,
  message_en   text,
  created_at   timestamptz not null default now()
);
create index if not exists import_errors_batch_idx on public.import_errors (batch_id);
