# Water Sources & Supply Monitoring System — Build Prompt

You are building a **professional operational water-management platform** for a Palestinian
water utility. Not a CRUD app. The system answers operational questions about where water
comes from, how much moves, how much arrives, and where it is lost.

Read this entire document before writing any code. A separate, longer technical
specification exists; **this document overrides it wherever they conflict**, because this
reflects decisions made after the original spec was written.

---

## 0. The one question the system must answer first

> **How much water actually reaches the intermediate reservoir at Saeer Pumping Station,
> compared with how much was pumped from all sources upstream?**

Everything in Phase 1 exists to answer this. Halahoul Central Reservoir, the full asset
catalogue, and the wider distribution picture come **after** this single question is
answered end to end.

Do not start by building screens. Start by building the vertical slice that produces this
one number correctly.

---

## 1. Technology stack

| Layer         | Choice                            | Notes                                  |
| ------------- | --------------------------------- | -------------------------------------- |
| Framework     | Next.js (App Router) + TypeScript | React Server Components where sensible |
| Styling       | Tailwind CSS v4                   | CSS-first theming                      |
| UI components | HeroUI v3 (`@heroui/react`)       | **Pin the exact version, no `^`**      |
| Forms         | React Hook Form + Zod             | Zod schemas shared client/server       |
| Charts        | Recharts                          |                                        |
| Map           | MapLibre GL JS                    |                                        |
| Backend       | Supabase (PostgreSQL + PostGIS)   | Postgres is the source of truth        |
| Auth          | Supabase Auth                     |                                        |
| Authorization | PostgreSQL Row Level Security     | Not frontend checks                    |

### HeroUI usage rules

1. Use HeroUI for every standard component that exists: buttons, inputs, selects, tables,
   modals, tabs, chips, alerts, tooltips, pagination, form controls, loading states.
2. Do **not** ship HeroUI's default look. Define an application design token layer
   (colors, radius, typography, spacing) in the Tailwind v4 CSS-first theme and let all
   components inherit it.
3. Do **not** build custom versions of components HeroUI already provides.
4. Charts, the map, and dense operational tables are ours — HeroUI is not expected to cover
   them.
5. Pin the HeroUI version exactly. It ships monthly minor releases; upgrades must be a
   deliberate, tested action.

---

## 2. Arabic is the primary language

This is an architectural requirement, not styling.

- Application direction is **RTL by default**. English is a secondary locale.
- Use **Tailwind logical properties only**: `ms-*`, `me-*`, `ps-*`, `pe-*`, `start-*`,
  `end-*`. A single `ml-4` or `text-left` will break the layout. Enforce this in review.
- Use a real Arabic UI font (IBM Plex Sans Arabic or Noto Kufi Arabic). Do not rely on
  system defaults — they make the interface look unprofessional in Arabic.
- **Numerals render in Latin digits** (`1,850` not `١٬٨٥٠`). Technical figures are read
  faster this way and are consistent with meter displays.
- Dates are **Gregorian**. Timezone is **Asia/Hebron**. Store `timestamptz`; render in
  local time. Be careful with DST when computing daily boundaries.
- All asset and entity names are bilingual: `name_ar` (required) and `name_en` (optional).
  Codes are always Latin/ASCII.
- Set up i18n from the first commit. Do not hardcode Arabic strings in components.

---

## 3. Domain model — core decisions

These decisions were made deliberately. Do not "improve" them without asking.

### 3.1 Measurement points are permanent; meters are not

A physical meter gets replaced, reset, or moved. If readings hang off the meter, every
replacement breaks the historical series. Therefore:

```
measurement_points   permanent logical measuring locations (on an asset or a water path)
meter_devices        physical hardware (serial, digits, multiplier)
meter_installations  which device sat on which point, from when to when
readings             attached to the MEASUREMENT POINT
```

Readings reference `measurement_point_id`, **never** a meter id. This is non-negotiable.

### 3.2 Readings are daily volumes in m³

Field teams enter, every morning, for every source and every meter:

> **the volume in m³ for the previous operational day**

Not a rate. Not a cumulative index. A volume.

Consequences:

