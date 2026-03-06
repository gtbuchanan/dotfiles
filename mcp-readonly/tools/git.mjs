import { exec, fail } from "../lib/exec.mjs";
import { ArgsSchema, rejectSubcommand } from "../lib/allowlist.mjs";

const SUBCOMMANDS = new Set([
  "branch", "diff", "log", "rev-parse", "show", "status",
]);

// --no-index: reads arbitrary files outside the repo
// --output / -o: writes command output to a file (checked via startsWith below)
const BLOCKED_FLAGS = new Set(["--no-index", "--output"]);

const BRANCH_BLOCKED = new Set([
  "-D", "-d", "-m", "-M", "-c", "-C",
  "--delete", "--move", "--copy", "--edit-description",
  "--set-upstream-to", "--unset-upstream", "--force",
]);

export const register = (server) =>
  server.tool(
    "git",
    "Run read-only git commands (branch, diff, log, rev-parse, show, status)",
    ArgsSchema,
    async ({ args }) => {
      const sub = args[0];
      if (!SUBCOMMANDS.has(sub)) return rejectSubcommand(args, SUBCOMMANDS);
      const globalBlocked = args.slice(1).find((a) => BLOCKED_FLAGS.has(a) || a.startsWith("--output=") || a.startsWith("-o"));
      if (globalBlocked) return fail(`Flag not allowed: ${globalBlocked}`);
      if (sub === "branch") {
        const blocked = args.slice(1).find((a) => BRANCH_BLOCKED.has(a));
        if (blocked) return fail(`Flag not allowed for git branch: ${blocked}`);
      }
      return exec("git", ["--no-pager", ...args]);
    },
  );
