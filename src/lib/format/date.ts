import { intlLocaleTag, type Locale } from "@/i18n/config";
import { APP_TIMEZONE } from "@/lib/env";

const TZ = APP_TIMEZONE;

/**
 * Dates are Gregorian, rendered in the application timezone (Asia/Hebron) with Latin digits.
 * Storage is always `timestamptz`; only rendering happens here.
 */
export function formatDate(
  value: Date | string,
  locale: Locale,
  options: Intl.DateTimeFormatOptions = { year: "numeric", month: "numeric", day: "numeric" },
): string {
  const date = typeof value === "string" ? new Date(value) : value;
  return new Intl.DateTimeFormat(intlLocaleTag[locale], { timeZone: TZ, ...options }).format(date);
}

/** e.g. "الأحد 6/9" — weekday + day/month, used for the covered operational day. */
export function formatOperationalDay(value: Date | string, locale: Locale): string {
  return formatDate(value, locale, { weekday: "long", day: "numeric", month: "numeric" });
}

export function formatDateTime(value: Date | string, locale: Locale): string {
  return formatDate(value, locale, {
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * Calendar date (YYYY-MM-DD) in the application timezone for a given instant.
 * DST-safe: derived from Intl parts, never from the UTC getters.
 */
export function toLocalDateKey(instant: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(instant);
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

/** Yesterday's calendar date in the application timezone — default covered day for field entry. */
export function yesterdayDateKey(now: Date = new Date()): string {
  const todayKey = toLocalDateKey(now);
  const [y, m, d] = todayKey.split("-").map(Number) as [number, number, number];
  const yesterdayUtc = new Date(Date.UTC(y, m - 1, d - 1));
  return yesterdayUtc.toISOString().slice(0, 10);
}
