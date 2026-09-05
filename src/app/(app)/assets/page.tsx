import { Alert, Card, Link as HeroLink } from "@heroui/react";
import { getLocale, getTranslations } from "next-intl/server";

import { AssetTable } from "@/components/assets/asset-table";
import { DataError } from "@/components/common/data-error";
import { defaultLocale, isLocale } from "@/i18n/config";
import { getAssetCatalogue } from "@/lib/data/assets";

/** The asset catalogue. Retired assets stay listed — nothing is ever removed. */
export default async function AssetsPage({
  searchParams,
}: {
  searchParams: Promise<{ retired?: string; placeholders?: string }>;
}) {
  const t = await getTranslations("asset");
  const rawLocale = await getLocale();
  const locale = isLocale(rawLocale) ? rawLocale : defaultLocale;

  const { retired, placeholders } = await searchParams;
  const includeRetired = retired !== "0";
  const result = await getAssetCatalogue(includeRetired);

  if (!result.ok) return <DataError errorKey={result.errorKey} detail={result.detail} />;

  const onlyPlaceholders = placeholders === "1";
  const assets = onlyPlaceholders ? result.data.filter((a) => a.is_placeholder) : result.data;
  const placeholderCount = result.data.filter((a) => a.is_placeholder).length;

  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <HeroLink href="/assets/new" className="text-sm">
          {t("addAsset")}
        </HeroLink>
      </header>

      {placeholderCount > 0 && (
        <Alert status="warning">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>{t("placeholdersOpenTitle", { count: placeholderCount })}</Alert.Title>
            <Alert.Description>{t("placeholdersOpenBody")}</Alert.Description>
            <HeroLink href="/assets/placeholders" className="mt-2 inline-block text-sm">
              {t("openPlaceholderTool")}
            </HeroLink>
          </Alert.Content>
        </Alert>
      )}

      <nav className="flex flex-wrap gap-3 text-sm">
        <HeroLink href="/assets">{t("filterAll")}</HeroLink>
        <HeroLink href="/assets?retired=0">{t("filterActive")}</HeroLink>
        <HeroLink href="/assets?placeholders=1">{t("filterPlaceholders")}</HeroLink>
      </nav>

      {assets.length === 0 ? (
        <Card>
          <Card.Content className="py-6">
            <p className="text-muted text-sm">{t("empty")}</p>
          </Card.Content>
        </Card>
      ) : (
        <>
          <p className="text-muted text-sm">{t("countLabel", { count: assets.length })}</p>
          <AssetTable assets={assets} locale={locale} />
        </>
      )}
    </div>
  );
}