- `volume_m3` is the primary stored value and is `NOT NULL`.
- A morning entry describes the **previous day**. The UI must state the covered date
  explicitly ("ضخ يوم الأحد 6/9"), never "today's reading". Off-by-one-day drift is the
  single most common failure in field data systems.
- Because the value is hand-entered and not derivable from anything else, it cannot be
  audited internally. Two cheap mitigations are **required**:
  - `cumulative_index` — nullable, optional secondary field. Nobody is required to fill
    it. When present it gives an independent cross-check and a future migration path to
    cumulative-based truth without schema change.
  - `entry_basis` — how the number was obtained (`METER_DISPLAY`, `METER_DIFF`,
    `PUMP_HOURS`, `ESTIMATE`). One dropdown. It tells us months later which data is solid
    and which is soft. Without it every number looks equally reliable on the dashboard and
    they are not.

### 3.3 A reading covers a period, not a date

Entry is daily, but Fridays, holidays, and vehicle breakdowns happen. Store
`covers_from` / `covers_to` (equal on a normal day) and derive `days_covered`. If two days
are entered together the number stays correct and the charts can distribute it. A single
`reading_date` column would silently corrupt the series.

### 3.4 Operational status lives on the reading

Source status changes day to day. Storing only a current status on the asset means you know
today's state and nothing about last week — which is exactly what explains a drop in
arrivals at Saeer. Each reading carries the asset's `operational_status` for that day. The
asset table keeps a denormalized _current_ status for map rendering only.

### 3.5 Israeli connections are ordinary sources

We read **our own meters, daily, downstream of Mekorot's meters.** So an Israeli connection
is a normal asset with a normal measurement point and a normal daily reading. The only
difference is `supply_type = ISRAELI` for reporting (purchased vs. groundwater produced).

**Do not build an invoice or reconciliation module.** Leave a nullable
`external_reference` field for a future bill-matching feature.

### 3.6 The groundwater transmission line is not modelled pipe by pipe

Several wells inject into the main groundwater transmission system. In Phase 1 we record
each well's daily pumped volume only. We do not model the pipeline, its segments, or its
hydraulics.

### 3.7 Corrections never overwrite

Historical readings are immutable. A correction is a **new row** with
`supersedes_id` pointing at the old one; the old row is marked superseded, never deleted or
edited. Same rule for tank levels.

---

## 4. Database schema

PostgreSQL + PostGIS on Supabase. UUID primary keys. `created_at` / `updated_at` everywhere.
Write this as ordered, re-runnable migration files.

