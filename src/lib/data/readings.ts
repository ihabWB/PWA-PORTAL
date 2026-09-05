import "server-only";

import { dailyAverage } from "@/lib/domain/operational-day";
import { createClient } from "@/lib/supabase/server";
import type { ReadingEntryInput } from "@/validation/reading";
import type { ReadingRow } from "@/types/database";

export type RecentReading = {
  id: string;
  coversFrom: string;
  coversTo: string;
  daysCovered: number;
  volumeM3: number;
  /** Volume per day, so a multi-day entry is comparable with the daily ones beside it. */
  dailyAverageM3: number;
  operationalStatus: ReadingRow["operational_status"];
  entryBasis: ReadingRow["entry_basis"];
  validationStatus: ReadingRow["validation_status"];
  isSuperseded: boolean;
};

/**
 * The previous few days on a point, newest first. Shown inline in the entry form so an
 * implausible value is noticed at the moment of entry rather than months later.
 */
export async function getRecentReadings(pointId: string, limit = 7): Promise<RecentReading[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("readings")
    .select(
      "id, covers_from, covers_to, days_covered, volume_m3, operational_status, entry_basis, validation_status, is_superseded",
    )
    .eq("measurement_point_id", pointId)
    .eq("is_superseded", false)
    .order("covers_from", { ascending: false })
    .limit(limit);

  if (error || !data) return [];

  return data.map((r) => ({
    id: r.id,
    coversFrom: r.covers_from,
    coversTo: r.covers_to,
    daysCovered: r.days_covered,
    volumeM3: Number(r.volume_m3),
    dailyAverageM3: dailyAverage(Number(r.volume_m3), r.covers_from, r.covers_to),
    operationalStatus: r.operational_status,
    entryBasis: r.entry_basis,
    validationStatus: r.validation_status,
    isSuperseded: r.is_superseded,
  }));
}

export type CreateReadingResult =
  { ok: true; readingId: string; flagged: boolean } | { ok: false; errorKey: string };

/**
 * Store a reading. The id comes from the client, so a retried submit is idempotent and
 * nothing blocks offline entry later. Corrections are new rows carrying supersedesId —
 * no existing row is ever edited.
 */
export async function createReading(
  input: ReadingEntryInput,
  userId: string,
): Promise<CreateReadingResult> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("readings")
    .insert({
      id: input.id,
      measurement_point_id: input.measurementPointId,
      covers_from: input.coversFrom,
      covers_to: input.coversTo,
      volume_m3: input.volumeM3,
      cumulative_index: input.cumulativeIndex ?? null,
      entry_basis: input.entryBasis,
      operational_status: input.operationalStatus,
      pump_hours: input.pumpHours ?? null,
      notes: input.notes ?? null,
      supersedes_id: input.supersedesId ?? null,
      entered_by: userId,
    })
    .select("id, validation_status")
    .single();

  if (error) {
    // Same id twice: the first submit already succeeded. Treat the retry as success.
    if (error.code === "23505" && (await readingExists(input.id))) {
      return { ok: true, readingId: input.id, flagged: false };
    }
    if (error.code === "23505") return { ok: false, errorKey: "reading.errors.alreadyEntered" };
    if (error.code === "23P01") return { ok: false, errorKey: "reading.errors.periodOverlaps" };
    if (error.code === "42501") return { ok: false, errorKey: "reading.errors.notPermitted" };
    return { ok: false, errorKey: "reading.errors.saveFailed" };
  }

  return { ok: true, readingId: data.id, flagged: data.validation_status === "FLAGGED" };
}

async function readingExists(id: string): Promise<boolean> {
  const supabase = await createClient();
  const { data } = await supabase.from("readings").select("id").eq("id", id).maybeSingle();
  return Boolean(data);
}
