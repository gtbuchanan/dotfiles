import { execShell } from "../lib/exec.mjs";
import { ArgsSchema, matchesAllowlist, rejectSubcommand } from "../lib/allowlist.mjs";

const SUBCOMMANDS = new Set([
  // devops
  "devops project list", "devops project show",
  "devops team list", "devops team list-member", "devops team show",
  "devops extension list", "devops extension search", "devops extension show",
  "devops service-endpoint list", "devops service-endpoint show",
  "devops wiki list", "devops wiki show",
  "devops wiki page show",
  // pipelines
  "pipelines list", "pipelines show",
  "pipelines agent list", "pipelines agent show",
  "pipelines build list", "pipelines build show",
  "pipelines build definition list", "pipelines build definition show",
  "pipelines build tag list",
  "pipelines folder list",
  "pipelines pool list", "pipelines pool show",
  "pipelines release list", "pipelines release show",
  "pipelines release definition list", "pipelines release definition show",
  "pipelines runs list", "pipelines runs show",
  "pipelines runs artifact list",
  "pipelines runs tag list",
  "pipelines variable list",
  "pipelines variable-group list", "pipelines variable-group show",
]);

export const register = (server) =>
  server.tool(
    "az",
    "Run read-only Azure DevOps CLI commands (devops project/team/extension/service-endpoint/wiki, pipelines list/show/build/release/runs/pool/agent)",
    ArgsSchema,
    async ({ args }) => {
      if (!matchesAllowlist(args, SUBCOMMANDS))
        return rejectSubcommand(args, SUBCOMMANDS);
      return execShell("az", args);
    },
  );
