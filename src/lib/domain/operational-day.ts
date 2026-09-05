import { toLocalDateKey, yesterdayDateKey } from "@/lib/format/date";

/**
 * The operational day a morning entry describes.
 *
 * A morning entry always describes the PREVIOUS day. Off-by-one drift is the single most
 * common failure in field data systems, so the covered date is explicit everywhere: it is
 * computed here, displayed prominently, and editable by the user for late entries.
 * No business logic of this kind lives in components.
 */

/** Default covered day for a new entry: yesterday in the application timezone. */
export function defaultCoveredDate(now: Date = new Date()): string {
  return yesterdayDateKey(now);
}

/** Today in the application timezone; the latest day an entry may cover. */
export function maxCoveredDate(now: Date = new Date()): string {
  return toLocalDateKey(now);
}

/** Inclusive day count of a covered period. */
export function daysCovered(from: string, to: string): number {
  return (
    Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000) + 1
  );
}

/** Average daily volume of a period reading; the comparable figure across entries. */
export function dailyAverage(volumeM3: number, from: string, to: string): number {
  const days = daysCovered(from, to);
  return days > 0 ? volumeM3 / days : volumeM3;
}

export type CoveredPeriodProblem = "END_BEFORE_START" | "IN_THE_FUTURE" | "TOO_LONG";

/** Maximum period a single entry may cover. Longer spans are almost always a typo. */
export const MAX_COVERED_DAYS = 62;

export function validateCoveredPeriod(
  from: string,
  to: string,
  now: Date = new Date(),
): CoveredPeriodProblem | null {
  if (to < from) return "END_BEFORE_START";
  if (to > maxCoveredDate(now)) return "IN_THE_FUTURE";
  if (daysCovered(from, to) > MAX_COVERED_DAYS) return "TOO_LONG";
  return null;
}

/** Shift a date key by whole days without crossing a DST boundary. */
export function shiftDateKey(dateKey: string, days: number): string {
  const [y, m, d] = dateKey.split("-").map(Number) as [number, number, number];
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}
