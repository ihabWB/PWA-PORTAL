import { Alert } from "@heroui/react";
import { getTranslations } from "next-intl/server";

type DataErrorProps = {
  errorKey: string;
  detail?: string;
};

/**
 * A failed query, shown as a failure. Never as an empty screen: an operator must be able to
 * tell "nothing was reported" from "the system could not ask".
 */
export async function DataError({ errorKey, detail }: DataErrorProps) {
  const t = await getTranslations();

  return (
    <Alert status="danger">
      <Alert.Indicator />
      <Alert.Content>
        <Alert.Title>{t("errors.title")}</Alert.Title>
        <Alert.Description>{t(errorKey)}</Alert.Description>
        {detail && <p className="text-muted mt-1 font-mono text-xs break-all">{detail}</p>}
      </Alert.Content>
    </Alert>
  );
}
