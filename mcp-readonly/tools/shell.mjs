import { z } from "zod";
import { execShell, fail } from "../lib/exec.mjs";

const COMMANDS = new Set([
  "basename", "date", "dirname", "eza", "file", "jq", "ls", "pwd",
  "readlink", "realpath", "stat", "wc", "which", "whoami",
]);

// jq: block file-path arguments to prevent reading arbitrary files.
// Allow only flags (-r, -e, -S, --arg, etc.) and filter expressions.
// Flags that read files — block entirely (data exfiltration via --slurpfile/--rawfile,
// arbitrary filter loading via --from-file/-f, library path probing via -L)
const JQ_FILE_FLAGS = new Set([
  "--slurpfile", "--rawfile", "--from-file", "-f", "-L", "--library-path",
]);
// Flags that take two following arguments (name + value)
const JQ_PAIR_FLAGS = new Set(["--arg", "--argjson"]);
// Flags that take one following argument
const JQ_VALUE_FLAGS = new Set(["--indent"]);

const validateJqArgs = (args) => {
  for (let i = 0; i < args.length; i++) {
    if (JQ_FILE_FLAGS.has(args[i])) return fail(`Flag not allowed for jq: ${args[i]}`);
    if (JQ_PAIR_FLAGS.has(args[i])) { i += 2; continue; }
    if (JQ_VALUE_FLAGS.has(args[i])) { i++; continue; }
    if (args[i].startsWith("-")) continue;
    // First non-flag arg is the filter expression; rest are file paths
    for (let j = i + 1; j < args.length; j++) {
      if (JQ_FILE_FLAGS.has(args[j])) return fail(`Flag not allowed for jq: ${args[j]}`);
      if (JQ_PAIR_FLAGS.has(args[j])) { j += 2; continue; }
      if (JQ_VALUE_FLAGS.has(args[j])) { j++; continue; }
      if (args[j].startsWith("-")) continue;
      return fail(`File arguments not allowed for jq (use stdin via piping). Got: ${args[j]}`);
    }
    break;
  }
  return null;
};

export const register = (server) =>
  server.tool(
    "shell",
    "Run read-only shell utilities (basename, date, dirname, eza, file, jq, ls, pwd, readlink, realpath, stat, wc, which, whoami)",
    {
      command: z.string().describe("Command name from the allowlist"),
      args: z.array(z.string()).default([]).describe("Command arguments"),
    },
    async ({ command, args }) => {
      if (!COMMANDS.has(command))
        return fail(`Command not allowed: ${command}. Allowed: ${[...COMMANDS].join(", ")}`);
      if (command === "jq") {
        const rejection = validateJqArgs(args);
        if (rejection) return rejection;
      }
      return execShell(command, args);
    },
  );
