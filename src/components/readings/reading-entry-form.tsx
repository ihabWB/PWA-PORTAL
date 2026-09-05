"use client";

import {
  Alert,
  Button,
  Description,
  FieldError,
  Form,
  Input,
  Label,
  NumberField,
  ListBox,
  Select,
  TextArea,
  TextField,
} from "@heroui/react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useTranslations } from "next-intl";
import { useActionState, useEffect, useMemo, useTransition } from "react";
import { Controller, useForm, useWatch, type DefaultValues } from "react-hook-form";

import { submitReadingAction, type ReadingFormState } from "@/app/(app)/field-entry/actions";
import type { OperationalStatus } from "@/types/database";
import {
  entryBasisValues,
  operationalStatusValues,
  readingEntrySchema,
  type ReadingEntryInput,
} from "@/validation/reading";

type ReadingEntryFormProps = {
  pointId: string;
  defaultDate: string;
  maxDate: string;
  /** Set when a reading already covers the day; submitting then supersedes it. */
  supersedesId: string | null;
  defaultStatus: OperationalStatus;
};

/**
 * One point = one screen. Validation runs through the shared Zod schema here for immediate
 * feedback; the Server Action runs the same schema again before touching the database.
 *
 * The reading id is generated on the CLIENT and lives in form state: the write path never
 * depends on a server-assigned sequential id, so offline entry stays possible later, and a
 * retry after a failed submit reuses the same id and is therefore idempotent. A new id is
 * minted only after a successful save.
 */
