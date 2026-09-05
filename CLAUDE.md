# CLAUDE.md

Project instructions for Claude Code. Read this at the start of every session.

## Read first

**[`SPEC.md`](./SPEC.md) is the authoritative specification.** Read it in full before
writing code in a new session. It contains the domain model, the database schema, the build
order, and the reasoning behind decisions that look arbitrary but are not.

If a longer original technical specification exists in this repo, `SPEC.md` overrides it
wherever they conflict.

## What this project is

An operational water-management platform for a Palestinian water utility — monitoring water
sources, daily pumped volumes, storage, and water balance. It is a decision-support system,
not a CRUD app.

**The question Phase 1 must answer:** how much water actually reaches the intermediate
reservoir at Saeer Pumping Station, compared with how much was pumped upstream.

## Stack

Next.js (App Router) · TypeScript · Tailwind CSS v4 · HeroUI v3 (pinned exactly) ·
React Hook Form + Zod · Recharts · MapLibre GL JS · Supabase (PostgreSQL + PostGIS) · RLS.

## Standing rules

These are violated most often. Check against them before every commit.

1. **RTL only.** Arabic is the primary language. Use logical properties (`ms-*`, `me-*`,
   `ps-*`, `pe-*`, `start-*`, `end-*`). A single `ml-*`, `pr-*`, or `text-left` breaks the
   layout. No hardcoded Arabic strings — everything goes through i18n.
2. **Readings attach to `measurement_point_id`, never to a meter.** Meters get replaced;
   the series must survive.
3. **Nothing is ever deleted.** Readings and levels are superseded by a new row
   (`supersedes_id`). Assets are retired by status + `operational_end_date`.
4. **Never store a derived value without its inputs.**
5. **Topology is data.** Adding a well, connection, reservoir, or meter must never require
   a code change. No hardcoded asset names, ids, or counts anywhere.
6. **Never hardcode reservoir geometry** (e.g. `1 m = 5,000 m³`). Use the level→volume
   curve function with linear fallback.
7. **Flag anomalies, never auto-reject or auto-delete.**
8. **Always show data completeness beside any aggregate.** "11,900 m³ · 19/21 points
   reported". A gap caused by missing readings must never read as a gap caused by losses.
9. **Use HeroUI for standard components**, themed through our design tokens — never
   HeroUI's default look, and never a hand-built button/input/table/modal.
10. **No business logic in React components.** Separate UI / logic / data access /
    validation. Server-side calculations live in PostgreSQL functions.
11. **RLS on every table, deny by default.** Hiding a button is not authorization. Validate
    with the same Zod schema on client and server.
12. **Do not build Phase 2/3 features**: consumer meters, DMAs, NRW, hydraulic modelling,
    SCADA, billing. Do not let the schema block them either.

## Working agreement

- **Follow the staged build order in `SPEC.md` §9.** Do not jump ahead. Do not build
  screens before the data model works.
- **Stop for review at the end of Stage 1 and Stage 2.** Present the plan / the migrations
  and wait for approval before proceeding. Schema changes after real readings exist are
  expensive.
- **Ask before deviating** from any decision in `SPEC.md`. Several of them look
  over-engineered and are not — the reasoning is in the document.
- Prefer small, reviewable commits. One concern per commit.
- When something in the spec is genuinely ambiguous, ask rather than guess. Guessing wrong
  on the data model costs weeks.

## Running locally

```
cp .env.example .env.local   # fill in Supabase URL + publishable key (sb_publishable_...)
npm install
npm run dev                  # http://localhost:3000
npm run typecheck && npm run lint && npm run check:rtl && npm run build
```

Supabase is a hosted project (no local CLI/Docker). Deployment target is Vercel; set the same
env vars there. The project uses Supabase's **new API keys**: only the publishable key
(`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`) is used, on client and server alike. **Never use a
secret key (`sb_secret_...`) anywhere** — it bypasses RLS. If a task seems to need it, stop and
ask first. Next.js 16 uses `src/proxy.ts` (formerly `middleware.ts`) for session refresh
and the auth gate.

## Conventions

- Migrations: ordered, re-runnable SQL files under `supabase/migrations/`.
- UUID primary keys, `created_at` / `updated_at` on every table, `timestamptz` stored,
  rendered in `Asia/Hebron`.
- Bilingual entity names: `name_ar` (required), `name_en` (optional). Codes are ASCII.
- Numerals render as Latin digits; dates are Gregorian.
- Pin `@heroui/react` to an exact version — no `^`. Upgrades are deliberate and tested.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
