/**
 * Concatenates supabase/migrations/*.sql in order into supabase/bundle.sql for one-shot
 * pasting into the Supabase SQL Editor. The bundle is derived output and git-ignored.
 */
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dir = join(root, "supabase", "migrations");
const files = readdirSync(dir)
  .filter((f) => f.endsWith(".sql"))
  .sort();

const parts = files.map((f) => {
  const body = readFileSync(join(dir, f), "utf8");
  return `-- >>>>>>>>>> ${f} >>>>>>>>>>\n${body}\n-- <<<<<<<<<< ${f} <<<<<<<<<<\n`;
});

const out = join(root, "supabase", "bundle.sql");
writeFileSync(out, parts.join("\n"), "utf8");
console.log(`Wrote ${out} (${files.length} files)`);
for (const f of files) console.log(`  ${f}`);
