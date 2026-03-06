import { exec } from "../lib/exec.mjs";
import { ArgsSchema, matchesAllowlist, rejectSubcommand } from "../lib/allowlist.mjs";

const SUBCOMMANDS = new Set([
  "issue list", "issue view",
  "pr checks", "pr diff", "pr list", "pr status", "pr view",
  "repo view",
  "run list", "run view",
  "search code", "search commits", "search issues", "search prs", "search repos",
]);

export const register = (server) =>
  server.tool(
    "gh",
    "Run read-only GitHub CLI commands (issue list/view, pr checks/diff/list/status/view, repo view, run list/view, search code/commits/issues/prs/repos)",
    ArgsSchema,
    async ({ args }) => {
      if (!matchesAllowlist(args, SUBCOMMANDS))
        return rejectSubcommand(args, SUBCOMMANDS);
      return exec("gh", args);
    },
  );
