"use client";

import { Alert, Button, Card, Form, Input, Label, TextField, FieldError } from "@heroui/react";
import { zodResolver } from "@hookform/resolvers/zod";
import { useTranslations } from "next-intl";
import { useActionState, useTransition } from "react";
import { Controller, useForm } from "react-hook-form";

import { signInAction, type SignInState } from "@/app/(auth)/login/actions";
import { signInSchema, type SignInInput } from "@/validation/auth";

type LoginFormProps = {
  configured: boolean;
  next?: string;
};

/**
 * Sign-in form. Client-side validation via the shared Zod schema (for fast feedback);
 * the Server Action re-validates with the same schema before touching Supabase.
 */
export function LoginForm({ configured, next }: LoginFormProps) {
  const t = useTranslations();
  const [state, formAction] = useActionState<SignInState, FormData>(signInAction, {});
  const [pending, startTransition] = useTransition();

  const { control, handleSubmit } = useForm<SignInInput>({
    resolver: zodResolver(signInSchema),
    defaultValues: { email: "", password: "" },
    mode: "onBlur",
  });

  const onValid = (values: SignInInput) => {
    const fd = new FormData();
    fd.set("email", values.email);
    fd.set("password", values.password);
    if (next) fd.set("next", next);
    startTransition(() => formAction(fd));
  };

  return (
    <Card>
      <Card.Header>
        <Card.Title>{t("auth.signInTitle")}</Card.Title>
        <Card.Description>{t("auth.signInSubtitle")}</Card.Description>
      </Card.Header>
      <Card.Content>
        {!configured && (
          <Alert status="warning" className="mb-4">
            <Alert.Indicator />
            <Alert.Content>
              <Alert.Title>{t("setup.title")}</Alert.Title>
              <Alert.Description>{t("setup.body")}</Alert.Description>
            </Alert.Content>
          </Alert>
        )}
        {state.errorKey && (
          <Alert status="danger" className="mb-4">
            <Alert.Indicator />
            <Alert.Content>
              <Alert.Description>{t(state.errorKey)}</Alert.Description>
            </Alert.Content>
          </Alert>
        )}

        <Form
          onSubmit={handleSubmit(onValid)}
          className="flex flex-col gap-4"
          validationBehavior="aria"
        >
          <Controller
            control={control}
            name="email"
            render={({ field, fieldState }) => (
              <TextField
                name={field.name}
                value={field.value}
                onChange={field.onChange}
                onBlur={field.onBlur}
                isInvalid={fieldState.invalid}
                isRequired
                type="email"
                autoComplete="email"
                inputMode="email"
                dir="ltr"
              >
                <Label>{t("auth.email")}</Label>
                <Input />
                {fieldState.error?.message && (
                  <FieldError>{t(fieldState.error.message)}</FieldError>
                )}
              </TextField>
            )}
          />
          <Controller
            control={control}
            name="password"
            render={({ field, fieldState }) => (
              <TextField
                name={field.name}
                value={field.value}
                onChange={field.onChange}
                onBlur={field.onBlur}
                isInvalid={fieldState.invalid}
                isRequired
                type="password"
                autoComplete="current-password"
                dir="ltr"
              >
                <Label>{t("auth.password")}</Label>
                <Input />
                {fieldState.error?.message && (
                  <FieldError>{t(fieldState.error.message)}</FieldError>
                )}
              </TextField>
            )}
          />
          <Button
            type="submit"
            variant="primary"
            isPending={pending}
            isDisabled={!configured}
            fullWidth
          >
            {pending ? t("auth.signingIn") : t("auth.signIn")}
          </Button>
        </Form>
      </Card.Content>
    </Card>
  );
}
