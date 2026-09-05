import { getLocale, getTranslations } from "next-intl/server";

import { DayNavigator } from "@/components/balance/day-navigator";
import { DataError } from "@/components/common/data-error";
import { TaskList } from "@/components/readings/task-list";
import { defaultLocale, isLocale } from "@/i18n/config";
import { getDailyEntryTasks } from "@/lib/data/entry-tasks";
import { defaultCoveredDate, maxCoveredDate } from "@/lib/domain/operational-day";
import { formatOperationalDay } from "@/lib/format";

/**
 * The morning routine: what still has to be entered for the previous operational day.
 * The list is derived from assignments and missing readings, never stored.
 */
export default async function FieldEntryPage({
  searchParams,
}: {
  searchParams: Promise<{ date?: string }>;
}) {
  const t = await getTranslations("entry");
  const rawLocale = await getLocale();
  const locale = isLocale(rawLocale) ? rawLocale : defaultLocale;

  const { date } = await searchParams;
  const day = isDateKey(date) && date <= maxCoveredDate() ? date : defaultCoveredDate();
  const list = await getDailyEntryTasks(day);

  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-col gap-1">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <p className="text-muted text-sm">{t("subtitle")}</p>
      </header>

      <p className="bg-accent-soft text-accent-soft-foreground rounded-(--radius) px-3 py-2 font-medium">
        {t("coveredDay", { date: formatOperationalDay(`${day}T00:00:00Z`, locale) })}
      </p>

      <DayNavigator date={day} basePath="/field-entry" />

      {list.ok ? (
        <TaskList list={list.data} locale={locale} />
      ) : (
        <DataError errorKey={list.errorKey} detail={list.detail} />
      )}
    </div>
  );
}

function isDateKey(v: string | undefined): v is string {
  return typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
}
