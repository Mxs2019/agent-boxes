import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const output = execFileSync(
  "git",
  ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
  { encoding: "utf8" },
);
const files = output.split("\0").filter(Boolean);
const failures = [];

const unsafePathRules = [
  [/(^|\/)(?:node_modules|\.wrangler|\.build|DerivedData|dist|xcuserdata)(\/|$)/, "local output"],
  [/(^|\/)\.DS_Store$/, "macOS metadata"],
  [/(^|\/)(?:\.env|\.dev\.vars)(?!\.example$)/, "environment secrets"],
  [/\/\.npmrc$/, "credential configuration"],
  [/(^|\/)\.netrc$/, "credential configuration"],
  [/\.(?:key|pem|p8|p12|cer|mobileprovision|provisionprofile)$/i, "credential material"],
  [/\.(?:sqlite|sqlite-shm|sqlite-wal)$/i, "local database"],
  [/(^|\/)(?:Secrets|Local)\.xcconfig$/i, "local Xcode configuration"],
];

const privateKeyPattern = new RegExp(
  ["^-----BEGIN ", "(?:RSA |EC |OPENSSH )?PRIVATE KEY-----$"].join(""),
  "m",
);
const homePathPattern = new RegExp(
  ["(?:/Us", "ers/[^/\\s]+/|/ho", "me/[^/\\s]+/|[A-Za-z]:\\\\Us", "ers\\\\[^\\\\\\s]+\\\\)"].join(
    "",
  ),
);
const accountKeyPattern = new RegExp(["\\bab", "_account_[A-Za-z0-9_-]{32,}\\b"].join(""));
const agentKeyPattern = new RegExp(["\\bab", "_agent_[A-Za-z0-9_-]{32,}\\b"].join(""));

const unsafeContentRules = [
  [privateKeyPattern, "private key"],
  [/\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b/, "GitHub token"],
  [/\bgithub_pat_[A-Za-z0-9_]{30,}\b/, "GitHub token"],
  [/\bnpm_[A-Za-z0-9]{30,}\b/, "npm token"],
  [/\bAKIA[0-9A-Z]{16}\b/, "AWS access key"],
  [/\bsk-[A-Za-z0-9_-]{24,}\b/, "API key"],
  [accountKeyPattern, "Agent Box account key"],
  [agentKeyPattern, "Agent Box agent key"],
  [/(?:CLOUDFLARE_API_TOKEN|CF_API_TOKEN)\s*[:=]\s*["']?[A-Za-z0-9_-]{20,}/, "Cloudflare token"],
  [/Authorization:\s*Bearer\s+[A-Za-z0-9._-]{24,}/i, "bearer token"],
  [/https?:\/\/[^\s/:]+:[^\s/@]+@/i, "URL credentials"],
  [homePathPattern, "local home path"],
];

for (const file of files) {
  for (const [pattern, reason] of unsafePathRules) {
    if (pattern.test(file)) failures.push(`${file}: ${reason}`);
  }

  let data;
  try {
    data = readFileSync(file);
  } catch {
    continue;
  }
  if (data.includes(0)) continue;

  const content = data.toString("utf8");
  for (const [pattern, reason] of unsafeContentRules) {
    if (pattern.test(content)) failures.push(`${file}: ${reason}`);
  }
}

if (failures.length > 0) {
  console.error("Public-safety check failed:");
  for (const failure of [...new Set(failures)].sort()) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Public-safety check passed for ${files.length} files.`);
