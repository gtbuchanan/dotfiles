import { exec } from "../lib/exec.mjs";
import { ArgsSchema, matchesAllowlist, rejectSubcommand } from "../lib/allowlist.mjs";

const GLOBAL_FLAGS = new Set(["--version", "--help", "-h"]);

const SUBCOMMANDS = new Set([
  "attestation verify",
  "cache list",
  "gist list", "gist view",
  "issue list", "issue status", "issue view",
  "label list",
  "pr checks", "pr diff", "pr list", "pr status", "pr view",
  "project field-list", "project item-list", "project list", "project view",
  "release list", "release view",
  "repo list", "repo view",
  "ruleset check", "ruleset list", "ruleset view",
  "run list", "run view",
  "search code", "search commits", "search issues", "search prs", "search repos",
  "secret list",
  "status",
  // variable get: excluded because it returns plaintext values, which may
  // contain internal URLs, hostnames, or other quasi-sensitive configuration
  // that should not be exposed to an LLM. variable list only shows names.
  "variable list",
  "workflow list", "workflow view",
]);

export const register = (server) =>
  server.tool(
    "gh",
    "Run read-only GitHub CLI commands (--version, --help, attestation verify, cache list, gist list/view, issue list/status/view, label list, pr checks/diff/list/status/view, project field-list/item-list/list/view, release list/view, repo list/view, ruleset check/list/view, run list/view, search code/commits/issues/prs/repos, secret list, status, variable list, workflow list/view)",
    ArgsSchema,
    async ({ args }) => {
      const isGlobal = args.length === 1 && GLOBAL_FLAGS.has(args[0]);
      if (!isGlobal && !matchesAllowlist(args, SUBCOMMANDS))
        return rejectSubcommand(args, SUBCOMMANDS);
      return exec("gh", args);
    },
  );
