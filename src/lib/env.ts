import { z } from "zod";

/**
 * Environment variables validated lazily (on first access), so the application can be
 * built and type-checked before the Supabase project keys exist.
 * NEXT_PUBLIC_* values are inlined by Next.js, so they must be referenced explicitly
 * (not via a dynamic key) for the browser bundle to see them.
 */

/** IANA timezone for rendering and daily boundaries. Safe to read without Supabase keys. */
export const APP_TIMEZONE: string = process.env.NEXT_PUBLIC_APP_TIMEZONE || "Asia/Hebron";

const supabaseSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.url({ message: "NEXT_PUBLIC_SUPABASE_URL must be a valid URL" }),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z
    .string()
    .min(1, "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is required"),
});

export type SupabaseEnv = z.infer<typeof supabaseSchema>;

let cached: SupabaseEnv | null = null;

export function getSupabaseEnv(): SupabaseEnv {
  if (cached) return cached;
  const parsed = supabaseSchema.safeParse({
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  });
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  - ${i.path.join(".")}: ${i.message}`)
      .join("\n");
    throw new Error(
      `Invalid Supabase environment configuration. Copy .env.example to .env.local and fill it in:\n${issues}`,
    );
  }
  cached = parsed.data;
  return cached;
}

/** True when Supabase keys are configured. Used to show a setup notice instead of crashing. */
export function hasSupabaseEnv(): boolean {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );
}
