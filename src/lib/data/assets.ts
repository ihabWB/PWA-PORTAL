import "server-only";

import { classifyPostgrestError, fail, ok, type DataResult } from "@/lib/data/result";
import { createClient } from "@/lib/supabase/server";
import type {
  AreaRow,
  AssetCatalogueRow,
  AssetPathRow,
  AssetPointRow,
  PlaceholderRow,
} from "@/types/database";
import type { AssetInput, MeasurementPointInput, WaterPathInput } from "@/validation/asset";

export type AssetSummary = AssetCatalogueRow;

export async function getAssetCatalogue(
  includeRetired = true,
): Promise<DataResult<AssetSummary[]>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_asset_catalogue", {
    p_include_retired: includeRetired,
  });
  if (error) return fail(classifyPostgrestError(error.code), error.message);
  return ok((data ?? []) as AssetCatalogueRow[]);
}

export async function getAsset(id: string): Promise<DataResult<AssetSummary | null>> {
  const all = await getAssetCatalogue(true);
  if (!all.ok) return all;
  return ok(all.data.find((a) => a.id === id) ?? null);
}

export async function getAreas(): Promise<DataResult<AreaRow[]>> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("areas")
    .select("id, code, name_ar, name_en")
    .order("name_ar");
  if (error) return fail(classifyPostgrestError(error.code), error.message);
  return ok((data ?? []) as AreaRow[]);
}

export async function getAssetPoints(assetId: string): Promise<DataResult<AssetPointRow[]>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_asset_points", { p_asset_id: assetId });
  if (error) return fail(classifyPostgrestError(error.code), error.message);
  return ok((data ?? []) as AssetPointRow[]);
}

export async function getAssetPaths(assetId: string): Promise<DataResult<AssetPathRow[]>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_asset_paths", { p_asset_id: assetId });
  if (error) return fail(classifyPostgrestError(error.code), error.message);
  return ok((data ?? []) as AssetPathRow[]);
}

export async function getPlaceholderRows(): Promise<DataResult<PlaceholderRow[]>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_placeholder_rows", {});
  if (error) return fail(classifyPostgrestError(error.code), error.message);
  return ok((data ?? []) as PlaceholderRow[]);
}

// ---------------------------------------------------------------------------
// Writes. Every one goes through a database function so the no-delete rule and the
// geometry handling stay in one place.
// ---------------------------------------------------------------------------

function writeError(code: string | undefined, message: string): string {
  if (code === "23505") return "asset.errors.codeTaken";
  if (code === "23514") return "asset.errors.constraintViolated";
  if (code === "22023")
    return message.includes("Coordinates")
      ? "asset.errors.longitudeRange"
      : "asset.errors.invalidInput";
  if (code === "42501") return "errors.notPermitted";
  return "asset.errors.saveFailed";
}

export async function saveAsset(input: AssetInput): Promise<DataResult<string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("upsert_water_asset", {
    p_id: input.id ?? null,
    p_code: input.code,
    p_name_ar: input.nameAr,
    p_name_en: input.nameEn ?? null,
    p_asset_type: input.assetType,
    p_supply_type: input.supplyType ?? null,
    p_area_id: input.areaId ?? null,
    p_current_status: input.currentStatus,
    p_longitude: input.longitude ?? null,
    p_latitude: input.latitude ?? null,
    p_capacity_m3: input.capacityM3 ?? null,
    p_height_m: input.heightM ?? null,
    p_is_pass_through: input.isPassThrough ?? false,
    p_pass_through_tolerance_pct: input.passThroughTolerancePct ?? null,
    p_operational_start_date: input.operationalStartDate ?? null,
    p_external_reference: input.externalReference ?? null,
    p_description_ar: input.descriptionAr ?? null,
    p_description_en: input.descriptionEn ?? null,
  });
  if (error) return fail(writeError(error.code, error.message), error.message);
  return ok(data as string);
}

export async function retireAsset(
  id: string,
  endDate: string,
  status: string,
  note: string | null,
): Promise<DataResult<string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("retire_water_asset", {
    p_id: id,
    p_end_date: endDate,
    p_status: status,
    p_note: note,
  });
  if (error) return fail(writeError(error.code, error.message), error.message);
  return ok(data as string);
}

export async function reinstateAsset(id: string, status: string): Promise<DataResult<string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("reinstate_water_asset", {
    p_id: id,
    p_status: status,
  });
  if (error) return fail(writeError(error.code, error.message), error.message);
  return ok(data as string);
}

export async function saveMeasurementPoint(
  input: MeasurementPointInput,
): Promise<DataResult<string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("upsert_measurement_point", {
    p_id: input.id ?? null,
    p_code: input.code,
    p_name_ar: input.nameAr,
    p_name_en: input.nameEn ?? null,
    p_point_type: input.pointType,
    p_asset_id: input.assetId ?? null,
    p_water_path_id: input.waterPathId ?? null,
    p_area_id: input.areaId ?? null,
    p_expects_daily_reading: input.expectsDailyReading,
    p_is_active: input.isActive,
  });
  if (error) return fail(writeError(error.code, error.message), error.message);
  return ok(data as string);
}

export async function saveWaterPath(input: WaterPathInput): Promise<DataResult<string>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("upsert_water_path", {
    p_id: input.id ?? null,
    p_from_asset_id: input.fromAssetId,
    p_to_asset_id: input.toAssetId,
    p_connection_type: input.connectionType,
    p_sequence_order: input.sequenceOrder ?? null,
    p_name_ar: input.nameAr ?? null,
    p_name_en: input.nameEn ?? null,
    p_active_from: input.activeFrom,
    p_active_to: input.activeTo ?? null,
    p_notes: input.notes ?? null,
  });
  if (error) return fail(writeError(error.code, error.message), error.message);
  return ok(data as string);
}
