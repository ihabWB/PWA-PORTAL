"use server";

import { revalidatePath } from "next/cache";

import { requireUser } from "@/lib/auth/require-user";
import { createReading } from "@/lib/data/readings";
import { readingEntrySchema } from "@/validation/reading";

export type ReadingFormState = {
  status: "idle" | "saved" | "error";
  /** i18n key of the message to display. */
  messageKey?: string;
  flagged?: boolean;
};

/**
 * Server Action for a daily reading. Re-validates with the SAME Zod schema the browser
 * used: the client is never trusted. Nothing is updated in place — a correction is a new
 * row carrying supersedesId.
 */
export async function submitReadingAction(
  _prev: ReadingFormState,
  formData: FormData,
): Promise<ReadingFormState> {
  const user = await requireUser();

  const raw = {
    id: str(formData.get("id")),
    measurementPointId: str(formData.get("measurementPointId")),
    coversFrom: str(formData.get("coversFrom")),
    coversTo: str(formData.get("coversTo")),
    volumeM3: numOrNaN(formData.get("volumeM3")),
    cumulativeIndex: optionalNum(formData.get("cumulativeIndex")),
    entryBasis: str(formData.get("entryBasis")),
    operationalStatus: str(formData.get("operationalStatus")),
    pumpHours: optionalNum(formData.get("pumpHours")),
    notes: optionalStr(formData.get("notes")),
    supersedesId: optionalStr(formData.get("supersedesId")),
  };

  const parsed = readingEntrySchema.safeParse(raw);
  if (!parsed.success) {
    return {
      status: "error",
      messageKey: parsed.error.issues[0]?.message ?? "reading.errors.saveFailed",
    };
  }

  const result = await createReading(parsed.data, user.id);
  if (!result.ok) {
    return { status: "error", messageKey: result.errorKey };
  }

  revalidatePath("/field-entry");
  revalidatePath("/saeer");
  return { status: "saved", flagged: result.flagged };
}

function str(v: FormDataEntryValue | null): string {
  return typeof v === "string" ? v.trim() : "";
}

function optionalStr(v: FormDataEntryValue | null): string | null {
  const s = str(v);
  return s.length > 0 ? s : null;
}

function numOrNaN(v: FormDataEntryValue | null): number {
  const s = str(v);
  return s.length > 0 ? Number(s) : Number.NaN;
}

function optionalNum(v: FormDataEntryValue | null): number | null {
  const s = str(v);
  if (s.length === 0) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}
