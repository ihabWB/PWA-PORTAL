import { getTranslations } from "next-intl/server";

import { Button } from "@heroui/react";

import { signOutAction } from "@/app/(auth)/login/actions";

import { LocaleSwitcher } from "./locale-switcher";

type TopBarProps = { userName: string };

export async function TopBar({ userName }: TopBarProps) {
  const t = await getTranslations("common");

  return (
    <header className="bg-surface border-border flex h-(--topbar-height) items-center justify-between gap-3 border-b px-4">
      <div className="text-muted truncate text-sm">{userName}</div>
      <div className="flex items-center gap-2">
        <LocaleSwitcher />
        <form action={signOutAction}>
          <Button type="submit" variant="ghost" size="sm">
            {t("signOut")}
          </Button>
        </form>
      </div>
    </header>
  );
}