export function ReadingEntryForm({
  pointId,
  defaultDate,
  maxDate,
  supersedesId,
  defaultStatus,
}: ReadingEntryFormProps) {
  const t = useTranslations("entry");
  const tc = useTranslations("common");
  const tr = useTranslations();
  const tb = useTranslations("entryBasis");
  const ts = useTranslations("status");

  const [state, formAction] = useActionState<ReadingFormState, FormData>(submitReadingAction, {
    status: "idle",
  });
  const [pending, startTransition] = useTransition();

  const defaults = useMemo<DefaultValues<ReadingEntryInput>>(
    () => ({
      measurementPointId: pointId,
      coversFrom: defaultDate,
      coversTo: defaultDate,
      entryBasis: "METER_DISPLAY",
      operationalStatus: defaultStatus,
      cumulativeIndex: null,
      pumpHours: null,
      notes: null,
    }),
    [pointId, defaultDate, defaultStatus],
  );

  const { control, handleSubmit, reset } = useForm<ReadingEntryInput>({
    resolver: zodResolver(readingEntrySchema),
    defaultValues: { ...defaults, id: crypto.randomUUID() },
    mode: "onBlur",
  });

  useEffect(() => {
    // A new id only after a successful save; a retry after failure reuses the same id.
    if (state.status === "saved") reset({ ...defaults, id: crypto.randomUUID() });
  }, [state.status, reset, defaults]);

  const basis = useWatch({ control, name: "entryBasis" });

  const onValid = (values: ReadingEntryInput) => {
    const fd = new FormData();
    fd.set("id", values.id);
    fd.set("measurementPointId", pointId);
    fd.set("coversFrom", values.coversFrom);
    fd.set("coversTo", values.coversTo);
    fd.set("volumeM3", String(values.volumeM3));
    fd.set("entryBasis", values.entryBasis);
    fd.set("operationalStatus", values.operationalStatus);
    if (values.cumulativeIndex != null) fd.set("cumulativeIndex", String(values.cumulativeIndex));
    if (values.pumpHours != null) fd.set("pumpHours", String(values.pumpHours));
    if (values.notes) fd.set("notes", values.notes);
    if (supersedesId) fd.set("supersedesId", supersedesId);
    startTransition(() => formAction(fd));
  };

  return (
    <Form
      onSubmit={handleSubmit(onValid)}
      className="flex flex-col gap-4"
      validationBehavior="aria"
    >
      {supersedesId && (
        <Alert status="accent">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{t("correcting")}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}

      {state.status === "saved" && (
        <Alert status={state.flagged ? "warning" : "success"}>
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>{t("savedTitle")}</Alert.Title>
            {state.flagged && <Alert.Description>{t("savedFlagged")}</Alert.Description>}
          </Alert.Content>
        </Alert>
      )}

      {state.status === "error" && state.messageKey && (
        <Alert status="danger">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{tr(state.messageKey)}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}

      {/* The covered day is editable so a late entry lands on the right day. */}
      <div className="grid grid-cols-2 gap-3">
        <Controller
          control={control}
          name="coversFrom"
          render={({ field, fieldState }) => (
            <TextField
              name={field.name}
              value={field.value ?? ""}
              onChange={field.onChange}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              type="date"
              isRequired
            >
              <Label>{t("coveredDayLabel")}</Label>
              <Input max={maxDate} />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />
        <Controller
          control={control}
          name="coversTo"
          render={({ field, fieldState }) => (
            <TextField
              name={field.name}
              value={field.value ?? ""}
              onChange={field.onChange}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              type="date"
              isRequired
            >
              <Label>{tc("of")}</Label>
              <Input max={maxDate} />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />
      </div>

      <Controller
        control={control}
        name="volumeM3"
        render={({ field, fieldState }) => (
          <NumberField
            name={field.name}
            value={field.value ?? Number.NaN}
            onChange={field.onChange}
            onBlur={field.onBlur}
            isInvalid={fieldState.invalid}
            minValue={0}
            step={1}
            formatOptions={{ maximumFractionDigits: 0, useGrouping: true }}
            isRequired
          >
            <Label>{t("volume")}</Label>
            <Input inputMode="numeric" className="text-2xl" />
            <Description>{t("volumeHelp")}</Description>
            {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
          </NumberField>
        )}
      />

      <Controller
        control={control}
        name="operationalStatus"
        render={({ field, fieldState }) => (
          <Select
            name={field.name}
            selectedKey={field.value ?? null}
            onSelectionChange={(k) => field.onChange(k)}
            isInvalid={fieldState.invalid}
            isRequired
          >
            <Label>{t("status")}</Label>
            <Select.Trigger />
            <Select.Popover>
              <ListBox>
                {operationalStatusValues.map((s) => (
                  <ListBox.Item key={s} id={s}>
                    {ts(s)}
                  </ListBox.Item>
                ))}
              </ListBox>
            </Select.Popover>
            {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
          </Select>
        )}
      />

      <Controller
        control={control}
        name="entryBasis"
        render={({ field, fieldState }) => (
          <Select
            name={field.name}
            selectedKey={field.value ?? null}
            onSelectionChange={(k) => field.onChange(k)}
            isInvalid={fieldState.invalid}
            isRequired
          >
            <Label>{tb("label")}</Label>
            <Select.Trigger />
            <Select.Popover>
              <ListBox>
                {entryBasisValues.map((b) => (
                  <ListBox.Item key={b} id={b}>
                    {tb(b)}
                  </ListBox.Item>
                ))}
              </ListBox>
            </Select.Popover>
            {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
          </Select>
        )}
      />

      {basis === "PUMP_HOURS" && (
        <Controller
          control={control}
          name="pumpHours"
          render={({ field, fieldState }) => (
            <NumberField
              name={field.name}
              value={field.value ?? Number.NaN}
              onChange={(v) => field.onChange(Number.isNaN(v) ? null : v)}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              minValue={0}
              step={0.5}
            >
              <Label>{t("pumpHours")}</Label>
              <Input inputMode="decimal" />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </NumberField>
          )}
        />
      )}

      <Controller
        control={control}
        name="cumulativeIndex"
        render={({ field, fieldState }) => (
          <NumberField
            name={field.name}
            value={field.value ?? Number.NaN}
            onChange={(v) => field.onChange(Number.isNaN(v) ? null : v)}
            onBlur={field.onBlur}
            isInvalid={fieldState.invalid}
            minValue={0}
            formatOptions={{ maximumFractionDigits: 0, useGrouping: false }}
          >
            <Label>{`${t("cumulativeIndex")} (${tc("optional")})`}</Label>
            <Input inputMode="numeric" />
            <Description>{t("cumulativeIndexHelp")}</Description>
            {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
          </NumberField>
        )}
      />

      <Controller
        control={control}
        name="notes"
        render={({ field }) => (
          <TextField
            name={field.name}
            value={field.value ?? ""}
            onChange={field.onChange}
            onBlur={field.onBlur}
          >
            <Label>{`${t("notes")} (${tc("optional")})`}</Label>
            <TextArea rows={2} />
          </TextField>
        )}
      />

      <Button type="submit" variant="primary" size="lg" isPending={pending} fullWidth>
        {pending ? tc("saving") : supersedesId ? t("correct") : t("submit")}
      </Button>
    </Form>
  );
}
