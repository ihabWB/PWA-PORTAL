import { Chip } from "@heroui/react";
import Link from "next/link";
import { getTranslations } from "next-intl/server";

import type { Locale } from "@/i18n/config";
import type { AssetSummary } from "@/lib/data/assets";
import { formatNumber } from "@/lib/format";

type AssetTableProps = {
  assets: AssetSummary[];
  locale: Locale;
};

/**
 * Dense operational table, ours rather than HeroUI's, per the spec. A missing coordinate is
 * printed as a dash and labelled, never filled in with a guess.
 */
export async function AssetTable({ assets, locale }: AssetTableProps) {
  const t = await getTranslations("asset");
  const ta = await getTranslations("assetType");
  const ts = await getTranslations("status");

  return (
    <div className="border-border overflow-x-auto rounded-(--radius) border">
      <table className="w-full text-start text-sm">
        <thead className="bg-surface-secondary text-muted">
          <tr>
            <th className="px-3 py-2 text-start font-medium">{t("code")}</th>
            <th className="px-3 py-2 text-start font-medium">{t("name")}</th>
            <th className="px-3 py-2 text-start font-medium">{t("assetTypeLabel")}</th>
            <th className="px-3 py-2 text-start font-medium">{t("area")}</th>
            <th className="px-3 py-2 text-start font-medium">{t("currentStatus")}</th>
            <th className="px-3 py-2 text-start font-medium">{t("coordinates")}</th>
            <th className="px-3 py-2 text-start font-medium">{t("points")}</th>
          </tr>
        </thead>
        <tbody>
          {assets.map((a) => (
            <tr key={a.id} className="border-border border-t">
              <td className="px-3 py-2 font-mono text-xs">
                <Link
                  href={`/assets/${a.id}`}
                  className="text-accent underline-offset-2 hover:underline"
                >
                  {a.code}
                </Link>
              </td>
              <td className="px-3 py-2">
                <span className="flex flex-wrap items-center gap-2">
                  {locale === "ar" ? a.name_ar : (a.name_en ?? a.name_ar)}
                  {a.is_placeholder && (
                    <Chip size="sm" variant="soft" color="warning">
                      {t("placeholder")}
                    </Chip>
                  )}
                  {a.is_retired && (
                    <Chip size="sm" variant="soft">
                      {t("retired")}
                    </Chip>
                  )}
                </span>
              </td>
              <td className="px-3 py-2">{ta(a.asset_type)}</td>
              <td className="px-3 py-2">{a.area_name_ar ?? "—"}</td>
              <td className="px-3 py-2">
                <Chip size="sm" variant="soft" color={statusColor(a.current_status)}>
                  {ts(a.current_status)}
                </Chip>
              </td>
              <td className="px-3 py-2 font-mono text-xs" dir="ltr">
                {a.longitude === null || a.latitude === null ? (
                  <span className="text-muted" title={t("noCoordinates")}>
                    —
                  </span>
                ) : (
                  `${a.longitude.toFixed(5)}, ${a.latitude.toFixed(5)}`
                )}
              </td>
              <td className="px-3 py-2 font-mono text-xs tabular-nums">
                {formatNumber(a.point_count, locale)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function statusColor(status: string): "success" | "warning" | "danger" | "default" {
  if (status === "OPERATING") return "success";
  if (status === "PARTIALLY_OPERATING" || status === "MAINTENANCE") return "warning";
  if (status === "STOPPED" || status === "DAMAGED") return "danger";
  return "default";
}
