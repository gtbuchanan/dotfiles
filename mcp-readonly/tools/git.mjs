import { exec, fail } from "../lib/exec.mjs";
import { ArgsSchema, rejectSubcommand, rejectBlockedFlags } from "../lib/allowlist.mjs";

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
      // Block -o short flag: standalone (-o), concatenated (-ofile.txt), or
      // combined with other short flags (-ao, -abo/tmp/evil.txt)
      const shortO = args.slice(1).find((a) =>
        a.startsWith("-") && !a.startsWith("--") && a !== "-" &&
        [...a.slice(1).split("=")[0]].includes("o"),
      );
      if (shortO) return fail(`Flag not allowed: ${shortO}`);
      // Block --output and --no-index with prefix matching (defeats abbreviation)
      const globalRejected = rejectBlockedFlags(args, BLOCKED_FLAGS);
      if (globalRejected) return globalRejected;
      if (sub === "branch") {
        const rejected = rejectBlockedFlags(args, BRANCH_BLOCKED);
        if (rejected) return rejected;
      }
      if (sub === "stash") {
        let stashSub = null;
        for (const a of args.slice(1)) {
          if (a === "--") break;
          if (!a.startsWith("-")) { stashSub = a; break; }
        }
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
      // Inject --no-pager to prevent interactive pager from blocking the process
      return exec("git", ["--no-pager", ...args]);
    },
  );
