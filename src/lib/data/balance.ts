import "server-only";

import { toBalanceView, type BalanceView } from "@/lib/domain/balance";
import { classifyPostgrestError, fail, ok, type DataResult } from "@/lib/data/result";
import { createClient } from "@/lib/supabase/server";
import type { ZoneBalanceRow } from "@/types/database";

/** The Phase 1 balance zone. Looked up by code so the id is never hardcoded. */
export const SAEER_ZONE_CODE = "SAEER-TRANSIT";

export type ZoneMeta = { id: string; code: string; nameAr: string; nameEn: string | null };

export async function getZoneByCode(code: string): Promise<DataResult<ZoneMeta>> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("balance_zones")
    .select("id, code, name_ar, name_en")
    .eq("code", code)
    .maybeSingle();

  if (error) return fail(classifyPostgrestError(error.code), error.message);
  if (!data) return fail("errors.zoneMissing", code);
  return ok({ id: data.id, code: data.code, nameAr: data.name_ar, nameEn: data.name_en });
}

/** Columns the screen depends on; their absence means a migration has not been applied. */
const REQUIRED_COLUMNS = [
  "inflow_m3",
  "arrival_m3",
  "difference_m3",
  "points_expected",
  "sources_groundwater_total",
  "sources_israeli_total",
] as const;

/**
 * Water balance for a zone over an inclusive date range.
 * All arithmetic happens in PostgreSQL so every client gets the same answer.
 */
export async function getZoneBalance(
  zoneId: string,
  from: string,
  to: string,
): Promise<DataResult<BalanceView>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("calculate_zone_balance", {
    p_zone_id: zoneId,
    p_from: from,
    p_to: to,
  });

  if (error) return fail(classifyPostgrestError(error.code), error.message);
  if (!data || data.length === 0) return fail("errors.queryFailed", "empty result");

  const row = data[0] as ZoneBalanceRow;
  const missing = REQUIRED_COLUMNS.filter((c) => !(c in row));
  if (missing.length > 0) {
    return fail(
      "errors.migrationMissing",
      `calculate_zone_balance is missing: ${missing.join(", ")}`,
    );
  }

  return ok(toBalanceView(row));
}
