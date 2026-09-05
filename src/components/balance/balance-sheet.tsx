import { Alert, Card, Chip } from "@heroui/react";
import { getTranslations } from "next-intl/server";

import type { Locale } from "@/i18n/config";
import type { BalanceView } from "@/lib/domain/balance";
import { formatPercent, formatVolume } from "@/lib/format";

type BalanceSheetProps = {
  balance: BalanceView;
  locale: Locale;
};

/**
 * Presentational only. Every figure arrives already computed; no arithmetic happens here.
 * Data completeness sits beside the totals because a shortfall caused by missing readings
 * must never read as a shortfall caused by losses.
 */
export async function BalanceSheet({ balance, locale }: BalanceSheetProps) {
  const t = await getTranslations("saeer");
  const tc = await getTranslations("common");
  const ts = await getTranslations("status");
  const unit = tc("unitM3");
  const missing = balance.completeness.expected - balance.completeness.reported;

  return (
    <div className="flex flex-col gap-4">
      {balance.hasGap && (
        <Alert status="warning">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{t("gapWarning", { missing })}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}

      <Card>
        <Card.Content className="flex flex-col gap-1 py-2">
          <Line
            label={t("pumped")}
            value={formatVolume(balance.inflowM3, locale)}
            unit={unit}
            emphasis
          />
          <Line
            label={t("groundwater")}
            note={t("reportedOf", {
              reported: balance.sources.groundwaterReported,
              total: balance.sources.groundwaterTotal,
            })}
            value={formatVolume(balance.groundwaterM3, locale)}
            indent
          />
          <Line
            label={t("israeli")}
            note={t("reportedOf", {
              reported: balance.sources.israeliReported,
              total: balance.sources.israeliTotal,
            })}
            value={formatVolume(balance.israeliM3, locale)}
            indent
          />

          <Line
            label={t("arrival")}
            value={formatVolume(balance.arrivalM3, locale)}
            unit={unit}
            emphasis
          />

          <hr className="border-separator my-2" />

          <Line
            label={t("difference")}
            value={formatVolume(balance.differenceM3, locale)}
            unit={unit}
            note={
              balance.differenceRatio === null
                ? undefined
                : formatPercent(balance.differenceRatio, locale)
            }
            emphasis
          />
          <Line
            label={t("measuredOfftakes")}
            value={formatVolume(balance.measuredOutflowM3, locale)}
            indent
          />
          <Line
            label={t("unexplained")}
            value={formatVolume(balance.unexplainedM3, locale)}
            indent
          />
        </Card.Content>
      </Card>

      <Card>
        <Card.Content className="flex flex-col gap-3 py-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <span className="text-muted text-sm">{t("completeness")}</span>
            <span className="font-mono text-sm">
              {t("completenessValue", {
                reported: balance.completeness.reported,
                expected: balance.completeness.expected,
              })}
            </span>
          </div>
          <div className="flex flex-wrap items-start justify-between gap-2">
            <span className="text-muted text-sm">{t("stoppedSources")}</span>
            <span className="flex flex-wrap justify-end gap-1">
              {balance.stoppedSources.length === 0 ? (
                <span className="text-sm">{t("noStoppedSources")}</span>
              ) : (
                balance.stoppedSources.map((s) => (
                  <Chip key={s.asset_id} size="sm" variant="soft" color="warning">
                    {`${locale === "ar" ? s.name_ar : (s.name_en ?? s.name_ar)} · ${ts(s.status)}`}
                  </Chip>
                ))
              )}
            </span>
          </div>
        </Card.Content>
      </Card>
    </div>
  );
}

type LineProps = {
  label: string;
  value: string;
  unit?: string;
  note?: string;
  indent?: boolean;
  emphasis?: boolean;
};

function Line({ label, value, unit, note, indent, emphasis }: LineProps) {
  return (
    <div
      className={`flex items-baseline justify-between gap-3 py-1 ${indent ? "ps-4" : ""} ${
        emphasis ? "font-semibold" : "text-muted"
      }`}
    >
      <span className="min-w-0 truncate">
        {label}
        {note ? <span className="text-muted ms-2 text-xs font-normal">{note}</span> : null}
      </span>
      <span className="font-mono whitespace-nowrap tabular-nums">
        {value}
        {unit ? <span className="text-muted ms-1 text-xs font-normal">{unit}</span> : null}
      </span>
    </div>
  );
}
