import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const dependencyFields = [
  "dependencies",
  "devDependencies",
  "optionalDependencies",
  "peerDependencies",
];
const exactVersion =
  /^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/;

const packageFiles = ["package.json"];
for (const workspaceRoot of ["apps", "packages"]) {
  for (const entry of readdirSync(workspaceRoot, { withFileTypes: true })) {
    const packageFile = join(workspaceRoot, entry.name, "package.json");
    if (entry.isDirectory() && existsSync(packageFile)) packageFiles.push(packageFile);
  }
}

const failures = [];

function checkOverride(file, path, value) {
  if (typeof value === "string") {
    if (!exactVersion.test(value)) failures.push(`${file}: ${path} uses ${value}`);
    return;
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    failures.push(`${file}: ${path} must contain an exact version or nested overrides`);
    return;
  }
  for (const [name, nestedValue] of Object.entries(value)) {
    checkOverride(file, `${path}.${name}`, nestedValue);
  }
}

for (const file of packageFiles) {
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    throw new Error(`${file} does not contain valid JSON.`, { cause: error });
  }

  for (const field of dependencyFields) {
    for (const [name, version] of Object.entries(manifest[field] ?? {})) {
      if (!exactVersion.test(version)) failures.push(`${file}: ${field}.${name} uses ${version}`);
    }
  }

  for (const [name, value] of Object.entries(manifest.overrides ?? {})) {
    checkOverride(file, `overrides.${name}`, value);
  }

  if (file === "package.json") {
    if (!/^npm@\d+\.\d+\.\d+$/.test(manifest.packageManager ?? "")) {
      failures.push(`${file}: packageManager must use an exact npm version`);
    }
    const npmEngineVersion = manifest.devEngines?.packageManager?.version;
    if (!exactVersion.test(npmEngineVersion ?? "")) {
      failures.push(`${file}: devEngines.packageManager.version must be exact`);
    }
  }
}

const npmConfigLines = new Set(
  readFileSync(".npmrc", "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#")),
);
for (const setting of ["save-exact=true", "min-release-age=7"]) {
  if (!npmConfigLines.has(setting)) failures.push(`.npmrc: ${setting} is required`);
}

const workflowDirectory = ".github/workflows";
if (existsSync(workflowDirectory)) {
  for (const entry of readdirSync(workflowDirectory, { withFileTypes: true })) {
    if (!entry.isFile() || !/\.ya?ml$/.test(entry.name)) continue;
    const workflowFile = join(workflowDirectory, entry.name);
    const workflow = readFileSync(workflowFile, "utf8");
    for (const match of workflow.matchAll(/^\s*uses:\s*[^\s#]+@([^\s#]+)/gm)) {
      if (!/^[0-9a-f]{40}$/i.test(match[1])) {
        failures.push(`${workflowFile}: action reference ${match[0].trim()} is not a commit SHA`);
      }
    }
  }
}

if (failures.length > 0) {
  console.error("Dependency policy check failed. Use exact package versions:");
  for (const failure of failures.sort()) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Dependency policy check passed for ${packageFiles.length} package files.`);
