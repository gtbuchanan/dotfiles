/**
 * Read-only MCP server for AI agents.
 *
 * Security design:
 *
 * - Allowlists, not denylists: every command/subcommand must be explicitly permitted.
 * - No `cwd` parameter: commands run in the server's working directory only.
 *   Allowing callers to set `cwd` would let an agent (or prompt injection) read
 *   files in arbitrary directories. The host's `Read` tool already covers
 *   file-reading needs with its own permission prompts.
 * - execFile (no shell): prevents shell metacharacter injection (;, &&, |, $(), ``)
 *   even when args contain untrusted input. On Windows, a `bash -c 'exec "$@"'`
 *   wrapper preserves this guarantee for shell utilities.
 * - --registry blocked: prevents SSRF / data exfiltration to attacker-controlled registries.
 * - --ignore-scripts injected: defense-in-depth for npm to prevent lifecycle scripts.
 *   Not needed for pnpm: its allowed subcommands are inherently read-only and reject the flag.
 * - Resource limits (timeout, maxBuffer): prevent runaway commands from consuming
 *   excessive CPU/memory on expensive operations (e.g., recursive ls).
 *
 * Auto-allow implications:
 * - These tools are auto-allowed in Claude settings (no user confirmation prompt).
 *   The allowlist/blocklist logic is the sole security boundary against prompt
 *   injection. Any command reachable through the allowlists can be invoked by
 *   an attacker who compromises the agent's context.
 *
 * Excluded by design:
 * - `chezmoi data`: leaks template variables that may contain secrets.
 * - `printenv` / `env`: leaks environment variables (API keys, tokens).
 * - `rg`: redundant with host `Grep` tool; allows searching arbitrary paths.
 * - `cat`, `head`, `tail`, `bat`, `diff`, `delta`: redundant with host `Read`
 *   tool; accepting path args would duplicate file-read surface area.
 * - `git diff --no-index`: reads arbitrary files outside the repo via git's
 *   diff machinery, bypassing the "git operations only" intent.
 * - `git --output` / `-o`: writes diff/log output to a file.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { z } from "zod";

const run = promisify(execFile);

const EXEC_OPTS = { timeout: 10_000, maxBuffer: 2 * 1024 * 1024 };

const text = (stdout, stderr) => ({
  content: [{ type: "text", text: (stdout + stderr).trimEnd() || "(no output)" }],
});

const fail = (msg) => ({
  content: [{ type: "text", text: msg }],
  isError: true,
});

const IS_WIN = process.platform === "win32";

const exec = async (cmd, args) => {
  try {
    const { stdout, stderr } = await run(cmd, args, EXEC_OPTS);
    return text(stdout, stderr);
  } catch (err) {
    if (err.stdout || err.stderr) return text(err.stdout || "", err.stderr || "");
    return fail(err.message);
  }
};

const execShell = async (cmd, args) => {
  if (!IS_WIN) return exec(cmd, args);
  return exec("bash", ["-c", 'exec "$@"', "--", cmd, ...args]);
};

const matchesAllowlist = (args, allowlist, maxDepth) => {
  for (let i = 1; i <= Math.min(args.length, maxDepth); i++) {
    if (allowlist.has(args.slice(0, i).join(" "))) return true;
  }
  return false;
};

const rejectSubcommand = (args, depth, allowlist) =>
  fail(`Subcommand not allowed: ${args.slice(0, depth).join(" ")}. Allowed: ${[...allowlist].join(", ")}`);

// --- Allowlists ---

const GIT_SUBCOMMANDS = new Set([
  "branch", "diff", "log", "rev-parse", "show", "status",
]);

// --no-index: reads arbitrary files outside the repo
// --output / -o: writes command output to a file (checked via startsWith below)
const GIT_BLOCKED_FLAGS = new Set([
  "--no-index", "--output",
]);

const GIT_BRANCH_BLOCKED = new Set([
  "-D", "-d", "-m", "-M", "-c", "-C",
  "--delete", "--move", "--copy", "--edit-description",
  "--set-upstream-to", "--unset-upstream", "--force",
]);

const CHEZMOI_SUBCOMMANDS = new Set([
  "cat-config", "diff", "doctor", "managed",
  "source-path", "state dump", "status", "target-path", "verify",
]);

const GH_SUBCOMMANDS = new Set([
  "issue list", "issue view",
  "pr checks", "pr diff", "pr list", "pr status", "pr view",
  "repo view",
  "run list", "run view",
  "search code", "search commits", "search issues", "search prs", "search repos",
]);

const ACLI_SUBCOMMANDS = new Set([
  "jira board list",
  "jira filter list",
  "jira project list",
  "jira sprint list",
  "jira workitem comment list",
  "jira workitem list",
  "jira workitem search",
  "jira workitem view",
]);

const NPM_SUBCOMMANDS = new Set([
  "audit", "bin", "explain", "fund", "ls", "outdated", "root", "search", "view",
]);

// --fix: npm audit fix attempts to update packages
// --registry: prevents SSRF / data exfiltration via attacker-controlled registries
const NPM_BLOCKED_FLAGS = new Set(["--fix", "--registry"]);

const PNPM_SUBCOMMANDS = new Set([
  "audit", "bin", "licenses list", "list", "outdated", "root", "search", "store status", "why",
]);

// --fix: pnpm audit --fix attempts to update packages
// --registry: prevents SSRF / data exfiltration via attacker-controlled registries
const PNPM_BLOCKED_FLAGS = new Set(["--fix", "--registry"]);

const SHELL_COMMANDS = new Set([
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

const SHELL_BLOCKED_FLAGS = {};

// --- Server ---

const server = new McpServer({ name: "readonly", version: "1.0.0" });

const ArgsSchema = {
  args: z.array(z.string()).describe("Command arguments"),
};

server.tool(
  "git",
  "Run read-only git commands (branch, diff, log, rev-parse, show, status)",
  ArgsSchema,
  async ({ args }) => {
    const sub = args[0];
    if (!GIT_SUBCOMMANDS.has(sub)) return rejectSubcommand(args, 1, GIT_SUBCOMMANDS);
    const globalBlocked = args.slice(1).find((a) => GIT_BLOCKED_FLAGS.has(a) || a.startsWith("--output=") || a.startsWith("-o"));
    if (globalBlocked) return fail(`Flag not allowed: ${globalBlocked}`);
    if (sub === "branch") {
      const blocked = args.slice(1).find((a) => GIT_BRANCH_BLOCKED.has(a));
      if (blocked) return fail(`Flag not allowed for git branch: ${blocked}`);
    }
    return exec("git", ["--no-pager", ...args]);
  },
);

server.tool(
  "chezmoi",
  "Run read-only chezmoi commands (cat-config, diff, doctor, managed, source-path, state dump, status, target-path, verify)",
  ArgsSchema,
  async ({ args }) => {
    if (!matchesAllowlist(args, CHEZMOI_SUBCOMMANDS, 2))
      return rejectSubcommand(args, 2, CHEZMOI_SUBCOMMANDS);
    return exec("chezmoi", args);
  },
);

server.tool(
  "gh",
  "Run read-only GitHub CLI commands (issue list/view, pr checks/diff/list/status/view, repo view, run list/view, search code/commits/issues/prs/repos)",
  ArgsSchema,
  async ({ args }) => {
    if (!matchesAllowlist(args, GH_SUBCOMMANDS, 2))
      return rejectSubcommand(args, 2, GH_SUBCOMMANDS);
    return exec("gh", args);
  },
);

server.tool(
  "acli",
  "Run read-only Atlassian CLI commands (jira board/filter/project/sprint/workitem list/search/view/comment list)",
  ArgsSchema,
  async ({ args }) => {
    if (!matchesAllowlist(args, ACLI_SUBCOMMANDS, 4))
      return rejectSubcommand(args, 4, ACLI_SUBCOMMANDS);
    return exec("acli", args);
  },
);

server.tool(
  "npm",
  "Run read-only npm commands (audit, bin, explain, fund, ls, outdated, root, search, view)",
  ArgsSchema,
  async ({ args }) => {
    if (!matchesAllowlist(args, NPM_SUBCOMMANDS, 1))
      return rejectSubcommand(args, 1, NPM_SUBCOMMANDS);
    const blocked = args.slice(1).find((a) => NPM_BLOCKED_FLAGS.has(a) || a.startsWith("--registry="));
    if (blocked) return fail(`Flag not allowed: ${blocked}`);
    return execShell("npm", ["--ignore-scripts", ...args]);
  },
);

server.tool(
  "pnpm",
  "Run read-only pnpm commands (audit, bin, licenses list, list, outdated, root, search, store status, why)",
  ArgsSchema,
  async ({ args }) => {
    if (!matchesAllowlist(args, PNPM_SUBCOMMANDS, 2))
      return rejectSubcommand(args, 2, PNPM_SUBCOMMANDS);
    const blocked = args.slice(1).find((a) => PNPM_BLOCKED_FLAGS.has(a) || a.startsWith("--registry="));
    if (blocked) return fail(`Flag not allowed: ${blocked}`);
    return exec("pnpm", args);
  },
);

server.tool(
  "shell",
  "Run read-only shell utilities (basename, date, dirname, eza, file, jq, ls, pwd, readlink, realpath, stat, wc, which, whoami)",
  {
    command: z.string().describe("Command name from the allowlist"),
    args: z.array(z.string()).default([]).describe("Command arguments"),
  },
  async ({ command, args }) => {
    if (!SHELL_COMMANDS.has(command))
      return fail(`Command not allowed: ${command}. Allowed: ${[...SHELL_COMMANDS].join(", ")}`);
    const blocked = SHELL_BLOCKED_FLAGS[command];
    if (blocked) {
      const flag = args.find((a) => blocked.has(a) || [...blocked].some((f) => a.startsWith(f + "=")));
      if (flag) return fail(`Flag not allowed for ${command}: ${flag}`);
    }
    if (command === "jq") {
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
    }
    return execShell(command, args);
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
