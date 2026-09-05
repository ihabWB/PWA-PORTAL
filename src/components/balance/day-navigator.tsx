"use client";

import { Button } from "@heroui/react";
import { useLocale, useTranslations } from "next-intl";
import { useRouter } from "next/navigation";

import { defaultLocale, isLocale } from "@/i18n/config";
import { maxCoveredDate, shiftDateKey } from "@/lib/domain/operational-day";
import { formatOperationalDay } from "@/lib/format";

type DayNavigatorProps = {
  date: string;
  basePath: string;
};

/**
 * Moves one operational day at a time. The covered day is always spelled out, never
 * implied: "today's reading" is exactly the phrasing that causes off-by-one drift.
 * Direction is handled by the RTL layout, so the buttons stay labelled, not arrowed.
 */
export function DayNavigator({ date, basePath }: DayNavigatorProps) {
  const t = useTranslations("common");
  const router = useRouter();
  const raw = useLocale();
  const locale = isLocale(raw) ? raw : defaultLocale;
  const today = maxCoveredDate();

  const go = (next: string) => router.push(`${basePath}?date=${next}`);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Button size="sm" variant="secondary" onPress={() => go(shiftDateKey(date, -1))}>
        {t("previousDay")}
      </Button>
      <span className="font-mono text-sm">{formatOperationalDay(`${date}T00:00:00Z`, locale)}</span>
      <Button
        size="sm"
        variant="secondary"
        isDisabled={shiftDateKey(date, 1) > today}
        onPress={() => go(shiftDateKey(date, 1))}
      >
        {t("nextDay")}
      </Button>
    </div>
  );
}
