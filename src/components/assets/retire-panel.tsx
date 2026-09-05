"use client";

import {
  Alert,
  Button,
  Description,
  FieldError,
  Form,
  Input,
  Label,
  ListBox,
  Select,
  TextField,
} from "@heroui/react";
import { useTranslations } from "next-intl";
import { useActionState, useState, useTransition } from "react";

import {
  reinstateAssetAction,
  retireAssetAction,
  type AssetFormState,
} from "@/app/(app)/assets/actions";

type RetirePanelProps = {
  assetId: string;
  isRetired: boolean;
  endDate: string | null;
  today: string;
  readingCount: number;
};

const RETIRE_STATUSES = ["STOPPED", "DAMAGED", "MAINTENANCE", "UNKNOWN"] as const;

/**
 * Retiring, not deleting. The row and every reading attached to it stay; the asset simply
 * leaves service on a date. Reinstating clears the end date.
 */
export function RetirePanel({
  assetId,
  isRetired,
  endDate,
  today,
  readingCount,
}: RetirePanelProps) {
  const t = useTranslations("asset");
  const tc = useTranslations("common");
  const tr = useTranslations();
  const ts = useTranslations("status");

  const [retireState, retireAction] = useActionState<AssetFormState, FormData>(retireAssetAction, {
    status: "idle",
  });
  const [reinstateState, reinstateAction] = useActionState<AssetFormState, FormData>(
    reinstateAssetAction,
    { status: "idle" },
  );
  const [pending, startTransition] = useTransition();
  const [date, setDate] = useState(today);
  const [status, setStatus] = useState<string>("STOPPED");

  const state = retireState.status !== "idle" ? retireState : reinstateState;

  return (
    <div className="flex flex-col gap-3">
      <p className="text-muted text-sm">{t("retireExplainer", { count: readingCount })}</p>

      {state.status === "error" && state.messageKey && (
        <Alert status="danger">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{tr(state.messageKey)}</Alert.Description>
            {state.detail && (
              <p className="text-muted mt-1 font-mono text-xs break-all">{state.detail}</p>
            )}
          </Alert.Content>
        </Alert>
      )}

      {isRetired ? (
        <>
          <Alert status="warning">
            <Alert.Indicator />
            <Alert.Content>
              <Alert.Description>{t("retiredOn", { date: endDate ?? "" })}</Alert.Description>
            </Alert.Content>
          </Alert>
          <Form
            onSubmit={(e) => {
              e.preventDefault();
              const fd = new FormData();
              fd.set("id", assetId);
              startTransition(() => reinstateAction(fd));
            }}
          >
            <Button type="submit" variant="secondary" isPending={pending}>
              {t("reinstate")}
            </Button>
          </Form>
        </>
      ) : (
        <Form
          onSubmit={(e) => {
            e.preventDefault();
            const fd = new FormData();
            fd.set("id", assetId);
            fd.set("endDate", date);
            fd.set("status", status);
            startTransition(() => retireAction(fd));
          }}
          className="flex flex-col gap-3"
        >
          <div className="grid gap-3 sm:grid-cols-2">
            <TextField value={date} onChange={setDate} type="date" isRequired>
              <Label>{t("retireDate")}</Label>
              <Input />
              <Description>{t("retireDateHelp")}</Description>
              <FieldError />
            </TextField>

            <Select selectedKey={status} onSelectionChange={(k) => setStatus(String(k))} isRequired>
              <Label>{t("retireStatus")}</Label>
              <Select.Trigger />
              <Select.Popover>
                <ListBox>
                  {RETIRE_STATUSES.map((s) => (
                    <ListBox.Item key={s} id={s}>
                      {ts(s)}
                    </ListBox.Item>
                  ))}
                </ListBox>
              </Select.Popover>
            </Select>
          </div>

          <Button type="submit" variant="danger" isPending={pending}>
            {pending ? tc("saving") : t("retire")}
          </Button>
        </Form>
      )}
    </div>
  );
}
