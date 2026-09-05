import "server-only";

import { classifyPostgrestError, fail, ok, type DataResult } from "@/lib/data/result";
import { createClient } from "@/lib/supabase/server";
import type { DailyEntryTaskRow } from "@/types/database";

export type EntryTask = {
  pointId: string;
  code: string;
  nameAr: string;
  nameEn: string | null;
  pointType: DailyEntryTaskRow["point_type"];
  assetNameAr: string | null;
  assetType: DailyEntryTaskRow["asset_type"];
  supplyType: DailyEntryTaskRow["supply_type"];
  isAssigned: boolean;
  /** Non-null when this point already has a reading covering the day. */
  readingId: string | null;
  volumeM3: number | null;
  operationalStatus: DailyEntryTaskRow["operational_status"];
  validationStatus: DailyEntryTaskRow["validation_status"];
};

export type EntryTaskList = {
  date: string;
  tasks: EntryTask[];
  done: number;
  pending: number;
};

/**
 * The morning task list for one operational day. Derived in PostgreSQL from measurement
 * points, assignments and missing readings — there is no tasks table by design.
 * RLS scopes the result: a field worker sees only their assigned points.
 */
export async function getDailyEntryTasks(date: string): Promise<DataResult<EntryTaskList>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_daily_entry_tasks", { p_date: date });

  if (error) return fail(classifyPostgrestError(error.code), error.message);
  if (!data) return fail("errors.queryFailed", "empty response");

  const tasks: EntryTask[] = (data as DailyEntryTaskRow[]).map((row) => ({
    pointId: row.measurement_point_id,
    code: row.code,
    nameAr: row.name_ar,
    nameEn: row.name_en,
    pointType: row.point_type,
    assetNameAr: row.asset_name_ar,
    assetType: row.asset_type,
    supplyType: row.supply_type,
    isAssigned: row.is_assigned,
    readingId: row.reading_id,
    volumeM3: row.volume_m3 === null ? null : Number(row.volume_m3),
    operationalStatus: row.operational_status,
    validationStatus: row.validation_status,
  }));

  const done = tasks.filter((t) => t.readingId !== null).length;
  return ok({ date, tasks, done, pending: tasks.length - done });
}

export async function getEntryTask(
  pointId: string,
  date: string,
): Promise<DataResult<EntryTask | null>> {
  const result = await getDailyEntryTasks(date);
  if (!result.ok) return result;
  return ok(result.data.tasks.find((t) => t.pointId === pointId) ?? null);
}
