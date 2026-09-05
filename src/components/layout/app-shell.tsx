import { getTranslations } from "next-intl/server";

import { SidebarNav } from "./sidebar-nav";
import { TopBar } from "./top-bar";

type AppShellProps = {
  userName: string;
  children: React.ReactNode;
};

/**
 * RTL-first application frame: sidebar on the inline-start edge, top bar, scrollable content.
 * Layout uses logical properties only so the same code flips correctly for English.
 */
export async function AppShell({ userName, children }: AppShellProps) {
  const t = await getTranslations("app");

  return (
    <div className="flex min-h-dvh">
      <aside className="bg-surface border-border hidden w-(--sidebar-width) shrink-0 flex-col border-e md:flex">
        <div className="border-border flex h-(--topbar-height) items-center border-b px-4">
          <span className="text-accent font-semibold">{t("shortName")}</span>
        </div>
        <SidebarNav />
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <TopBar userName={userName} />
        <main className="flex-1 p-4 md:p-6">{children}</main>
      </div>
    </div>
  );
}
