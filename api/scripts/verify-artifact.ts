import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

/**
 * Confirms `api/generated/` matches the buildHash in its own manifest.
 *
 * Self-contained on purpose: it runs as the Vercel build command, where the
 * repo outside the project root may not be present. Drift between `shared/`
 * and the artifact is caught separately by `scripts/validate_shared.py`, which
 * does have the whole repo.
 */
const GENERATED = fileURLToPath(new URL("../generated/", import.meta.url));

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });
}

const manifestPath = join(GENERATED, "manifest.json");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8")) as {
  schemaVersion: string;
  buildHash: string;
};

// Same recipe as the generator: sorted by full path, hashing basename then body.
const digest = createHash("sha256");
for (const path of walk(GENERATED).filter((path) => path !== manifestPath).sort()) {
  digest.update(path.split("/").pop() ?? "");
  digest.update(readFileSync(path, "utf8"));
}
const computed = digest.digest("hex").slice(0, 16);

if (computed !== manifest.buildHash) {
  console.error(
    `generated artifact does not match its manifest\n` +
      `  manifest: ${manifest.buildHash}\n  computed: ${computed}\n` +
      `  run: python3 scripts/build_intelligence_schemas.py`,
  );
  process.exit(1);
}

console.log(`generated artifact ok — schema ${manifest.schemaVersion}, build ${manifest.buildHash}`);
