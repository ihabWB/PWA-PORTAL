"use client";

import { Button } from "@heroui/react";
import { useLocale, useTranslations } from "next-intl";
import { useTransition } from "react";

import { setLocaleAction } from "@/i18n/actions";
import { type Locale } from "@/i18n/config";

/** Toggles between Arabic and English by writing the locale cookie, then re-rendering. */
export function LocaleSwitcher() {
  const t = useTranslations("common");
  const locale = useLocale() as Locale;
  const [pending, startTransition] = useTransition();
  const target: Locale = locale === "ar" ? "en" : "ar";

  return (
    <Button
      variant="ghost"
      size="sm"
      isPending={pending}
      aria-label={t("language")}
      onPress={() => startTransition(() => setLocaleAction(target))}
    >
      {target === "ar" ? t("arabic") : t("english")}
    </Button>
  );
}
