import { PendingActivation } from "@/components/auth/pending-activation";
import { AppShell } from "@/components/layout/app-shell";
import { displayName, getOwnProfile } from "@/lib/auth/profile";
import { requireUser } from "@/lib/auth/require-user";

/**
 * Protected application shell. The single auth gate for every operational screen.
 * An authenticated user without an active profile sees an explicit "awaiting activation"
 * message instead of empty RLS-filtered screens.
 */
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  const profile = await getOwnProfile(user);

  if (!profile?.is_active) {
    return <PendingActivation email={user.email ?? ""} />;
  }

  return <AppShell userName={displayName(user, profile)}>{children}</AppShell>;
}
