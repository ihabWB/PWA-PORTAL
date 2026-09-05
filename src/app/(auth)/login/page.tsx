import { getTranslations } from "next-intl/server";

import { LoginForm } from "@/components/auth/login-form";
import { hasSupabaseEnv } from "@/lib/env";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const t = await getTranslations();
  const { next } = await searchParams;

  return (
    <main className="flex min-h-dvh items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <header className="mb-6 text-center">
          <h1 className="text-xl font-semibold">{t("app.name")}</h1>
          <p className="text-muted mt-1 text-sm">{t("app.tagline")}</p>
        </header>
        <LoginForm configured={hasSupabaseEnv()} next={next} />
      </div>
    </main>
  );
}
