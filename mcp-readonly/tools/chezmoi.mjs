import { exec } from "../lib/exec.mjs";
import { ArgsSchema, matchesAllowlist, rejectSubcommand } from "../lib/allowlist.mjs";

const SUBCOMMANDS = new Set([
  "diff", "doctor", "managed",
  "source-path", "status", "target-path", "verify",
]);

export const register = (server) =>
  server.tool(
    "chezmoi",
    "Run read-only chezmoi commands (diff, doctor, managed, source-path, status, target-path, verify)",
    ArgsSchema,
    async ({ args }) => {
      if (!matchesAllowlist(args, SUBCOMMANDS))
        return rejectSubcommand(args, SUBCOMMANDS);
      return exec("chezmoi", args);
    },
  );
