import { z } from "zod";

import { MAX_COVERED_DAYS, daysCovered, maxCoveredDate } from "@/lib/domain/operational-day";

/**
 * Daily reading entry. The SAME schema runs in the browser and in the Server Action.
 * Messages are i18n keys resolved by the caller — never hardcoded strings.
 */
const dateKey = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, { message: "reading.errors.dateInvalid" });

export const entryBasisValues = ["METER_DISPLAY", "METER_DIFF", "PUMP_HOURS", "ESTIMATE"] as const;

export const operationalStatusValues = [
  "OPERATING",
  "PARTIALLY_OPERATING",
  "STOPPED",
  "MAINTENANCE",
  "DAMAGED",
  "UNKNOWN",
] as const;

export const readingEntrySchema = z
  .object({
    /** Client-generated so a retried submit is idempotent and offline stays possible. */
    id: z.uuid({ message: "reading.errors.idInvalid" }),
    measurementPointId: z.uuid({ message: "reading.errors.pointInvalid" }),
    coversFrom: dateKey,
    coversTo: dateKey,
    volumeM3: z
      .number({ message: "reading.errors.volumeRequired" })
      .min(0, { message: "reading.errors.volumeNegative" })
      .max(10_000_000, { message: "reading.errors.volumeTooLarge" }),
    cumulativeIndex: z
      .number()
      .min(0, { message: "reading.errors.indexNegative" })
      .nullable()
      .optional(),
    entryBasis: z.enum(entryBasisValues, { message: "reading.errors.basisRequired" }),
    operationalStatus: z.enum(operationalStatusValues, {
      message: "reading.errors.statusRequired",
    }),
    pumpHours: z
      .number()
      .min(0)
      .max(24 * MAX_COVERED_DAYS)
      .nullable()
      .optional(),
    notes: z.string().max(1000).nullable().optional(),
    /** Set when this entry corrects an existing reading; the old row is superseded, never edited. */
    supersedesId: z.uuid().nullable().optional(),
  })
  .refine((v) => v.coversTo >= v.coversFrom, {
    message: "reading.errors.periodReversed",
    path: ["coversTo"],
  })
  .refine((v) => v.coversTo <= maxCoveredDate(), {
    message: "reading.errors.periodInFuture",
    path: ["coversTo"],
  })
  .refine((v) => daysCovered(v.coversFrom, v.coversTo) <= MAX_COVERED_DAYS, {
    message: "reading.errors.periodTooLong",
    path: ["coversTo"],
  })
  // PUMP_HOURS as the basis means the number came from running hours, so record them.
  .refine((v) => v.entryBasis !== "PUMP_HOURS" || (v.pumpHours ?? 0) > 0, {
    message: "reading.errors.pumpHoursRequired",
    path: ["pumpHours"],
  });

export type ReadingEntryInput = z.infer<typeof readingEntrySchema>;
