import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

/**
 * RTL guard: physical-direction Tailwind utilities break the Arabic layout.
 * Use logical equivalents: ms-/me-/ps-/pe-/start-/end-/text-start/text-end/border-s/border-e/rounded-s/rounded-e.
 */
const PHYSICAL_UTILITY =
  "(^|\\s|:)(-?)(ml|mr|pl|pr|left|right|inset-x-0 |border-l|border-r|rounded-l|rounded-r|rounded-tl|rounded-tr|rounded-bl|rounded-br|scroll-ml|scroll-mr|scroll-pl|scroll-pr)-|(^|\\s|:)text-(left|right)(\\s|$)|(^|\\s|:)float-(left|right)(\\s|$)";

const rtlRule = {
  "no-restricted-syntax": [
    "error",
    {
      selector: `JSXAttribute[name.name='className'] > Literal[value=/${PHYSICAL_UTILITY}/]`,
      message:
        "Physical direction utility in className. Use logical properties (ms-*, me-*, ps-*, pe-*, start-*, end-*, text-start/end, border-s/e).",
    },
    {
      selector: `JSXAttribute[name.name='className'] TemplateElement[value.raw=/${PHYSICAL_UTILITY}/]`,
      message:
        "Physical direction utility in className. Use logical properties (ms-*, me-*, ps-*, pe-*, start-*, end-*, text-start/end, border-s/e).",
    },
  ],
};

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    files: ["src/**/*.{ts,tsx}"],
    rules: rtlRule,
  },
  globalIgnores([".next/**", "out/**", "build/**", "next-env.d.ts", "node_modules/**"]),
]);
