import { z } from "zod";
import { fail } from "./exec.mjs";

// LLMs frequently serialize array parameters as JSON strings instead of native
// arrays (e.g., '["status", "-sb"]' instead of ["status", "-sb"]). The MCP
// Python SDK calls this out explicitly; the TypeScript SDK does not handle it.
// Coerce stringified JSON arrays before Zod validation so callers recover
// gracefully. Only arrays are accepted — stringified objects/primitives still
// fail validation.
const coerceArgs = (val) => {
  if (typeof val !== "string") return val;
  try {
    const parsed = JSON.parse(val);
    if (Array.isArray(parsed)) return parsed;
  } catch {}
  return val;
};

export const ArgsSchema = {
  args: z.preprocess(coerceArgs, z.array(z.string()).default([]))
    .describe("Command arguments"),
};

const maxDepthOf = (allowlist) => {
  const entries = [...allowlist];
  return entries.length === 0 ? 1 : Math.max(...entries.map((s) => s.split(" ").length));
};

export const matchesAllowlist = (args, allowlist) => {
  const depth = maxDepthOf(allowlist);
  let key = "";
  for (let i = 0; i < Math.min(args.length, depth); i++) {
    key = i === 0 ? args[0] : key + " " + args[i];
    if (allowlist.has(key)) return true;
  }
  return false;
};

export const rejectSubcommand = (args, allowlist) => {
  const depth = maxDepthOf(allowlist);
  const sub = args.slice(0, depth).join(" ") || "(none)";
  return fail(`Subcommand not allowed: ${sub}. Allowed: ${[...allowlist].join(", ")}`);
};

// Uses prefix matching to defeat CLI flag abbreviation. Many CLIs (notably npm
// and pnpm) expand unique prefixes internally, so `--reg` resolves to
// `--registry`. Exact matching would be bypassable via abbreviation. The
// trade-off is that a blocked flag like `--fix` also blocks any flag starting
// with `--fix` (e.g., a hypothetical `--fixup`). This errs on the side of
// safety: false positives (blocking a legitimate flag) are preferable to false
// negatives (allowing a dangerous abbreviated flag through).
export const normalizeApiPath = (endpoint) =>
  endpoint?.replace(/^\//, "").split("?")[0].replace(/\/$/, "") || "";

// Matches a GitHub API endpoint path against a list of segment patterns.
// `*` matches exactly one segment; trailing `**` matches one or more remaining
// segments (for variable-depth paths like repos/*/*/contents/**).
// Rejects full URLs (http:// / https://) to prevent targeting arbitrary hosts.
export const matchesApiPath = (endpoint, patterns) => {
  if (/^https?:\/\//.test(endpoint)) return false;
  const normalized = normalizeApiPath(endpoint);
  if (!normalized) return false;
  const segments = normalized.split("/");
  return patterns.some((pattern) => {
    const pSegments = pattern.split("/");
    const last = pSegments[pSegments.length - 1];
    if (last === "**") {
      const prefix = pSegments.slice(0, -1);
      return segments.length > prefix.length &&
        prefix.every((p, i) => p === "*" || p === segments[i]);
    }
    return pSegments.length === segments.length &&
      pSegments.every((p, i) => p === "*" || p === segments[i]);
  });
};

export const rejectApiEndpoint = (endpoint, patterns) => {
  const normalized = normalizeApiPath(endpoint) || "(none)";
  return fail(`API endpoint not allowed: ${normalized}. Allowed patterns: ${patterns.join(", ")}`);
};

export const rejectBlockedFlags = (args, blockedFlags) => {
  const flag = args.slice(1).find((a) =>
    a !== "--" && a !== "-" &&
    [...blockedFlags].some((f) =>
      a === f || a.startsWith(f + "=") || f.startsWith(a.split("=")[0]) ||
      // Short flags (-X) accept concatenated values (-XPOST) in most CLIs
      // (pflag/cobra, getopt). Match any arg starting with a 2-char short flag.
      (f.length === 2 && f[0] === "-" && f[1] !== "-" && a.startsWith(f))
    ),
  );
  return flag ? fail(`Flag not allowed: ${flag}`) : null;
};
