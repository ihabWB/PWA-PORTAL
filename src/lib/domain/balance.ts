import type { StoppedSource, ZoneBalanceRow } from "@/types/database";

/**
 * Presentation model for a water-balance period.
 *
 * Two rules from the spec are enforced here rather than in components:
 *   - every aggregate travels with its data completeness;
 *   - the difference is split into what was actually measured and what is unexplained,
 *     and the unexplained part is never hidden or absorbed.
 */
export type BalanceView = {
  from: string;
  to: string;
  days: number;
  /** Total pumped upstream. */
  inflowM3: number;
  groundwaterM3: number;
  israeliM3: number;
  /** What reached the destination node. */
  arrivalM3: number;
  /** Metered take-offs along the route (0 while no route meters are read daily). */
  measuredOutflowM3: number;
  /** inflow − measured outflow − arrival − storage change. */
  differenceM3: number;
  differenceRatio: number | null;
  /** The part of the difference nothing accounts for. */
  unexplainedM3: number;
  storageChangeM3: number | null;
  storageComplete: boolean;
  completeness: Completeness;
  sources: SourceCounts;
  stoppedSources: StoppedSource[];
  /** True when at least one expected point did not report; every total is then a floor. */
  hasGap: boolean;
};

export type Completeness = {
  reported: number;
  expected: number;
  ratio: number;
  pointDaysReported: number;
  pointDaysExpected: number;
};

export type SourceCounts = {
  total: number;
  operating: number;
  groundwaterReported: number;
  groundwaterTotal: number;
  israeliReported: number;
  israeliTotal: number;
};

export function toBalanceView(row: ZoneBalanceRow): BalanceView {
  const expected = row.points_expected;
  const reported = row.points_complete;

  return {
    from: row.period_from,
    to: row.period_to,
    days: row.days,
    inflowM3: num(row.inflow_m3),
    groundwaterM3: num(row.inflow_groundwater_m3),
    israeliM3: num(row.inflow_israeli_m3),
    arrivalM3: num(row.arrival_m3),
    measuredOutflowM3: num(row.outflow_measured_m3),
    differenceM3: num(row.difference_m3),
    differenceRatio: row.difference_pct === null ? null : num(row.difference_pct) / 100,
    // Measured take-offs are already subtracted by the SQL function; whatever remains is
    // route losses, unmetered take-offs and data-entry error together. We cannot separate
    // them yet, so the whole remainder is reported as unexplained.
    unexplainedM3: num(row.difference_m3),
    storageChangeM3: row.storage_change_m3 === null ? null : num(row.storage_change_m3),
    storageComplete: row.storage_complete,
    completeness: {
      reported,
      expected,
      ratio: expected > 0 ? reported / expected : 1,
      pointDaysReported: row.point_days_reported,
      pointDaysExpected: row.point_days_expected,
    },
    sources: {
      total: row.sources_total,
      operating: row.sources_operating,
      groundwaterReported: row.sources_groundwater_reported,
      groundwaterTotal: row.sources_groundwater_total,
      israeliReported: row.sources_israeli_reported,
      israeliTotal: row.sources_israeli_total,
    },
    stoppedSources: row.stopped_sources ?? [],
    hasGap: expected > reported,
  };
}

/** PostgREST returns numeric as a string; never let that reach arithmetic. */
function num(value: number | string | null): number {
  if (value === null) return 0;
  return typeof value === "number" ? value : Number(value);
}
