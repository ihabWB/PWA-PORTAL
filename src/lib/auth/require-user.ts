import { redirect } from "next/navigation";
import type { User } from "@supabase/supabase-js";

import { createClient } from "@/lib/supabase/server";

/**
 * Single server-side auth gate. Call once in the protected layout, never per page.
 * Middleware already redirects anonymous requests; this is the defence-in-depth check.
 * Role checks arrive in Stage 2 with the `profiles` table (role read from the JWT).
 */
export async function requireUser(): Promise<User> {
  const supabase = await createClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    redirect("/login");
  }
  return user;
}
