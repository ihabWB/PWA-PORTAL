import { AppShell } from "@/components/layout/app-shell";
import { requireUser } from "@/lib/auth/require-user";

/** Protected application shell. The single auth gate for every operational screen. */
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  const displayName =
    (user.user_metadata?.full_name_ar as string | undefined) ??
    (user.user_metadata?.full_name as string | undefined) ??
    user.email ??
    "";

  return <AppShell userName={displayName}>{children}</AppShell>;
}