```sql
-- ============ reference / org ============

areas (
  id, code, name_ar, name_en, geom geometry(MultiPolygon,4326) NULL,
  created_at, updated_at
)

profiles (                       -- extends auth.users
  id uuid PK REFERENCES auth.users,
  full_name_ar, full_name_en, phone,
  role text CHECK (role IN
    ('SUPER_ADMIN','WATER_MANAGEMENT','AREA_MANAGER','FIELD_TEAM')),
  is_active bool DEFAULT true,
  created_at, updated_at
)

user_areas (                     -- an area manager / field worker may cover several areas
  user_id, area_id, PRIMARY KEY (user_id, area_id)
)

-- ============ assets ============

water_assets (
  id, code UNIQUE, name_ar, name_en,
  asset_type text CHECK (asset_type IN
    ('WELL','ISRAELI_CONNECTION','TANK','RESERVOIR','PUMPING_STATION','MAIN_METER')),
  -- future types must be addable without schema redesign
  supply_type text NULL CHECK (supply_type IN ('GROUNDWATER','ISRAELI')),
  area_id REFERENCES areas,
  current_status text CHECK (current_status IN
    ('OPERATING','PARTIALLY_OPERATING','STOPPED','MAINTENANCE','DAMAGED','UNKNOWN')),
  geom geometry(Point,4326),                 -- PostGIS, not lat/lng columns
  capacity_m3 numeric NULL,                  -- tanks / reservoirs
  height_m numeric NULL,
  operational_start_date, operational_end_date NULL,
  external_reference text NULL,
  description_ar, description_en,
  created_at, updated_at
)
-- GIST index on geom. Index on (asset_type), (area_id), (current_status).
-- Assets are NEVER deleted. Decommissioning = status + operational_end_date.

level_volume_curve (             -- non-linear tank geometry; optional per asset
  id, asset_id, level_m numeric, volume_m3 numeric,
  UNIQUE (asset_id, level_m)
)
-- If no curve rows exist, fall back to linear: volume = level * (capacity/height).
-- NEVER hardcode "1 m = 5,000 m³" anywhere in application code.

-- ============ measurement ============

measurement_points (
  id, code UNIQUE, name_ar, name_en,
  point_type text CHECK (point_type IN
    ('SOURCE_METER','TRANSFER_METER','TANK_INLET_METER','TANK_OUTLET_METER')),
  -- future: SERVICE_PROVIDER_METER, CONSUMER_METER
  asset_id REFERENCES water_assets NULL,
  water_path_id REFERENCES water_paths NULL,
  CHECK (asset_id IS NOT NULL OR water_path_id IS NOT NULL),
  unit text DEFAULT 'm3',
  is_active bool DEFAULT true,
  expects_daily_reading bool DEFAULT true,     -- drives missing-reading alerts
  area_id REFERENCES areas,
  created_at, updated_at
)
-- An asset MAY have many measurement points. A path MAY have many. Never assume 1:1.

meter_devices (
  id, serial_number, manufacturer, model,
  digit_count int NULL, multiplier numeric DEFAULT 1,
  status text, notes, created_at, updated_at
)

meter_installations (
  id, measurement_point_id, meter_device_id,
  installed_at date, removed_at date NULL,
  index_at_install numeric NULL, index_at_removal numeric NULL,
  notes, created_at, updated_at
)
-- No two overlapping active installations on one point (enforce with an exclusion
-- constraint or a trigger).

readings (
  id,
  measurement_point_id REFERENCES measurement_points NOT NULL,
  covers_from date NOT NULL,
  covers_to   date NOT NULL CHECK (covers_to >= covers_from),
  days_covered int GENERATED ALWAYS AS (covers_to - covers_from + 1) STORED,
  volume_m3 numeric NOT NULL CHECK (volume_m3 >= 0),
  cumulative_index numeric NULL,
  entry_basis text NOT NULL CHECK (entry_basis IN
    ('METER_DISPLAY','METER_DIFF','PUMP_HOURS','ESTIMATE')),
  operational_status text,
  pump_hours numeric NULL,
  validation_status text DEFAULT 'OK'
    CHECK (validation_status IN ('OK','FLAGGED','UNDER_REVIEW','REVIEWED')),
  validation_notes text NULL,
  supersedes_id uuid NULL REFERENCES readings,
  is_superseded bool DEFAULT false,
  entered_by uuid REFERENCES profiles,
  entered_at timestamptz DEFAULT now(),
  notes text,
  UNIQUE (measurement_point_id, covers_from) WHERE is_superseded = false
)
-- Index on (measurement_point_id, covers_from DESC).

tank_level_readings (
  id, asset_id, reading_date date, reading_time timestamptz,
  level_m numeric NOT NULL,
  storage_m3 numeric,            -- computed server-side from curve or linear fallback
  percentage_full numeric,
  supersedes_id, is_superseded,
  entered_by, entered_at, notes,
  UNIQUE (asset_id, reading_date) WHERE is_superseded = false
)

-- ============ topology & balance ============

water_paths (
  id, from_asset_id, to_asset_id,
  connection_type text, sequence_order int,
  active_from date, active_to date NULL,
  name_ar, name_en, notes,
  created_at, updated_at
)
-- Topology is DATA. Adding a well, connection, reservoir or meter must never require
-- a code change.

balance_zones (
  id, code, name_ar, name_en, description, is_active,
  created_at, updated_at
)

balance_zone_members (
  id, zone_id, measurement_point_id,
  role text CHECK (role IN ('INFLOW','OUTFLOW','STORAGE')),
  measurement_quality text CHECK (measurement_quality IN
    ('MEASURED','ESTIMATED','UNMEASURED')),
  sign int DEFAULT 1
)
-- measurement_quality is essential. Without it every balance report shows a huge
-- unexplained gap and users stop trusting the system within two weeks.

-- ============ operations ============

assignments (
  id, user_id, measurement_point_id,
  active_from date, active_to date NULL
)
-- Daily task lists are DERIVED from assignments + expects_daily_reading + missing
-- readings. Do not create a tasks table.

alerts (
  id, alert_type text CHECK (alert_type IN
    ('MISSING_READING','ABNORMAL_READING','SOURCE_STOPPED','SOURCE_MAINTENANCE',
     'LOW_RESERVOIR_LEVEL','HIGH_RESERVOIR_LEVEL','WATER_BALANCE_DISCREPANCY',
     'DATA_VALIDATION_ERROR')),
  severity text CHECK (severity IN ('INFO','WARNING','CRITICAL')),
  status text CHECK (status IN ('OPEN','ACKNOWLEDGED','RESOLVED')),
  asset_id NULL, measurement_point_id NULL,
  reference_date date NULL,
  description_ar, description_en,
  created_at, acknowledged_by, acknowledged_at, resolved_at, resolution_notes
)

audit_logs (
  id, user_id, action, entity_table, entity_id,
  old_value jsonb, new_value jsonb, created_at
)
-- Written by database triggers, not by application code, so nothing can bypass it.
-- Mandatory on: readings, tank_level_readings, water_assets.current_status,
-- measurement_points, water_paths.

import_batches / import_errors   -- Excel import staging; see §8
```

