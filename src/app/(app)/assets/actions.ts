"use server";

import { revalidatePath } from "next/cache";

import { requireUser } from "@/lib/auth/require-user";
import {
  reinstateAsset,
  retireAsset,
  saveAsset,
  saveMeasurementPoint,
  saveWaterPath,
} from "@/lib/data/assets";
import {
  assetSchema,
  measurementPointSchema,
  retireAssetSchema,
  waterPathSchema,
} from "@/validation/asset";

export type AssetFormState = {
  status: "idle" | "saved" | "error";
  messageKey?: string;
  detail?: string;
  savedId?: string;
};

const str = (v: FormDataEntryValue | null) => (typeof v === "string" ? v.trim() : "");
const optStr = (v: FormDataEntryValue | null) => {
  const s = str(v);
  return s.length > 0 ? s : null;
};
const optNum = (v: FormDataEntryValue | null) => {
  const s = str(v);
  if (s.length === 0) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : Number.NaN;
};
const bool = (v: FormDataEntryValue | null) => str(v) === "true" || str(v) === "on";

function refresh(assetId?: string) {
  revalidatePath("/assets");
  revalidatePath("/assets/placeholders");
  if (assetId) revalidatePath(`/assets/${assetId}`);
  // Renaming or retiring an asset changes what the operational screens show.
  revalidatePath("/saeer");
  revalidatePath("/field-entry");
}

export async function saveAssetAction(
  _prev: AssetFormState,
  formData: FormData,
): Promise<AssetFormState> {
  await requireUser();

  const parsed = assetSchema.safeParse({
    id: optStr(formData.get("id")),
    code: str(formData.get("code")),
    nameAr: str(formData.get("nameAr")),
    nameEn: optStr(formData.get("nameEn")),
    assetType: str(formData.get("assetType")),
    supplyType: optStr(formData.get("supplyType")),
    areaId: optStr(formData.get("areaId")),
    currentStatus: str(formData.get("currentStatus")),
    longitude: optNum(formData.get("longitude")),
    latitude: optNum(formData.get("latitude")),
    capacityM3: optNum(formData.get("capacityM3")),
    heightM: optNum(formData.get("heightM")),
    isPassThrough: bool(formData.get("isPassThrough")),
    passThroughTolerancePct: optNum(formData.get("passThroughTolerancePct")),
    operationalStartDate: optStr(formData.get("operationalStartDate")),
    externalReference: optStr(formData.get("externalReference")),
    descriptionAr: optStr(formData.get("descriptionAr")),
    descriptionEn: optStr(formData.get("descriptionEn")),
  });

  if (!parsed.success) {
    return {
      status: "error",
      messageKey: parsed.error.issues[0]?.message ?? "asset.errors.saveFailed",
    };
  }

  const result = await saveAsset(parsed.data);
  if (!result.ok) return { status: "error", messageKey: result.errorKey, detail: result.detail };

  refresh(result.data);
  return { status: "saved", savedId: result.data };
}

export async function retireAssetAction(
  _prev: AssetFormState,
  formData: FormData,
): Promise<AssetFormState> {
  await requireUser();

  const parsed = retireAssetSchema.safeParse({
    id: str(formData.get("id")),
    endDate: str(formData.get("endDate")),
    status: str(formData.get("status")),
    note: optStr(formData.get("note")),
  });
  if (!parsed.success) {
    return {
      status: "error",
      messageKey: parsed.error.issues[0]?.message ?? "asset.errors.saveFailed",
    };
  }

  const result = await retireAsset(
    parsed.data.id,
    parsed.data.endDate,
    parsed.data.status,
    parsed.data.note ?? null,
  );
  if (!result.ok) return { status: "error", messageKey: result.errorKey, detail: result.detail };

  refresh(parsed.data.id);
  return { status: "saved", savedId: parsed.data.id };
}

export async function reinstateAssetAction(
  _prev: AssetFormState,
  formData: FormData,
): Promise<AssetFormState> {
  await requireUser();
  const id = str(formData.get("id"));
  if (id === "") return { status: "error", messageKey: "asset.errors.saveFailed" };

  const result = await reinstateAsset(id, "OPERATING");
  if (!result.ok) return { status: "error", messageKey: result.errorKey, detail: result.detail };

  refresh(id);
  return { status: "saved", savedId: id };
}

export async function savePointAction(
  _prev: AssetFormState,
  formData: FormData,
): Promise<AssetFormState> {
  await requireUser();

  const parsed = measurementPointSchema.safeParse({
    id: optStr(formData.get("id")),
    code: str(formData.get("code")),
    nameAr: str(formData.get("nameAr")),
    nameEn: optStr(formData.get("nameEn")),
    pointType: str(formData.get("pointType")),
    assetId: optStr(formData.get("assetId")),
    waterPathId: optStr(formData.get("waterPathId")),
    areaId: optStr(formData.get("areaId")),
    expectsDailyReading: bool(formData.get("expectsDailyReading")),
    isActive: bool(formData.get("isActive")),
    excludedFromBalance: bool(formData.get("excludedFromBalance")),
  });
  if (!parsed.success) {
    return {
      status: "error",
      messageKey: parsed.error.issues[0]?.message ?? "asset.errors.saveFailed",
    };
  }

  const result = await saveMeasurementPoint(parsed.data);
  if (!result.ok) return { status: "error", messageKey: result.errorKey, detail: result.detail };

  refresh(parsed.data.assetId ?? undefined);
  return { status: "saved", savedId: result.data };
}

export async function savePathAction(
  _prev: AssetFormState,
  formData: FormData,
): Promise<AssetFormState> {
  await requireUser();

  const parsed = waterPathSchema.safeParse({
    id: optStr(formData.get("id")),
    fromAssetId: str(formData.get("fromAssetId")),
    toAssetId: str(formData.get("toAssetId")),
    connectionType: str(formData.get("connectionType")),
    sequenceOrder: optNum(formData.get("sequenceOrder")),
    nameAr: optStr(formData.get("nameAr")),
    nameEn: optStr(formData.get("nameEn")),
    activeFrom: str(formData.get("activeFrom")),
    activeTo: optStr(formData.get("activeTo")),
    notes: optStr(formData.get("notes")),
  });
  if (!parsed.success) {
    return {
      status: "error",
      messageKey: parsed.error.issues[0]?.message ?? "asset.errors.saveFailed",
    };
  }

  const result = await saveWaterPath(parsed.data);
  if (!result.ok) return { status: "error", messageKey: result.errorKey, detail: result.detail };

  refresh(parsed.data.fromAssetId);
  revalidatePath(`/assets/${parsed.data.toAssetId}`);
  return { status: "saved", savedId: result.data };
}
