/**
 * i18n configuration. Arabic is the primary locale; English is secondary.
 * Locale is stored in a cookie — there is no locale prefix in the URL.
 */
export const locales = ["ar", "en"] as const;
export type Locale = (typeof locales)[number];

export const defaultLocale: Locale = "ar";

export const LOCALE_COOKIE = "NEXT_LOCALE";

/** Text direction per locale. RTL is the default experience. */
export const localeDirection: Record<Locale, "rtl" | "ltr"> = {
  ar: "rtl",
  en: "ltr",
};

/**
 * BCP-47 tags handed to Intl and React Aria.
 * `nu-latn` forces Latin digits; `ca-gregory` forces the Gregorian calendar.
 */
export const intlLocaleTag: Record<Locale, string> = {
  ar: "ar-PS-u-ca-gregory-nu-latn",
  en: "en-GB-u-ca-gregory-nu-latn",
};

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && (locales as readonly string[]).includes(value);
}
