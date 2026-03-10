import { exec, fail } from "../lib/exec.mjs";
import { ArgsSchema, rejectSubcommand } from "../lib/allowlist.mjs";

const SUBCOMMANDS = new Set([
  "branch", "diff", "log", "remote", "rev-parse", "show", "stash", "status",
]);

// --no-index: reads arbitrary files outside the repo
// --output / -o: writes command output to a file (checked via startsWith below)
const BLOCKED_FLAGS = new Set(["--no-index", "--output"]);

const BRANCH_BLOCKED = new Set([
  "-D", "-d", "-m", "-M", "-c", "-C",
  "--delete", "--move", "--copy", "--edit-description",
  "--set-upstream-to", "--unset-upstream", "--force",
]);

// Only these sub-subcommands (or none) are allowed for `git stash`
const STASH_ALLOWED_SUBS = new Set(["list", "show"]);

// Only these sub-subcommands (or none) are allowed for `git remote`
// `show` is excluded because it triggers network I/O to the remote
const REMOTE_ALLOWED_SUBS = new Set(["get-url"]);

// Only these flags are allowed for `git remote` (bare listing and get-url)
const REMOTE_ALLOWED_FLAGS = new Set(["-v", "--verbose", "--push", "--all"]);

export const register = (server) =>
  server.tool(
    "git",
    "Run read-only git commands (branch, diff, log, remote, rev-parse, show, stash, status)",
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
      if (sub === "stash") {
        const stashSub = args.slice(1).find((a) => !a.startsWith("-"));
        if (!stashSub || !STASH_ALLOWED_SUBS.has(stashSub))
          return fail(`Subcommand not allowed for git stash: ${stashSub ?? "(none)"}. Allowed: ${[...STASH_ALLOWED_SUBS].join(", ")}`);
      }
      if (sub === "remote") {
        const remoteArgs = args.slice(1);
        const remoteSub = remoteArgs.find((a) => !a.startsWith("-"));
        if (remoteSub && !REMOTE_ALLOWED_SUBS.has(remoteSub))
          return fail(`Subcommand not allowed for git remote: ${remoteSub}. Allowed: (none), ${[...REMOTE_ALLOWED_SUBS].join(", ")}`);
        const blockedFlag = remoteArgs.filter((a) => a.startsWith("-")).find((a) => !REMOTE_ALLOWED_FLAGS.has(a));
        if (blockedFlag) return fail(`Flag not allowed for git remote: ${blockedFlag}`);
      }
      return exec("git", ["--no-pager", ...args]);
    },
  );
