import { z } from "zod";

import {
  ASSET_TYPES,
  OPERATIONAL_STATUSES,
  OPTIONAL_SUPPLY_ASSET_TYPES,
  POINT_TYPES,
  SOURCE_ASSET_TYPES,
} from "@/types/database";

/**
 * Asset, measurement point and water path schemas. Shared by the browser and the Server
 * Actions — the client is never trusted. Messages are i18n keys resolved by the caller.
 */

/** ASCII, upper case, no spaces. Codes are identifiers, not labels. */
const codeSchema = z
  .string()
  .trim()
  .min(2, { message: "asset.errors.codeTooShort" })
  .max(32, { message: "asset.errors.codeTooLong" })
  .regex(/^[A-Za-z0-9][A-Za-z0-9_-]*$/, { message: "asset.errors.codeFormat" });

const optionalDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, { message: "asset.errors.dateInvalid" })
  .nullable()
  .optional();

export const assetSchema = z
  .object({
    id: z.uuid().nullable().optional(),
    code: codeSchema,
    nameAr: z.string().trim().min(2, { message: "asset.errors.nameArRequired" }).max(200),
    nameEn: z.string().trim().max(200).nullable().optional(),
    assetType: z.enum(ASSET_TYPES, { message: "asset.errors.typeRequired" }),
    supplyType: z.enum(["GROUNDWATER", "ISRAELI"]).nullable().optional(),
    areaId: z.uuid({ message: "asset.errors.areaInvalid" }).nullable().optional(),
    currentStatus: z.enum(OPERATIONAL_STATUSES, { message: "asset.errors.statusRequired" }),
    // Coordinates are optional on purpose. An empty coordinate is truer than an invented one.
    longitude: z
      .number()
      .min(-180, { message: "asset.errors.longitudeRange" })
      .max(180, { message: "asset.errors.longitudeRange" })
      .nullable()
      .optional(),
    latitude: z
      .number()
      .min(-90, { message: "asset.errors.latitudeRange" })
      .max(90, { message: "asset.errors.latitudeRange" })
      .nullable()
      .optional(),
    capacityM3: z
      .number()
      .positive({ message: "asset.errors.capacityPositive" })
      .nullable()
      .optional(),
    heightM: z.number().positive({ message: "asset.errors.heightPositive" }).nullable().optional(),
    isPassThrough: z.boolean().optional(),
    passThroughTolerancePct: z
      .number()
      .min(0, { message: "asset.errors.tolerancePositive" })
      .max(100, { message: "asset.errors.tolerancePositive" })
      .nullable()
      .optional(),
    operationalStartDate: optionalDate,
    externalReference: z.string().trim().max(200).nullable().optional(),
    descriptionAr: z.string().trim().max(2000).nullable().optional(),
    descriptionEn: z.string().trim().max(2000).nullable().optional(),
  })
  // Both coordinates or neither: half a pair is not a location.
  .refine((v) => (v.longitude == null) === (v.latitude == null), {
    message: "asset.errors.coordinatePair",
    path: ["latitude"],
  })
  // A source must say where its water comes from.
  .refine((v) => !SOURCE_ASSET_TYPES.includes(v.assetType) || v.supplyType != null, {
    message: "asset.errors.supplyTypeRequired",
    path: ["supplyType"],
  })
  // A main meter may declare one without being obliged to; anything else must not claim one.
  .refine(
    (v) =>
      SOURCE_ASSET_TYPES.includes(v.assetType) ||
      OPTIONAL_SUPPLY_ASSET_TYPES.includes(v.assetType) ||
      v.supplyType == null,
    { message: "asset.errors.supplyTypeNotAllowed", path: ["supplyType"] },
  )
  // Storage geometry is either fully known or left unknown; a half-known tank invents volumes.
  .refine((v) => (v.capacityM3 == null) === (v.heightM == null), {
    message: "asset.errors.geometryPair",
    path: ["heightM"],
  });

export type AssetInput = z.infer<typeof assetSchema>;

export const retireAssetSchema = z.object({
  id: z.uuid(),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, { message: "asset.errors.dateInvalid" }),
  status: z.enum(["STOPPED", "DAMAGED", "MAINTENANCE", "UNKNOWN"], {
    message: "asset.errors.retireStatus",
  }),
  note: z.string().trim().max(1000).nullable().optional(),
});

export const measurementPointSchema = z
  .object({
    id: z.uuid().nullable().optional(),
    code: codeSchema,
    nameAr: z.string().trim().min(2, { message: "asset.errors.nameArRequired" }).max(200),
    nameEn: z.string().trim().max(200).nullable().optional(),
    pointType: z.enum(POINT_TYPES, { message: "asset.errors.pointTypeRequired" }),
    assetId: z.uuid().nullable().optional(),
    waterPathId: z.uuid().nullable().optional(),
    areaId: z.uuid().nullable().optional(),
    expectsDailyReading: z.boolean(),
    isActive: z.boolean(),
    /** Measured upstream of a storage node: the same water is counted again downstream. */
    excludedFromBalance: z.boolean(),
  })
  .refine((v) => v.assetId != null || v.waterPathId != null, {
    message: "asset.errors.pointNeedsHost",
    path: ["assetId"],
  });

export type MeasurementPointInput = z.infer<typeof measurementPointSchema>;

export const waterPathSchema = z
  .object({
    id: z.uuid().nullable().optional(),
    fromAssetId: z.uuid({ message: "asset.errors.pathEndpointRequired" }),
    toAssetId: z.uuid({ message: "asset.errors.pathEndpointRequired" }),
    connectionType: z
      .string()
      .trim()
      .min(2, { message: "asset.errors.connectionTypeRequired" })
      .max(64),
    sequenceOrder: z.number().int().min(0).max(10_000).nullable().optional(),
    nameAr: z.string().trim().max(200).nullable().optional(),
    nameEn: z.string().trim().max(200).nullable().optional(),
    activeFrom: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, { message: "asset.errors.dateInvalid" }),
    activeTo: optionalDate,
    notes: z.string().trim().max(1000).nullable().optional(),
  })
  .refine((v) => v.fromAssetId !== v.toAssetId, {
    message: "asset.errors.pathSelfLoop",
    path: ["toAssetId"],
  })
  .refine((v) => v.activeTo == null || v.activeTo >= v.activeFrom, {
    message: "asset.errors.pathPeriodReversed",
    path: ["activeTo"],
  });

export type WaterPathInput = z.infer<typeof waterPathSchema>;

/** A code the seed created. Renaming one keeps its readings; it is not a new row. */
export function isPlaceholderCode(code: string): boolean {
  return code.toUpperCase().includes("TMP");
}
