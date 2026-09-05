import { Card, Link as HeroLink } from "@heroui/react";
import { getTranslations } from "next-intl/server";

import { AssetForm } from "@/components/assets/asset-form";
import { DataError } from "@/components/common/data-error";
import { getAreas } from "@/lib/data/assets";

export default async function NewAssetPage() {
  const t = await getTranslations("asset");
  const tc = await getTranslations("common");
  const areas = await getAreas();

  if (!areas.ok) return <DataError errorKey={areas.errorKey} detail={areas.detail} />;

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4">
      <HeroLink href="/assets" className="text-sm">
        {tc("back")}
      </HeroLink>
      <h1 className="text-xl font-semibold">{t("addAsset")}</h1>
      <Card>
        <Card.Content className="py-4">
          <AssetForm areas={areas.data} />
        </Card.Content>
      </Card>
    </div>
  );
}
