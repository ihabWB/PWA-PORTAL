/**
 * Fails when any source file uses physical-direction Tailwind utilities.
 * Complements the ESLint rule (which only sees JSX className literals) by scanning CSS too.
 * Usage: node scripts/check-rtl.mjs
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, extname } from "node:path";

const ROOT = new URL("../src/", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
const EXTS = new Set([".ts", ".tsx", ".css"]);
const PATTERN =
  /(^|[\s"'`:])-?(ml|mr|pl|pr|left|right|border-l|border-r|rounded-l|rounded-r|rounded-tl|rounded-tr|rounded-bl|rounded-br)-[\w[\]()/.%-]+|(^|[\s"'`:])(text|float)-(left|right)(?=[\s"'`]|$)/gm;

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (EXTS.has(extname(full))) out.push(full);
  }
  return out;
}

let failures = 0;
for (const file of walk(ROOT)) {
  const text = readFileSync(file, "utf8");
  // Allow explicit opt-outs for genuinely directional things (e.g. `dir="ltr"` inputs).
  const lines = text.split("\n");
  lines.forEach((line, i) => {
    if (line.includes("rtl-ok")) return;
    if (PATTERN.test(line)) {
      failures++;
      console.error(`${file}:${i + 1}: ${line.trim()}`);
    }
    PATTERN.lastIndex = 0;
  });
}

if (failures > 0) {
  console.error(`\n${failures} physical-direction utilities found. Use logical properties.`);
  process.exit(1);
}
console.log("RTL check passed: no physical-direction utilities in src/.");
