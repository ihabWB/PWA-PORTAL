import { Alert, Button, Card } from "@heroui/react";
import { getTranslations } from "next-intl/server";

import { signOutAction } from "@/app/(auth)/login/actions";

type PendingActivationProps = { email: string };

/**
 * Shown to a signed-in user whose profile is missing or not yet activated by an administrator.
 * RLS would otherwise return empty result sets everywhere, which reads as a broken app.
 */
export async function PendingActivation({ email }: PendingActivationProps) {
  const t = await getTranslations();

  return (
    <main className="flex min-h-dvh items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <Card.Header>
          <Card.Title>{t("auth.pending.title")}</Card.Title>
          <Card.Description>{t("auth.pending.subtitle", { email })}</Card.Description>
        </Card.Header>
        <Card.Content className="flex flex-col gap-4">
          <Alert status="warning">
            <Alert.Indicator />
            <Alert.Content>
              <Alert.Description>{t("auth.pending.body")}</Alert.Description>
            </Alert.Content>
          </Alert>
          <form action={signOutAction}>
            <Button type="submit" variant="secondary" fullWidth>
              {t("common.signOut")}
            </Button>
          </form>
        </Card.Content>
      </Card>
    </main>
  );
}
