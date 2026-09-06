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
  NumberField,
  Select,
  TextArea,
  TextField,
} from "@heroui/react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useTransition } from "react";
import { Controller, useForm, useWatch, type DefaultValues } from "react-hook-form";

import { saveAssetAction, type AssetFormState } from "@/app/(app)/assets/actions";
import {
  ASSET_TYPES,
  OPERATIONAL_STATUSES,
  OPTIONAL_SUPPLY_ASSET_TYPES,
  SOURCE_ASSET_TYPES,
  type AreaRow,
} from "@/types/database";
import { assetSchema, type AssetInput } from "@/validation/asset";

type AssetFormProps = {
  areas: AreaRow[];
  initial?: Partial<AssetInput>;
  /** Shown when the row being edited still carries a seeded placeholder code. */
  isPlaceholder?: boolean;
};

const SUPPLY_TYPES = ["GROUNDWATER", "ISRAELI"] as const;

/**
 * Create or edit an asset. Coordinates are optional and stay empty unless typed: an empty
 * coordinate is more honest than an invented one, and the list marks the gap explicitly.
 */
export function AssetForm({ areas, initial, isPlaceholder }: AssetFormProps) {
  const t = useTranslations("asset");
  const tc = useTranslations("common");
  const tr = useTranslations();
  const ta = useTranslations("assetType");
  const ts = useTranslations("status");
  const tsup = useTranslations("supplyType");
  const router = useRouter();

  const [state, formAction] = useActionState<AssetFormState, FormData>(saveAssetAction, {
    status: "idle",
  });
  const [pending, startTransition] = useTransition();

  const defaults: DefaultValues<AssetInput> = {
    id: null,
    code: "",
    nameAr: "",
    nameEn: null,
    assetType: "WELL",
    supplyType: "GROUNDWATER",
    areaId: areas[0]?.id ?? null,
    currentStatus: "UNKNOWN",
    longitude: null,
    latitude: null,
    capacityM3: null,
    heightM: null,
    isPassThrough: false,
    passThroughTolerancePct: null,
    operationalStartDate: null,
    externalReference: null,
    descriptionAr: null,
    descriptionEn: null,
    ...initial,
  };

  const { control, handleSubmit } = useForm<AssetInput>({
    resolver: zodResolver(assetSchema),
    defaultValues: defaults,
    mode: "onBlur",
  });

  const assetType = useWatch({ control, name: "assetType" });
  const isSource = SOURCE_ASSET_TYPES.includes(assetType);
  // A main meter may declare a supply type without being obliged to: the Saeer screen splits
  // the total between groundwater and purchased water, so its volume has to be attributable.
  const maySetSupply = isSource || OPTIONAL_SUPPLY_ASSET_TYPES.includes(assetType);
  const storesWater = assetType === "TANK" || assetType === "RESERVOIR";

  useEffect(() => {
    if (state.status === "saved" && state.savedId) router.push(`/assets/${state.savedId}`);
  }, [state.status, state.savedId, router]);

  const onValid = (values: AssetInput) => {
    const fd = new FormData();
    const set = (k: string, v: unknown) => {
      if (v !== null && v !== undefined && v !== "") fd.set(k, String(v));
    };
    set("id", values.id);
    set("code", values.code);
    set("nameAr", values.nameAr);
    set("nameEn", values.nameEn);
    set("assetType", values.assetType);
    set("supplyType", maySetSupply ? values.supplyType : null);
    set("areaId", values.areaId);
    set("currentStatus", values.currentStatus);
    set("longitude", values.longitude);
    set("latitude", values.latitude);
    set("capacityM3", storesWater ? values.capacityM3 : null);
    set("heightM", storesWater ? values.heightM : null);
    fd.set("isPassThrough", String(values.isPassThrough ?? false));
    set("passThroughTolerancePct", values.passThroughTolerancePct);
    set("operationalStartDate", values.operationalStartDate);
    set("externalReference", values.externalReference);
    set("descriptionAr", values.descriptionAr);
    set("descriptionEn", values.descriptionEn);
    startTransition(() => formAction(fd));
  };

  return (
    <Form
      onSubmit={handleSubmit(onValid)}
      className="flex flex-col gap-4"
      validationBehavior="aria"
    >
      {isPlaceholder && (
        <Alert status="warning">
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>{t("placeholderTitle")}</Alert.Title>
            <Alert.Description>{t("placeholderHint")}</Alert.Description>
          </Alert.Content>
        </Alert>
      )}

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
              <Description>{t("codeHelp")}</Description>
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />

        <Controller
          control={control}
          name="assetType"
          render={({ field, fieldState }) => (
            <Select
              name={field.name}
              selectedKey={field.value ?? null}
              onSelectionChange={(k) => field.onChange(k)}
              isInvalid={fieldState.invalid}
              isRequired
            >
              <Label>{t("assetTypeLabel")}</Label>
              <Select.Trigger />
              <Select.Popover>
                <ListBox>
                  {ASSET_TYPES.map((v) => (
                    <ListBox.Item key={v} id={v}>
                      {ta(v)}
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
          render={({ field, fieldState }) => (
            <TextField
              name={field.name}
              value={field.value ?? ""}
              onChange={(v) => field.onChange(v === "" ? null : v)}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              dir="ltr"
            >
              <Label>{`${t("nameEn")} (${tc("optional")})`}</Label>
              <Input />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />

        {maySetSupply && (
          <Controller
            control={control}
            name="supplyType"
            render={({ field, fieldState }) => (
              <Select
                name={field.name}
                selectedKey={field.value ?? null}
                onSelectionChange={(k) => field.onChange(k)}
                isInvalid={fieldState.invalid}
                isRequired={isSource}
              >
                <Label>
                  {isSource ? t("supplyTypeLabel") : `${t("supplyTypeLabel")} (${tc("optional")})`}
                </Label>
                <Select.Trigger />
                <Select.Popover>
                  <ListBox>
                    {SUPPLY_TYPES.map((v) => (
                      <ListBox.Item key={v} id={v}>
                        {tsup(v)}
                      </ListBox.Item>
                    ))}
                  </ListBox>
                </Select.Popover>
                {fieldState.error?.message && (
                  <FieldError>{tr(fieldState.error.message)}</FieldError>
                )}
              </Select>
            )}
          />
        )}

        <Controller
          control={control}
          name="areaId"
          render={({ field, fieldState }) => (
            <Select
              name={field.name}
              selectedKey={field.value ?? null}
              onSelectionChange={(k) => field.onChange(k === null ? null : String(k))}
              isInvalid={fieldState.invalid}
            >
              <Label>{t("area")}</Label>
              <Select.Trigger />
              <Select.Popover>
                <ListBox>
                  {areas.map((a) => (
                    <ListBox.Item key={a.id} id={a.id}>
                      {a.name_ar}
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
          name="currentStatus"
          render={({ field, fieldState }) => (
            <Select
              name={field.name}
              selectedKey={field.value ?? null}
              onSelectionChange={(k) => field.onChange(k)}
              isInvalid={fieldState.invalid}
              isRequired
            >
              <Label>{t("currentStatus")}</Label>
              <Select.Trigger />
              <Select.Popover>
                <ListBox>
                  {OPERATIONAL_STATUSES.map((v) => (
                    <ListBox.Item key={v} id={v}>
                      {ts(v)}
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
          name="operationalStartDate"
          render={({ field, fieldState }) => (
            <TextField
              name={field.name}
              value={field.value ?? ""}
              onChange={(v) => field.onChange(v === "" ? null : v)}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              type="date"
            >
              <Label>{`${t("operationalStartDate")} (${tc("optional")})`}</Label>
              <Input />
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />

        <Controller
          control={control}
          name="externalReference"
          render={({ field, fieldState }) => (
            <TextField
              name={field.name}
              value={field.value ?? ""}
              onChange={(v) => field.onChange(v === "" ? null : v)}
              onBlur={field.onBlur}
              isInvalid={fieldState.invalid}
              dir="ltr"
            >
              <Label>{`${t("externalReference")} (${tc("optional")})`}</Label>
              <Input />
              <Description>{t("externalReferenceHelp")}</Description>
              {fieldState.error?.message && <FieldError>{tr(fieldState.error.message)}</FieldError>}
            </TextField>
          )}
        />
      </div>

      <fieldset className="flex flex-col gap-2">
        <legend className="text-muted mb-1 text-sm">{t("coordinates")}</legend>
        <p className="text-muted text-xs">{t("coordinatesHelp")}</p>
        <div className="grid gap-3 sm:grid-cols-2">
          <Controller
            control={control}
            name="longitude"
            render={({ field, fieldState }) => (
              <NumberField
                name={field.name}
                value={field.value ?? Number.NaN}
                onChange={(v) => field.onChange(Number.isNaN(v) ? null : v)}
                onBlur={field.onBlur}
                isInvalid={fieldState.invalid}
                formatOptions={{ maximumFractionDigits: 6, useGrouping: false }}
              >
                <Label>{t("longitude")}</Label>
                <Input inputMode="decimal" dir="ltr" />
                {fieldState.error?.message && (
                  <FieldError>{tr(fieldState.error.message)}</FieldError>
                )}
              </NumberField>
            )}
          />
          <Controller
            control={control}
            name="latitude"
            render={({ field, fieldState }) => (
              <NumberField
                name={field.name}
                value={field.value ?? Number.NaN}
                onChange={(v) => field.onChange(Number.isNaN(v) ? null : v)}
                onBlur={field.onBlur}
                isInvalid={fieldState.invalid}
                formatOptions={{ maximumFractionDigits: 6, useGrouping: false }}
              >
                <Label>{t("latitude")}</Label>
                <Input inputMode="decimal" dir="ltr" />
                {fieldState.error?.message && (
                  <FieldError>{tr(fieldState.error.message)}</FieldError>
                )}
              </NumberField>
            )}
          />
        </div>
      </fieldset>

      {storesWater && (
        <fieldset className="flex flex-col gap-2">
          <legend className="text-muted mb-1 text-sm">{t("geometry")}</legend>
          <p className="text-muted text-xs">{t("geometryHelp")}</p>
          <div className="grid gap-3 sm:grid-cols-2">
            <Controller
              control={control}
              name="capacityM3"
              render={({ field, fieldState }) => (
                <NumberField
                  name={field.name}
                  value={field.value ?? Number.NaN}
                  onChange={(v) => field.onChange(Number.isNaN(v) ? null : v)}
                  onBlur={field.onBlur}
                  isInvalid={fieldState.invalid}
                  minValue={0}
                >
                  <Label>{t("capacityM3")}</Label>
                  <Input inputMode="numeric" />
                  {fieldState.error?.message && (
                    <FieldError>{tr(fieldState.error.message)}</FieldError>
                  )}
                </NumberField>
              )}
            />
            <Controller
              control={control}
              name="heightM"
              render={({ field, fieldState }) => (
                <NumberField
                  name={field.name}
                  value={field.value ?? Number.NaN}
                  onChange={(v) => field.onChange(Number.isNaN(v) ? null : v)}
                  onBlur={field.onBlur}
                  isInvalid={fieldState.invalid}
                  minValue={0}
                  formatOptions={{ maximumFractionDigits: 2 }}
                >
                  <Label>{t("heightM")}</Label>
                  <Input inputMode="decimal" />
                  {fieldState.error?.message && (
                    <FieldError>{tr(fieldState.error.message)}</FieldError>
                  )}
                </NumberField>
              )}
            />
          </div>

          <Controller
            control={control}
            name="isPassThrough"
            render={({ field }) => (
              <Checkbox isSelected={field.value ?? false} onChange={field.onChange}>
                {t("isPassThrough")}
              </Checkbox>
            )}
          />
          <p className="text-muted text-xs">{t("isPassThroughHelp")}</p>
        </fieldset>
      )}

      <Controller
        control={control}
        name="descriptionAr"
        render={({ field }) => (
          <TextField
            name={field.name}
            value={field.value ?? ""}
            onChange={(v) => field.onChange(v === "" ? null : v)}
            onBlur={field.onBlur}
          >
            <Label>{`${t("descriptionAr")} (${tc("optional")})`}</Label>
            <TextArea rows={2} />
          </TextField>
        )}
      />

      <Button type="submit" variant="primary" isPending={pending}>
        {pending ? tc("saving") : tc("save")}
      </Button>
    </Form>
  );
}
