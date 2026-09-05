"use server";

import { redirect } from "next/navigation";

import { hasSupabaseEnv } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";
import { signInSchema } from "@/validation/auth";

export type SignInState = {
  /** i18n key of the error to display, if any. */
  errorKey?: string;
};

/**
 * Server Action: validates with the shared Zod schema (never trust the client) and signs in.
 * On success redirects to `next` (safe relative path only).
 */
export async function signInAction(_prev: SignInState, formData: FormData): Promise<SignInState> {
  if (!hasSupabaseEnv()) {
    return { errorKey: "auth.errors.notConfigured" };
  }

  const parsed = signInSchema.safeParse({
    email: formData.get("email"),
    password: formData.get("password"),
  });
  if (!parsed.success) {
    return { errorKey: parsed.error.issues[0]?.message ?? "auth.errors.generic" };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) {
    const invalid = error.code === "invalid_credentials" || error.status === 400;
    return { errorKey: invalid ? "auth.errors.invalidCredentials" : "auth.errors.generic" };
  }

  const next = formData.get("next");
  const target =
    typeof next === "string" && next.startsWith("/") && !next.startsWith("//") ? next : "/";
  redirect(target);
}

export async function signOutAction(): Promise<void> {
  if (hasSupabaseEnv()) {
    const supabase = await createClient();
    await supabase.auth.signOut();
  }
  redirect("/login");
}
