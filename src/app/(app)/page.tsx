import { Card } from "@heroui/react";
import { getLocale, getTranslations } from "next-intl/server";

import { defaultLocale, isLocale } from "@/i18n/config";
import { formatDate, formatVolume } from "@/lib/format";
import { requireUser } from "@/lib/auth/require-user";

/**
 * Stage 1 placeholder home. Demonstrates the formatting rules (Latin digits, Gregorian date,
 * Asia/Hebron) and the data-completeness pattern. Replaced by the Saeer screen in Stage 3.
 */
export default async function HomePage() {
  const t = await getTranslations("home");
  const tCommon = await getTranslations("common");
  const raw = await getLocale();
  const locale = isLocale(raw) ? raw : defaultLocale;
  const user = await requireUser();

  const name =
    (user.user_metadata?.full_name_ar as string | undefined) ??
    (user.user_metadata?.full_name as string | undefined) ??
    user.email ??
    "";

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-semibold">{t("welcome", { name })}</h1>
      <p className="text-muted">{t("todayIs", { date: formatDate(new Date(), locale) })}</p>

      <Card>
        <Card.Content className="flex flex-col gap-2">
          <p>{t("stageNotice")}</p>
          <p className="font-mono text-lg">
            {t("sampleFigure", { volume: formatVolume(11900, locale), unit: tCommon("unitM3") })}
          </p>
          <p className="text-muted text-sm">
            {t("sampleCompleteness", { reported: 19, expected: 21 })}
          </p>
        </Card.Content>
      </Card>
    </div>
  );
}
