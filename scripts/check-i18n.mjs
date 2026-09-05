/**
 * i18n integrity check. Runs before every build.
 *
 * The previous check only compared ar.json with en.json, so a key missing from BOTH files
 * passed while the app threw MISSING_MESSAGE at runtime. This one starts from the code:
 *
 *   A  every translation key used in src/ exists in ar AND en
 *   B  every key-like string literal (Zod messages, error keys) resolves in ar AND en
 *   C  every key in the message files is reachable from the code
 *   D  ar and en have identical key sets
 *
 * Namespaces indexed dynamically (t(someVariable)) cannot be resolved statically. They are
 * reported explicitly, their whole namespace is required in both locales, and their keys are
 * exempt from check C — the report says so rather than implying full coverage.
 *
 * Usage: node scripts/check-i18n.mjs
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, extname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = join(ROOT, "src");
const MESSAGES = { ar: join(SRC, "i18n/messages/ar.json"), en: join(SRC, "i18n/messages/en.json") };

// ---------------------------------------------------------------- message files
const load = (p) => JSON.parse(readFileSync(p, "utf8"));
const flatten = (obj, prefix = "") => {
  const out = new Map();
  for (const [k, v] of Object.entries(obj)) {
    const path = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === "object" && !Array.isArray(v)) {
      for (const [ik, iv] of flatten(v, path)) out.set(ik, iv);
    } else {
      out.set(path, v);
    }
  }
  return out;
};

const messages = Object.fromEntries(
  Object.entries(MESSAGES).map(([loc, p]) => [loc, flatten(load(p))]),
);
const locales = Object.keys(messages);
const topLevel = new Set([...messages.ar.keys()].map((k) => k.split(".")[0]));

// ---------------------------------------------------------------- source scan
const walk = (dir, out = []) => {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) walk(full, out);
    else if ([".ts", ".tsx"].includes(extname(full))) out.push(full);
  }
  return out;
};

/** Remove comments and JSX text so literals inside them are not mistaken for keys. */
const stripComments = (s) =>
  s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/(^|[^:])\/\/[^\n]*/g, "$1 ");

const usedKeys = new Map(); // key -> [locations]
const dynamicNamespaces = new Map(); // namespace -> [locations]
const record = (map, key, loc) => {
  if (!map.has(key)) map.set(key, []);
  map.get(key).push(loc);
};

const BIND =
  /(?:const|let)\s+(\w+)\s*=\s*(?:await\s+)?(?:useTranslations|getTranslations)\s*\(\s*(?:"([^"]*)"|'([^']*)')?\s*\)/g;
const KEY_LIKE = /["'`]([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9_]+)+)["'`]/g;

for (const file of walk(SRC)) {
  const rel = relative(ROOT, file).replace(/\\/g, "/");
  const raw = readFileSync(file, "utf8");
  const src = stripComments(raw);

  // Which local variables are translation functions, and for which namespace.
  const binders = new Map();
  for (const m of src.matchAll(BIND)) {
    binders.set(m[1], m[2] ?? m[3] ?? "");
  }

  for (const [name, ns] of binders) {
    // t("literal")  /  t.rich("literal")  /  t(anythingElse)
    const call = new RegExp(`\\b${name}(?:\\.(?:rich|raw|markup))?\\s*\\(`, "g");
    for (const m of src.matchAll(call)) {
      const rest = src.slice(m.index + m[0].length);
      const lit = /^\s*(?:"([^"]*)"|'([^']*)'|`([^`$]*)`)/.exec(rest);
      const line = src.slice(0, m.index).split("\n").length;
      const loc = `${rel}:${line}`;
      if (lit) {
        const key = lit[1] ?? lit[2] ?? lit[3];
        record(usedKeys, ns ? `${ns}.${key}` : key, loc);
      } else {
        record(dynamicNamespaces, ns, loc);
      }
    }
  }

  // Key-like literals anywhere (Zod messages, errorKey constants, action results).
  for (const m of src.matchAll(KEY_LIKE)) {
    const candidate = m[1];
    if (!topLevel.has(candidate.split(".")[0])) continue;
    const line = src.slice(0, m.index).split("\n").length;
    record(usedKeys, candidate, `${rel}:${line}`);
  }
}

// ---------------------------------------------------------------- checks
const problems = [];

// A + B: every used key exists in every locale
for (const [key, locs] of usedKeys) {
  for (const loc of locales) {
    if (!messages[loc].has(key)) {
      problems.push(`missing key "${key}" in ${loc}.json  (used at ${locs[0]})`);
    }
  }
}

// dynamic namespaces must exist and be non-empty in every locale
const dynamicKeyPrefixes = [];
for (const [ns, locs] of dynamicNamespaces) {
  if (ns === "") continue; // root-namespace dynamic use is covered by the key-like literal scan
  dynamicKeyPrefixes.push(`${ns}.`);
  for (const loc of locales) {
    const count = [...messages[loc].keys()].filter((k) => k.startsWith(`${ns}.`)).length;
    if (count === 0) {
      problems.push(
        `namespace "${ns}" is indexed dynamically but has no keys in ${loc}.json  (${locs[0]})`,
      );
    }
  }
}

// C: every declared key is reachable
const reachable = (key) => usedKeys.has(key) || dynamicKeyPrefixes.some((p) => key.startsWith(p));
const unused = [...messages.ar.keys()].filter((k) => !reachable(k));
for (const key of unused)
  problems.push(`unused key "${key}" is declared but never referenced in src/`);

// D: identical key sets across locales
for (const key of messages.ar.keys()) {
  if (!messages.en.has(key)) problems.push(`key "${key}" exists in ar.json but not en.json`);
}
for (const key of messages.en.keys()) {
  if (!messages.ar.has(key)) problems.push(`key "${key}" exists in en.json but not ar.json`);
}

// empty values are as broken as missing ones
for (const loc of locales) {
  for (const [key, value] of messages[loc]) {
    if (typeof value !== "string" || value.trim() === "") {
      problems.push(`key "${key}" in ${loc}.json is empty or not a string`);
    }
  }
}

// ---------------------------------------------------------------- report
const dynamicList = [...dynamicNamespaces.keys()].filter((n) => n !== "").sort();
console.log(
  `i18n check: ${usedKeys.size} keys referenced in src/, ${messages.ar.size} declared per locale.`,
);
if (dynamicList.length > 0) {
  console.log(
    `  namespaces indexed dynamically (presence verified, individual use not): ${dynamicList.join(", ")}`,
  );
}

if (problems.length > 0) {
  console.error(`\n${problems.length} problem(s):`);
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log("i18n check passed: every used key resolves in every locale, and no key is orphaned.");
