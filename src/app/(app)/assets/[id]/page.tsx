import { Alert, Card, Chip, Link as HeroLink } from "@heroui/react";
import { notFound } from "next/navigation";
import { getLocale, getTranslations } from "next-intl/server";

import { AssetForm } from "@/components/assets/asset-form";
import { PathForm } from "@/components/assets/path-form";
import { PointForm } from "@/components/assets/point-form";
import { RetirePanel } from "@/components/assets/retire-panel";
import { DataError } from "@/components/common/data-error";
import { defaultLocale, isLocale } from "@/i18n/config";
import {
  getAreas,
  getAsset,
  getAssetCatalogue,
  getAssetPaths,
  getAssetPoints,
} from "@/lib/data/assets";
import { maxCoveredDate } from "@/lib/domain/operational-day";
import { formatDate, formatNumber } from "@/lib/format";

/** Asset detail: identity, its measurement points, its topology, and retirement. */
export default async function AssetDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const t = await getTranslations("asset");
  const tc = await getTranslations("common");
  const tp = await getTranslations("pointType");
  const rawLocale = await getLocale();
  const locale = isLocale(rawLocale) ? rawLocale : defaultLocale;

  const { id } = await params;

  const [assetResult, areasResult, pointsResult, pathsResult, catalogueResult] = await Promise.all([
    getAsset(id),
    getAreas(),
    getAssetPoints(id),
    getAssetPaths(id),
    getAssetCatalogue(true),
  ]);

  for (const r of [assetResult, areasResult, pointsResult, pathsResult, catalogueResult]) {
    if (!r.ok) return <DataError errorKey={r.errorKey} detail={r.detail} />;
  }
  if (
    !assetResult.ok ||
    !areasResult.ok ||
    !pointsResult.ok ||
    !pathsResult.ok ||
    !catalogueResult.ok
  ) {
    return null;
  }

  const asset = assetResult.data;
  if (!asset) notFound();

  const today = maxCoveredDate();
  const candidates = catalogueResult.data
    .filter((a) => a.id !== asset.id)
    .map((a) => ({ id: a.id, code: a.code, nameAr: a.name_ar }));

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-5">
      <HeroLink href="/assets" className="text-sm">
        {tc("back")}
      </HeroLink>

      <header className="flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="text-xl font-semibold">
          {locale === "ar" ? asset.name_ar : (asset.name_en ?? asset.name_ar)}
        </h1>
        <span className="flex items-center gap-2">
          {asset.is_placeholder && (
            <Chip size="sm" variant="soft" color="warning">
              {t("placeholder")}
            </Chip>
          )}
          <span className="text-muted font-mono text-xs">{asset.code}</span>
        </span>
      </header>

      {asset.longitude === null && (
        <Alert status="accent">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{t("noCoordinatesNotice")}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}

      <Card>
        <Card.Header>
          <Card.Title>{t("identity")}</Card.Title>
        </Card.Header>
        <Card.Content className="py-4">
          <AssetForm
            areas={areasResult.data}
            isPlaceholder={asset.is_placeholder}
            initial={{
              id: asset.id,
              code: asset.code,
              nameAr: asset.name_ar,
              nameEn: asset.name_en,
              assetType: asset.asset_type,
              supplyType: asset.supply_type,
              areaId: asset.area_id,
              currentStatus: asset.current_status,
              longitude: asset.longitude,
              latitude: asset.latitude,
              capacityM3: asset.capacity_m3 === null ? null : Number(asset.capacity_m3),
              heightM: asset.height_m === null ? null : Number(asset.height_m),
              isPassThrough: asset.is_pass_through,
              operationalStartDate: asset.operational_start_date,
            }}
          />
        </Card.Content>
      </Card>

      <Card>
        <Card.Header>
          <Card.Title>{t("pointsTitle")}</Card.Title>
          <Card.Description>{t("pointsHelp")}</Card.Description>
        </Card.Header>
        <Card.Content className="flex flex-col gap-4 py-4">
          {pointsResult.data.length === 0 ? (
            <p className="text-muted text-sm">{t("noPoints")}</p>
          ) : (
            <ul className="flex flex-col">
              {pointsResult.data.map((p) => (
                <li
                  key={p.id}
                  className="border-separator flex flex-wrap items-baseline justify-between gap-2 border-b py-2 last:border-b-0"
                >
                  <span className="flex min-w-0 flex-col">
                    <span className="flex flex-wrap items-center gap-2">
                      <span>{locale === "ar" ? p.name_ar : (p.name_en ?? p.name_ar)}</span>
                      {p.is_placeholder && (
                        <Chip size="sm" variant="soft" color="warning">
                          {t("placeholder")}
                        </Chip>
                      )}
                      {!p.expects_daily_reading && (
                        <Chip size="sm" variant="soft">
                          {t("notDaily")}
                        </Chip>
                      )}
                      {!p.is_active && (
                        <Chip size="sm" variant="soft">
                          {t("pointInactive")}
                        </Chip>
                      )}
                    </span>
                    <span className="text-muted flex flex-wrap gap-2 text-xs">
                      <span className="font-mono">{p.code}</span>
                      <span>{tp(p.point_type)}</span>
                    </span>
                  </span>
                  <span className="text-muted font-mono text-xs whitespace-nowrap tabular-nums">
                    {t("readingCount", { count: formatNumber(p.reading_count, locale) })}
                    {p.last_reading_date
                      ? ` · ${formatDate(`${p.last_reading_date}T00:00:00Z`, locale)}`
                      : ""}
                  </span>
                </li>
              ))}
            </ul>
          )}

          <details className="border-border rounded-(--radius) border p-3">
            <summary className="cursor-pointer text-sm font-medium">{t("addPoint")}</summary>
            <div className="pt-3">
              <PointForm assetId={asset.id} areaId={asset.area_id} />
            </div>
          </details>
        </Card.Content>
      </Card>

      <Card>
        <Card.Header>
          <Card.Title>{t("pathsTitle")}</Card.Title>
          <Card.Description>{t("pathsHelp")}</Card.Description>
        </Card.Header>
        <Card.Content className="flex flex-col gap-4 py-4">
          {pathsResult.data.length === 0 ? (
            <p className="text-muted text-sm">{t("noPaths")}</p>
          ) : (
            <ul className="flex flex-col">
              {pathsResult.data.map((p) => (
                <li
                  key={`${p.id}-${p.direction}`}
                  className="border-separator flex flex-wrap items-baseline justify-between gap-2 border-b py-2 last:border-b-0"
                >
                  <span className="flex flex-wrap items-center gap-2">
                    <Chip size="sm" variant="soft">
                      {p.direction === "OUT" ? t("pathOut") : t("pathIn")}
                    </Chip>
                    <span>{p.other_name_ar}</span>
                    <span className="text-muted font-mono text-xs">{p.other_code}</span>
                  </span>
                  <span className="text-muted text-xs">
                    {p.connection_type}
                    {p.is_active ? "" : ` · ${t("pathEnded")}`}
                  </span>
                </li>
              ))}
            </ul>
          )}

          <details className="border-border rounded-(--radius) border p-3">
            <summary className="cursor-pointer text-sm font-medium">{t("addPath")}</summary>
            <div className="pt-3">
              <PathForm fromAssetId={asset.id} candidates={candidates} today={today} />
            </div>
          </details>
        </Card.Content>
      </Card>

      <Card>
        <Card.Header>
          <Card.Title>{t("retireTitle")}</Card.Title>
        </Card.Header>
        <Card.Content className="py-4">
          <RetirePanel
            assetId={asset.id}
            isRetired={asset.is_retired}
            endDate={asset.operational_end_date}
            today={today}
            readingCount={asset.reading_count}
          />
        </Card.Content>
      </Card>
    </div>
  );
}
