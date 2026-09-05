import type { User } from "@supabase/supabase-js";

import { createClient } from "@/lib/supabase/server";
import type { ProfileRow } from "@/types/database";

export type OwnProfile = Pick<
  ProfileRow,
  "id" | "full_name_ar" | "full_name_en" | "role" | "is_active"
>;

/**
 * The signed-in user's own profile row. RLS always allows a user to read their own row,
 * even when inactive, so the UI can explain the account state instead of failing.
 * Returns null when the row does not exist yet (auth trigger not run) — treated as inactive.
 */
export async function getOwnProfile(user: User): Promise<OwnProfile | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name_ar, full_name_en, role, is_active")
    .eq("id", user.id)
    .maybeSingle();

  if (error) {
    // A missing table before Stage 2 is applied, or any other read error, must not crash the shell.
    return null;
  }
  return data;
}

export function displayName(user: User, profile: OwnProfile | null): string {
  if (profile?.full_name_ar) return profile.full_name_ar;
  return (user.user_metadata?.full_name as string | undefined) ?? user.email ?? "";
}
