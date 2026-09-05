import { z } from "zod";

/**
 * Sign-in schema. Shared by the client form and the server action.
 * Error messages are i18n keys resolved by the caller — never hardcoded strings.
 */
export const signInSchema = z.object({
  email: z.email({ message: "auth.errors.emailInvalid" }).trim().toLowerCase(),
  password: z
    .string({ message: "auth.errors.passwordRequired" })
    .min(1, { message: "auth.errors.passwordRequired" })
    .min(6, { message: "auth.errors.passwordTooShort" }),
});

export type SignInInput = z.infer<typeof signInSchema>;
