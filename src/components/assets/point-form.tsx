"use client";

import {
  Alert,
  Button,
  Checkbox,
  Description,
  FieldError,
  Form,
  Input,
  Label,
  ListBox,
  Select,
  TextField,
} from "@heroui/react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useTranslations } from "next-intl";
import { useActionState, useTransition } from "react";
import { Controller, useForm, type DefaultValues } from "react-hook-form";

import { savePointAction, type AssetFormState } from "@/app/(app)/assets/actions";
import { POINT_TYPES } from "@/types/database";
import { measurementPointSchema, type MeasurementPointInput } from "@/validation/asset";

type PointFormProps = {
  assetId: string;
  areaId: string | null;
  initial?: Partial<MeasurementPointInput>;
  onDoneLabelKey?: string;
};

/**
 * Add or edit a measurement point on an asset. expects_daily_reading is explicit because it
 * decides whether the point ever appears in the morning task list and in daily completeness.
 */
export function PointForm({ assetId, areaId, initial }: PointFormProps) {
  const t = useTranslations("asset");
  const tc = useTranslations("common");
  const tr = useTranslations();
  const tp = useTranslations("pointType");

  const [state, formAction] = useActionState<AssetFormState, FormData>(savePointAction, {
    status: "idle",
  });
  const [pending, startTransition] = useTransition();

  const defaults: DefaultValues<MeasurementPointInput> = {
    id: null,
    code: "",
    nameAr: "",
    nameEn: null,
    pointType: "SOURCE_METER",
    assetId,
    waterPathId: null,
    areaId,
    expectsDailyReading: true,
    isActive: true,
    excludedFromBalance: false,
    ...initial,
  };

  const { control, handleSubmit, reset } = useForm<MeasurementPointInput>({
    resolver: zodResolver(measurementPointSchema),
    defaultValues: defaults,
    mode: "onBlur",
  });

  const onValid = (values: MeasurementPointInput) => {
    const fd = new FormData();
    const set = (k: string, v: unknown) => {
      if (v !== null && v !== undefined && v !== "") fd.set(k, String(v));
    };
    set("id", values.id);
    set("code", values.code);
    set("nameAr", values.nameAr);
    set("nameEn", values.nameEn);
    set("pointType", values.pointType);
    set("assetId", values.assetId);
    set("areaId", values.areaId);
    fd.set("expectsDailyReading", String(values.expectsDailyReading));
    fd.set("isActive", String(values.isActive));
    fd.set("excludedFromBalance", String(values.excludedFromBalance));
    startTransition(() => {
      formAction(fd);
      if (!values.id) reset(defaults);
    });
  };

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
            <Alert.Description>{t("pointSaved")}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}

      <div className="grid gap-3 sm:grid-cols-2">
        <Controller
          control={control}
          name="code"
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
              <Label>{t("code")}</Label>
              <Input />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />
        <Controller
          control={control}
          name="pointType"
          render={({ field, fieldState }) => (
            <Select
              name={field.name}
              selectedKey={field.value ?? null}
              onSelectionChange={(k) => field.onChange(k)}
              isInvalid={fieldState.invalid}
              isRequired
            >
              <Label>{t("pointTypeLabel")}</Label>
              <Select.Trigger />
              <Select.Popover>
                <ListBox>
                  {POINT_TYPES.map((v) => (
                    <ListBox.Item key={v} id={v}>
                      {tp(v)}
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
          name="nameAr"
          render={({ field, fieldState }) => (
            <TextField
              name={field.name}
              value={field.value ?? ""}
              onChange={field.onChange}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              isRequired
            >
              <Label>{t("nameAr")}</Label>
              <Input />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />
        <Controller
          control={control}
          name="nameEn"
          render={({ field }) => (
            <TextField
              name={field.name}
              value={field.value ?? ""}
              onChange={(v) => field.onChange(v === "" ? null : v)}
              onBlur={field.onBlur}
              dir="ltr"
            >
              <Label>{`${t("nameEn")} (${tc("optional")})`}</Label>
              <Input />
            </TextField>
          )}
        />
      </div>

      <Controller
        control={control}
        name="expectsDailyReading"
        render={({ field }) => (
          <div className="flex flex-col gap-1">
            <Checkbox isSelected={field.value ?? true} onChange={field.onChange}>
              {t("expectsDailyReading")}
            </Checkbox>
            <Description className="text-muted text-xs">{t("expectsDailyReadingHelp")}</Description>
          </div>
        )}
      />

      <Controller
        control={control}
        name="excludedFromBalance"
        render={({ field }) => (
          <div className="flex flex-col gap-1">
            <Checkbox isSelected={field.value ?? false} onChange={field.onChange}>
              {t("excludedFromBalance")}
            </Checkbox>
            <Description className="text-muted text-xs">{t("excludedFromBalanceHelp")}</Description>
          </div>
        )}
      />

      <Controller
        control={control}
        name="isActive"
        render={({ field }) => (
          <Checkbox isSelected={field.value ?? true} onChange={field.onChange}>
            {t("pointIsActive")}
          </Checkbox>
        )}
      />

      <Button type="submit" variant="primary" isPending={pending}>
        {pending ? tc("saving") : tc("save")}
      </Button>
    </Form>
  );
}
