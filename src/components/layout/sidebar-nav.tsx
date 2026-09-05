"use client";

import { Chip } from "@heroui/react";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { usePathname } from "next/navigation";

/**
 * Navigation entries. Only `/` exists in Stage 1; the rest are placeholders that map to the
 * SPEC.md build order and become real routes as each stage ships.
 */
const NAV_ITEMS: ReadonlyArray<{ key: string; href: string; ready: boolean }> = [
  { key: "home", href: "/", ready: true },
  { key: "saeer", href: "/saeer", ready: false },
  { key: "fieldEntry", href: "/field-entry", ready: false },
  { key: "readings", href: "/readings", ready: false },
  { key: "assets", href: "/assets", ready: false },
  { key: "map", href: "/map", ready: false },
  { key: "alerts", href: "/alerts", ready: false },
];

export function SidebarNav() {
  const t = useTranslations("nav");
  const pathname = usePathname();

  return (
    <nav aria-label={t("home")} className="flex flex-col gap-1 p-2">
      {NAV_ITEMS.map((item) => {
        const active = item.ready && pathname === item.href;
        const base =
          "flex items-center justify-between gap-2 rounded-(--radius) px-3 py-2 text-sm transition-colors";
        if (!item.ready) {
          return (
            <span key={item.key} className={`${base} text-muted cursor-default`} aria-disabled>
              <span>{t(item.key)}</span>
              <Chip size="sm" variant="soft">
                {t("comingSoon")}
              </Chip>
            </span>
          );
        }
        return (
          <Link
            key={item.key}
            href={item.href}
            aria-current={active ? "page" : undefined}
            className={`${base} ${
              active
                ? "bg-accent-soft text-accent-soft-foreground font-medium"
                : "hover:bg-default text-foreground"
            }`}
          >
            <span>{t(item.key)}</span>
          </Link>
        );
      })}
    </nav>
  );
}
