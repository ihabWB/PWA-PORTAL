import { Alert, Card, Chip, Link as HeroLink } from "@heroui/react";
import { getLocale, getTranslations } from "next-intl/server";

import { DataError } from "@/components/common/data-error";
import { defaultLocale, isLocale } from "@/i18n/config";
import { getPlaceholderRows } from "@/lib/data/assets";
import { formatNumber } from "@/lib/format";
import type { PlaceholderRow } from "@/types/database";

/**
 * Placeholder inventory. The Saeer seed created rows with temporary codes so the vertical
 * slice could be built before the real catalogue existed. This screen keeps that fact visible
 * until every one is replaced, so seed data cannot quietly become production data.
 */
export default async function PlaceholdersPage() {
  const t = await getTranslations("asset");
  const tc = await getTranslations("common");
  const ta = await getTranslations("assetType");
  const tp = await getTranslations("pointType");
  const rawLocale = await getLocale();
  const locale = isLocale(rawLocale) ? rawLocale : defaultLocale;

  const result = await getPlaceholderRows();
  if (!result.ok) return <DataError errorKey={result.errorKey} detail={result.detail} />;

  const assets = result.data.filter((r) => r.entity === "ASSET");
  const points = result.data.filter((r) => r.entity === "MEASUREMENT_POINT");
  const withReadings = result.data.filter((r) => Number(r.reading_count) > 0).length;

  const row = (r: PlaceholderRow, kindLabel: string) => (
    <li
      key={`${r.entity}-${r.id}`}
      className="border-separator flex flex-wrap items-baseline justify-between gap-2 border-b py-2 last:border-b-0"
    >
      <span className="flex min-w-0 flex-col">
        <span>{locale === "ar" ? r.name_ar : (r.name_en ?? r.name_ar)}</span>
        <span className="text-muted flex flex-wrap items-center gap-2 text-xs">
          <span className="font-mono">{r.code}</span>
          <span>{kindLabel}</span>
        </span>
      </span>
      <span className="flex shrink-0 items-center gap-3">
        {Number(r.reading_count) > 0 && (
          <Chip size="sm" variant="soft">
            {t("readingCount", { count: formatNumber(Number(r.reading_count), locale) })}
          </Chip>
        )}
        {r.parent_asset_id && (
          <HeroLink href={`/assets/${r.parent_asset_id}`} className="text-sm">
            {r.entity === "ASSET" ? t("rename") : t("renameFromAsset")}
          </HeroLink>
        )}
      </span>
    </li>
  );

  return (
    <div className="flex flex-col gap-4">
      <HeroLink href="/assets" className="text-sm">
        {tc("back")}
      </HeroLink>

      <header className="flex flex-col gap-1">
        <h1 className="text-xl font-semibold">{t("placeholdersTitle")}</h1>
        <p className="text-muted text-sm">{t("placeholdersSubtitle")}</p>
      </header>

      {result.data.length === 0 ? (
        <Alert status="success">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>{t("placeholdersDoneTitle")}</Alert.Title>
            <Alert.Description>{t("placeholdersDoneBody")}</Alert.Description>
          </Alert.Content>
        </Alert>
      ) : (
        <>
          <Alert status="warning">
            <Alert.Indicator />
            <Alert.Content>
              <Alert.Title>
                {t("placeholdersRemaining", { assets: assets.length, points: points.length })}
              </Alert.Title>
              <Alert.Description>{t("placeholdersHowTo")}</Alert.Description>
            </Alert.Content>
          </Alert>

          {withReadings > 0 && (
            <Alert status="accent">
              <Alert.Indicator />
              <Alert.Content>
                <Alert.Description>
                  {t("placeholdersWithReadings", { count: withReadings })}
                </Alert.Description>
              </Alert.Content>
            </Alert>
          )}

          {assets.length > 0 && (
            <Card>
              <Card.Header>
                <Card.Title>{t("placeholderAssets")}</Card.Title>
              </Card.Header>
              <Card.Content className="py-2">
                <ul className="flex flex-col">{assets.map((r) => row(r, ta(r.kind as never)))}</ul>
              </Card.Content>
            </Card>
          )}

          {points.length > 0 && (
            <Card>
              <Card.Header>
                <Card.Title>{t("placeholderPoints")}</Card.Title>
                <Card.Description>{t("placeholderPointsHelp")}</Card.Description>
              </Card.Header>
              <Card.Content className="py-2">
                <ul className="flex flex-col">{points.map((r) => row(r, tp(r.kind as never)))}</ul>
              </Card.Content>
            </Card>
          )}
        </>
      )}
    </div>
  );
}