### Server-side logic (PostgreSQL functions)

Put these in the database, not in TypeScript, so every client gets the same answer:

- `get_storage_m3(asset_id, level_m)` — curve lookup with linear interpolation, linear
  fallback.
- `get_missing_readings(from_date, to_date, area_id)` — active points expecting readings
  with no non-superseded row.
- `calculate_zone_balance(zone_id, from_date, to_date)` — returns inflow, outflow, opening
  and closing storage, expected closing, discrepancy, **and data completeness**.
- `flag_abnormal_reading()` — trigger comparing against the point's trailing mean/σ; sets
  `validation_status = 'FLAGGED'`. **Never rejects or deletes. Flags only.**

---

## 5. Water balance — Saeer

The first and only balance zone in Phase 1:

```
INFLOW    daily pumped volumes of all wells feeding the main groundwater
          transmission line  +  Israeli connections feeding it
OUTFLOW   metered service-provider take-offs along the route (where meters exist)
ARRIVAL   volume arriving at the Saeer intermediate reservoir
DIFFERENCE = INFLOW − OUTFLOW(measured) − ARRIVAL
```

Rules:

- The difference contains route take-offs **and** losses **and** data-entry error. We
  cannot separate them yet. **Show it explicitly as "unexplained", never hide or absorb
  it.**
