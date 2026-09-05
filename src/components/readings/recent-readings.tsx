import { Card, Chip } from "@heroui/react";
import { getTranslations } from "next-intl/server";

import type { Locale } from "@/i18n/config";
import type { RecentReading } from "@/lib/data/readings";
import { formatDate, formatNumber, formatVolume } from "@/lib/format";

type RecentReadingsProps = {
  readings: RecentReading[];
  locale: Locale;
};

/**
 * Previous days, inline. A worker who sees yesterday's 1,200 beside a typed 12,000 notices
 * the extra zero immediately; nobody notices it three months later in a report.
 */
export async function RecentReadings({ readings, locale }: RecentReadingsProps) {
  const t = await getTranslations("entry");
  const tc = await getTranslations("common");
  const tv = await getTranslations("validation");

  return (
    <Card>
      <Card.Header>
        <Card.Title>{t("recent")}</Card.Title>
      </Card.Header>
      <Card.Content className="py-2">
        {readings.length === 0 ? (
          <p className="text-muted text-sm">{t("recentEmpty")}</p>
        ) : (
          <ul className="flex flex-col">
            {readings.map((r) => (
              <li
                key={r.id}
                className="border-separator flex items-baseline justify-between gap-3 border-b py-2 last:border-b-0"
              >
                <span className="flex min-w-0 flex-col">
                  <span className="text-sm">{formatDate(`${r.coversFrom}T00:00:00Z`, locale)}</span>
                  {r.daysCovered > 1 && (
                    <span className="text-muted text-xs">
                      {t("multiDay", { days: r.daysCovered })} ·{" "}
                      {t("perDay", { value: formatNumber(r.dailyAverageM3, locale) })}
                    </span>
                  )}
                </span>
                <span className="flex shrink-0 items-center gap-2">
                  {r.validationStatus !== "OK" && (
                    <Chip size="sm" variant="soft" color="warning">
                      {tv(r.validationStatus)}
                    </Chip>
                  )}
                  <span className="font-mono text-sm whitespace-nowrap tabular-nums">
                    {formatVolume(r.volumeM3, locale)}
                    <span className="text-muted ms-1 text-xs">{tc("unitM3")}</span>
                  </span>
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card.Content>
    </Card>
  );
}
