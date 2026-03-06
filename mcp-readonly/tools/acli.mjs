import { exec } from "../lib/exec.mjs";
import { ArgsSchema, matchesAllowlist, rejectSubcommand } from "../lib/allowlist.mjs";

const SUBCOMMANDS = new Set([
  "jira board list",
  "jira filter list",
  "jira project list",
  "jira sprint list",
  "jira workitem comment list",
  "jira workitem list",
  "jira workitem search",
  "jira workitem view",
]);

export const register = (server) =>
  server.tool(
    "acli",
    "Run read-only Atlassian CLI commands (jira board/filter/project/sprint/workitem list/search/view/comment list)",
    ArgsSchema,
    async ({ args }) => {
      if (!matchesAllowlist(args, SUBCOMMANDS))
        return rejectSubcommand(args, SUBCOMMANDS);
      return exec("acli", args);
    },
  );
