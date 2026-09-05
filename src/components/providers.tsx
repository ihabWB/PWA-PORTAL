"use client";

import { ToastProvider } from "@heroui/react";
import { useRouter } from "next/navigation";
import { I18nProvider, RouterProvider } from "react-aria-components";

type ProvidersProps = {
  /** BCP-47 tag (with `nu-latn` / `ca-gregory` extensions) driving React Aria direction and formats. */
  locale: string;
  children: React.ReactNode;
};

/**
 * Client-side providers. HeroUI v3 needs no wrapper of its own; React Aria's I18nProvider
 * gives every component the locale/direction, and RouterProvider makes HeroUI links use
 * Next.js client navigation.
 */
export function Providers({ locale, children }: ProvidersProps) {
  const router = useRouter();

  return (
    <I18nProvider locale={locale}>
      <RouterProvider navigate={(href) => router.push(href)}>
        {children}
        <ToastProvider />
      </RouterProvider>
    </I18nProvider>
  );
}
