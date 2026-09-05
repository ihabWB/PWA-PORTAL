import { getLocale, getTranslations } from "next-intl/server";

import { BalanceSheet } from "@/components/balance/balance-sheet";
import { DayNavigator } from "@/components/balance/day-navigator";
import { DataError } from "@/components/common/data-error";
import { defaultLocale, isLocale } from "@/i18n/config";
import { SAEER_ZONE_CODE, getZoneBalance, getZoneByCode } from "@/lib/data/balance";
import { defaultCoveredDate, maxCoveredDate } from "@/lib/domain/operational-day";
import { formatOperationalDay } from "@/lib/format";

/**
 * The question Phase 1 exists to answer: how much water reached the Saeer intermediate
 * reservoir compared with how much was pumped upstream.
 */
export default async function SaeerPage({
  searchParams,
}: {
  searchParams: Promise<{ date?: string }>;
}) {
  const t = await getTranslations("saeer");
  const rawLocale = await getLocale();
  const locale = isLocale(rawLocale) ? rawLocale : defaultLocale;

  const { date } = await searchParams;
  const day = isDateKey(date) && date <= maxCoveredDate() ? date : defaultCoveredDate();

  const zone = await getZoneByCode(SAEER_ZONE_CODE);
  if (!zone.ok) return <DataError errorKey={zone.errorKey} detail={zone.detail} />;

  const balance = await getZoneBalance(zone.data.id, day, day);

  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="text-xl font-semibold">
          {locale === "ar" ? zone.data.nameAr : (zone.data.nameEn ?? zone.data.nameAr)}
        </h1>
        <p className="text-muted text-sm">{formatOperationalDay(`${day}T00:00:00Z`, locale)}</p>
      </header>

      <DayNavigator date={day} basePath="/saeer" />

      {balance.ok ? (
        <BalanceSheet balance={balance.data} locale={locale} />
      ) : (
        <DataError errorKey={balance.errorKey} detail={balance.detail} />
      )}

      <p className="text-muted text-xs">{t("noOfftakeMeters")}</p>
    </div>
  );
}

function isDateKey(v: string | undefined): v is string {
  return typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
}
