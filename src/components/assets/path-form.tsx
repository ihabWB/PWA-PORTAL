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
  NumberField,
  Select,
  TextField,
} from "@heroui/react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useTranslations } from "next-intl";
import { useActionState, useTransition } from "react";
import { Controller, useForm, type DefaultValues } from "react-hook-form";

import { savePathAction, type AssetFormState } from "@/app/(app)/assets/actions";
import { waterPathSchema, type WaterPathInput } from "@/validation/asset";

type PathFormProps = {
  fromAssetId: string;
  /** Every other asset, so topology can be drawn without touching code. */
  candidates: { id: string; code: string; nameAr: string }[];
  today: string;
};

/**
 * Water path editor. Topology is data: connecting a new well to the transmission main is
 * an entry here, never a code change.
 */
export function PathForm({ fromAssetId, candidates, today }: PathFormProps) {
  const t = useTranslations("asset");
  const tc = useTranslations("common");
  const tr = useTranslations();

  const [state, formAction] = useActionState<AssetFormState, FormData>(savePathAction, {
    status: "idle",
  });
  const [pending, startTransition] = useTransition();

  const defaults: DefaultValues<WaterPathInput> = {
    id: null,
    fromAssetId,
    toAssetId: candidates[0]?.id,
    connectionType: "PIPELINE",
    sequenceOrder: null,
    nameAr: null,
    nameEn: null,
    activeFrom: today,
    activeTo: null,
    notes: null,
  };

  const { control, handleSubmit, reset } = useForm<WaterPathInput>({
    resolver: zodResolver(waterPathSchema),
    defaultValues: defaults,
    mode: "onBlur",
  });

  const onValid = (values: WaterPathInput) => {
    const fd = new FormData();
    const set = (k: string, v: unknown) => {
      if (v !== null && v !== undefined && v !== "") fd.set(k, String(v));
    };
    set("fromAssetId", values.fromAssetId);
    set("toAssetId", values.toAssetId);
    set("connectionType", values.connectionType);
    set("sequenceOrder", values.sequenceOrder);
    set("nameAr", values.nameAr);
    set("activeFrom", values.activeFrom);
    set("activeTo", values.activeTo);
    set("notes", values.notes);
    startTransition(() => {
      formAction(fd);
      reset(defaults);
    });
  };

  if (candidates.length === 0) {
    return <p className="text-muted text-sm">{t("pathNoCandidates")}</p>;
  }

  return (
    <Form
      onSubmit={handleSubmit(onValid)}
      className="flex flex-col gap-3"
      validationBehavior="aria"
    >
      {state.status === "error" && state.messageKey && (
        <Alert status="danger">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{tr(state.messageKey)}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}
      {state.status === "saved" && (
        <Alert status="success">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Description>{t("pathSaved")}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}

      <div className="grid gap-3 sm:grid-cols-2">
        <Controller
          control={control}
          name="toAssetId"
          render={({ field, fieldState }) => (
            <Select
              name={field.name}
              selectedKey={field.value ?? null}
              onSelectionChange={(k) => field.onChange(k === null ? null : String(k))}
              isInvalid={fieldState.invalid}
              isRequired
            >
              <Label>{t("pathTo")}</Label>
              <Select.Trigger />
              <Select.Popover>
                <ListBox>
                  {candidates.map((c) => (
                    <ListBox.Item key={c.id} id={c.id}>
                      {`${c.nameAr} · ${c.code}`}
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
          name="connectionType"
          render={({ field, fieldState }) => (
            <TextField
              name={field.name}
              value={field.value ?? ""}
              onChange={field.onChange}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              isRequired
              dir="ltr"
            >
              <Label>{t("connectionType")}</Label>
              <Input />
              <Description>{t("connectionTypeHelp")}</Description>
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />

        <Controller
          control={control}
          name="activeFrom"
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
              <Label>{t("pathActiveFrom")}</Label>
              <Input />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />

        <Controller
          control={control}
          name="sequenceOrder"
          render={({ field, fieldState }) => (
            <NumberField
              name={field.name}
              value={field.value ?? Number.NaN}
              onChange={(v) => field.onChange(Number.isNaN(v) ? null : v)}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              minValue={0}
            >
              <Label>{`${t("sequenceOrder")} (${tc("optional")})`}</Label>
              <Input inputMode="numeric" />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </NumberField>
          )}
        />
      </div>

      <Button type="submit" variant="secondary" isPending={pending}>
        {pending ? tc("saving") : t("addPath")}
      </Button>
    </Form>
  );
}