- Every balance figure must be displayed next to its **data completeness** ("19 / 21
  measurement points reported"). A shortfall caused by two missing readings must never read
  as a shortfall caused by losses. This is the difference between a system people trust and
  one they abandon.
- Balance must be computable by day, week, month, and arbitrary date range.

Target screen:

```
الواصل إلى الخزان الوسيط — سعير            الأحد 6/9

  المضخوخ من المصادر         14,200 م³
    آبار جوفية (7 نشطة)       9,600
    وصلات إسرائيلية (2)       4,600
  الواصل إلى سعير            11,900 م³
  ─────────────────────────────────
  الفرق                       2,300 م³   (16%)
    مسحوبات مقيسة               900
    غير مفسَّر                 1,400

  اكتمال البيانات    19 / 21 نقطة قياس
  مصادر متوقفة       بئر بني نعيم 2 (صيانة)
```

---

## 6. Field entry (mobile, one-handed, Arabic)

The morning routine is the system's highest-frequency interaction. Optimize it ruthlessly.

- Task list is generated from assignments; points already entered are checked off.
- One point = one screen: volume in m³ (large numeric keypad), operational status, optional
  cumulative index, entry basis, optional note, submit.
- **The covered date is displayed prominently and is editable** (default: yesterday), so a
  late entry lands on the right day.
- Show the previous few days' values inline so the worker notices an implausible entry
  immediately.
- Offline is not implemented in Phase 1, but nothing may block it: client-generated UUIDs,
  idempotent writes, no server-assigned sequential ids in the write path.

---

## 7. Security

- RLS on every table. Deny by default.
- `SUPER_ADMIN` full access; `WATER_MANAGEMENT` reads all, manages operational data;
  `AREA_MANAGER` scoped to `user_areas`; `FIELD_TEAM` reads only assigned points and
  inserts readings for them, and **cannot update or delete any reading**.
- Corrections by field workers are new rows only. Editing existing rows is a management
  role action and always audited.
- Validate with the same Zod schemas on client and server. Never trust the client.
- Hiding a button is not authorization.

---

## 8. Excel import

Initial data arrives as Excel. Import must be staged: upload → parse into staging tables →
validate columns, coordinates, duplicate codes, asset-code format → preview with a clear
error report → commit only valid rows → keep a permanent `import_batches` log.

Never insert unvalidated spreadsheet data straight into production tables.

---

## 9. Build order

Do **not** build everything at once. Ship each stage working before starting the next.

**Stage 1 — Foundation.** Next.js + TS + Tailwind v4 + HeroUI v3 pinned, Supabase project,
auth, RTL Arabic shell, i18n, design tokens, app layout. No features.

**Stage 2 — Schema.** All migrations above, RLS policies, audit triggers, PostgreSQL
functions, seed data for the Saeer chain only (wells feeding the line, the Israeli
connections, the transmission line, Saeer tank + pumping station, their measurement points).

**Stage 3 — The Saeer vertical slice.** This is the milestone that matters. Field entry
form → readings stored → validation flags → balance function → the Saeer screen in §5
rendering real numbers. One asset chain, working end to end. Stop and review here.

**Stage 4 — Readings management.** Reading history, corrections with supersede, missing
readings view, flagged readings review queue.

**Stage 5 — Asset management.** Full CRUD (no deletes), status management, asset detail
pages, water paths editor.

**Stage 6 — Dashboard.** Sources by status, supply totals, storage, data quality, alerts.

**Stage 7 — GIS.** MapLibre, status-coloured markers, filter by type/status/area, click to
asset detail.

**Stage 8 — Halahoul.** Reservoir levels, level→volume curve, its own balance zone. It is a
second instance of the same pattern, not new architecture.

**Stage 9 — Excel import, reports, alert engine.**

---

## 10. Hard rules

1. Never delete a reading, a level, or an asset. Supersede or change status.
2. Readings attach to measurement points, never to meters.
3. Never assume one asset = one meter, or one path = one measurement point.
4. Topology comes from the database. Adding a well, connection, reservoir, or meter must
   never require a code change.
5. Never hardcode reservoir geometry (`1 m = 5,000 m³`) in application code.
6. Never store a derived value without its inputs.
7. Flag anomalies; never auto-reject or auto-delete.
8. Always show data completeness beside any aggregate figure.
9. Business logic does not live in React components. Separate UI / logic / data access /
   validation.
10. No microservices. No premature abstraction. No tables created "for symmetry".
11. Logical CSS properties only — a single `ml-*` or `text-left` breaks RTL.
12. Do not build Phase 2/3 features: consumer meters, DMAs, NRW, hydraulic modelling,
    SCADA, billing. Do not let the schema block them either.

---

## 11. Definition of done for Phase 1

A water-management user can, in one system, answer:

1. Which sources are operating, stopped, or under maintenance — today and last week?
2. How much was pumped yesterday, from groundwater and from Israeli connections?
3. How much reached the Saeer intermediate reservoir?
4. What is the difference, and how much of it is unexplained?
5. Which readings are missing, and who was responsible for them?
6. Which readings look abnormal?
7. Who entered or changed a reading, when, and what was the previous value?
8. What is the trend over the last week and month?
9. Where is each asset located?

If a screen does not help answer one of these, it does not belong in Phase 1.

---

## Start here

Begin with **Stage 1**. Before writing code, produce a short plan: the file/folder
structure, the design token set, and the exact HeroUI version you will pin. Wait for
approval on that plan before implementing.

When you reach Stage 2, produce the migrations and ask for review before applying them.
