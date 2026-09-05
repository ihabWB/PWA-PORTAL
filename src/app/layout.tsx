import type { Metadata } from "next";
import { IBM_Plex_Sans_Arabic } from "next/font/google";
import { NextIntlClientProvider } from "next-intl";
import { getLocale, getTranslations } from "next-intl/server";

import { Providers } from "@/components/providers";
import { intlLocaleTag, isLocale, localeDirection, defaultLocale } from "@/i18n/config";

import "./globals.css";

const plexArabic = IBM_Plex_Sans_Arabic({
  subsets: ["arabic", "latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-plex-arabic",
  display: "swap",
});

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("app");
  return {
    title: {
      default: t("name"),
      template: `%s · ${t("shortName")}`,
    },
    description: t("tagline"),
  };
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const raw = await getLocale();
  const locale = isLocale(raw) ? raw : defaultLocale;
  const dir = localeDirection[locale];

  return (
    <html lang={locale} dir={dir} className={plexArabic.variable} suppressHydrationWarning>
      <body className="antialiased">
        <NextIntlClientProvider>
          <Providers locale={intlLocaleTag[locale]}>{children}</Providers>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
