import { Alert, Card, Link } from "@heroui/react";
import { notFound } from "next/navigation";
import { getLocale, getTranslations } from "next-intl/server";

import { DataError } from "@/components/common/data-error";
import { ReadingEntryForm } from "@/components/readings/reading-entry-form";
import { RecentReadings } from "@/components/readings/recent-readings";
import { defaultLocale, isLocale } from "@/i18n/config";
import { getEntryTask } from "@/lib/data/entry-tasks";
import { getRecentReadings } from "@/lib/data/readings";
import { defaultCoveredDate, maxCoveredDate } from "@/lib/domain/operational-day";
import { formatOperationalDay } from "@/lib/format";

/** One point, one screen. Everything needed to enter a day's volume and nothing else. */
export default async function ReadingEntryPage({
  params,
  searchParams,
}: {
  params: Promise<{ pointId: string }>;
  searchParams: Promise<{ date?: string }>;
}) {
  const t = await getTranslations("entry");
  const tc = await getTranslations("common");
  const rawLocale = await getLocale();
  const locale = isLocale(rawLocale) ? rawLocale : defaultLocale;

  const { pointId } = await params;
  const { date } = await searchParams;
  const day = isDateKey(date) && date <= maxCoveredDate() ? date : defaultCoveredDate();

  // RLS decides visibility: an unassigned point simply is not in the list.
  const result = await getEntryTask(pointId, day);
  if (!result.ok) return <DataError errorKey={result.errorKey} detail={result.detail} />;
  const task = result.data;
  if (!task) notFound();

  const recent = await getRecentReadings(pointId, 7);
  const existing = task.readingId !== null;

  return (
    <div className="mx-auto flex w-full max-w-lg flex-col gap-4">
      <div>
        <Link href={`/field-entry?date=${day}`} className="text-sm">
          {tc("back")}
        </Link>
      </div>

      <header className="flex flex-col gap-1">
        <h1 className="text-xl font-semibold">
          {locale === "ar" ? task.nameAr : (task.nameEn ?? task.nameAr)}
        </h1>
        <p className="text-muted font-mono text-xs">{task.code}</p>
      </header>

      <p className="bg-accent-soft text-accent-soft-foreground rounded-(--radius) px-3 py-2 font-medium">
        {t("coveredDay", { date: formatOperationalDay(`${day}T00:00:00Z`, locale) })}
      </p>

      {existing && (
        <Alert status="accent">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{t("alreadyEntered")}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}

      <Card>
        <Card.Content className="py-4">
          <ReadingEntryForm
            pointId={task.pointId}
            defaultDate={day}
            maxDate={maxCoveredDate()}
            supersedesId={task.readingId}
            defaultStatus={task.operationalStatus ?? "OPERATING"}
          />
        </Card.Content>
      </Card>

      <RecentReadings readings={recent} locale={locale} />
    </div>
  );
}

function isDateKey(v: string | undefined): v is string {
  return typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
}
