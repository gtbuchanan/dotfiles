// Uses execShell instead of exec for Windows compatibility: pnpm installed via
// npm or corepack ships as a .cmd wrapper that execFile cannot invoke directly.
// execShell is a no-op on non-Windows and wraps with bash on Windows.
import { execShell } from "../lib/exec.mjs";
import { ArgsSchema, matchesAllowlist, rejectSubcommand, rejectBlockedFlags } from "../lib/allowlist.mjs";

const GLOBAL_FLAGS = new Set(["--version", "--help", "-h"]);

const SUBCOMMANDS = new Set([
  "audit", "bin", "licenses list", "list", "outdated", "root", "search", "store status", "why",
]);

// --fix: pnpm audit --fix attempts to update packages
// --registry: prevents SSRF / data exfiltration via attacker-controlled registries
const BLOCKED_FLAGS = new Set(["--fix", "--registry"]);

export const register = (server) =>
  server.tool(
    "pnpm",
    "Run read-only pnpm commands (--version, --help, audit, bin, licenses list, list, outdated, root, search, store status, why)",
    ArgsSchema,
    async ({ args }) => {
      const isGlobal = args.length === 1 && GLOBAL_FLAGS.has(args[0]);
      if (!isGlobal && !matchesAllowlist(args, SUBCOMMANDS))
        return rejectSubcommand(args, SUBCOMMANDS);
      const rejected = rejectBlockedFlags(args, BLOCKED_FLAGS);
      if (rejected) return rejected;
      return execShell("pnpm", args);
    },
  );
