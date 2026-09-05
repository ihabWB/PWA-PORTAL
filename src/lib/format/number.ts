import { intlLocaleTag, type Locale } from "@/i18n/config";

/**
 * Numbers always render with Latin digits and grouping separators (e.g. 11,900),
 * regardless of UI locale — technical figures must match meter displays.
 */
export function formatNumber(
  value: number,
  locale: Locale,
  options: Intl.NumberFormatOptions = {},
): string {
  return new Intl.NumberFormat(intlLocaleTag[locale], {
    maximumFractionDigits: 0,
    ...options,
  }).format(value);
}

/** Volume in cubic metres, no unit suffix — the unit is rendered via i18n by the caller. */
export function formatVolume(value: number, locale: Locale): string {
  return formatNumber(value, locale, { maximumFractionDigits: 0 });
}

/** Percentage from a ratio (0.16 → "16%"). */
export function formatPercent(ratio: number, locale: Locale, fractionDigits = 0): string {
  return new Intl.NumberFormat(intlLocaleTag[locale], {
    style: "percent",
    maximumFractionDigits: fractionDigits,
  }).format(ratio);
}
