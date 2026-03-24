/**
 * Read-only MCP server for AI agents.
 *
 * Security design:
 *
 * - Allowlists, not denylists: every command/subcommand must be explicitly permitted.
 * - No generic `cwd` parameter: most commands run in the server's working
 *   directory only. Allowing callers to set `cwd` would let an agent (or
 *   prompt injection) read files in arbitrary directories. Exception: the git
 *   tool accepts an optional `cwd` validated against `git worktree list`, so
 *   agents in linked worktrees can resolve HEAD correctly without opening
 *   arbitrary directory access.
 * - cwd exception criteria: a tool may accept `cwd` only when (1) the set of
 *   valid targets is enumerable at runtime from a trusted source (e.g.,
 *   `git worktree list`), (2) the caller-supplied path is resolved and
 *   compared exactly against that set (no prefix/substring matching), and
 *   (3) the tool's existing allowlist/blocklist checks still apply to the
 *   args. Generic user-supplied directory access is never permitted.
 * - execFile (no shell): prevents shell metacharacter injection (;, &&, |, $(), ``)
 *   even when args contain untrusted input. On Windows, a `bash -c 'exec "$@"'`
 *   wrapper preserves this guarantee for shell utilities.
 * - --registry blocked: prevents SSRF / data exfiltration to attacker-controlled registries.
 *   Uses prefix matching because npm/pnpm expand abbreviated flags internally
 *   (e.g., `--reg` resolves to `--registry`). Exact matching would be bypassable.
 * - --ignore-scripts injected: defense-in-depth for npm to prevent lifecycle scripts.
 *   `--no-ignore-scripts` is also blocked to prevent last-wins override.
 *   Not needed for pnpm: its allowed subcommands are inherently read-only and reject the flag.
 * - Resource limits (timeout, maxBuffer): prevent runaway commands from consuming
 *   excessive CPU/memory on expensive operations (e.g., recursive ls).
 * - Non-zero exit codes with output: returned as successful results (no isError)
 *   because many read-only commands use non-zero exits for informational purposes
 *   (e.g., git diff exits 1 when differences exist, npm audit exits 1 when
 *   vulnerabilities are found). The output content itself conveys the meaning.
 *
 * Auto-allow implications:
 * - These tools are auto-allowed in Claude settings (no user confirmation prompt).
 *   The allowlist/blocklist logic is the sole security boundary against prompt
 *   injection. Any command reachable through the allowlists can be invoked by
 *   an attacker who compromises the agent's context.
 *
 * Accepted risks (auto-allow surface area):
 * - `git show` / `git diff`: expose the full git object store, including files
 *   from any historical commit. Accidentally committed secrets (even if since
 *   rotated/deleted) are readable without user confirmation. This is inherent
 *   to allowing read-only git operations and is accepted by design.
 * - `gh search`: can search code/commits/issues across all repos the
 *   authenticated user can access, including private repos. Results are
 *   constrained by GitHub's search API (no full file contents).
 * - Shell metadata commands (`ls`, `stat`, `readlink`, `realpath`, `wc`, `file`,
 *   `eza`): accept arbitrary path arguments and can enumerate filesystem metadata
 *   (directory listings, permissions, symlink targets, line/byte counts) outside
 *   the working directory. They cannot read file contents — `cat`/`head`/`tail`
 *   are excluded for that reason. The host's `Read` tool with its own permission
 *   prompts is the content-read boundary.
 * - `az` non-invoke subcommands: no flag filtering is applied. The allowlisted
 *   commands (`list`, `show`) are inherently read-only. If future az CLI versions
 *   add mutating flags to these commands, they would pass through unchecked.
 * - `jq --jsonargs` / `--args`: not handled by the file-path validator, which
 *   may false-positive on legitimate uses. The error direction is safe (blocks
 *   rather than allows). These flags are uncommon in MCP agent usage.
 *
 * Excluded by design:
 * - `chezmoi data`: leaks template variables that may contain secrets.
 * - `chezmoi cat-config`: may expose encryption keys, GPG recipient IDs, or
 *   other sensitive configuration values.
 * - `printenv` / `env`: leaks environment variables (API keys, tokens).
 * - `rg`: redundant with host `Grep` tool; allows searching arbitrary paths.
 * - `cat`, `head`, `tail`, `bat`, `diff`, `delta`: redundant with host `Read`
 *   tool; accepting path args would duplicate file-read surface area.
 * - `git diff --no-index`: reads arbitrary files outside the repo via git's
 *   diff machinery, bypassing the "git operations only" intent.
 * - `git --output` / `-o`: writes diff/log output to a file.
 */
import { createRequire } from "node:module";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as tools from "./tools/index.mjs";

const require = createRequire(import.meta.url);
const { version } = require("./package.json");

const server = new McpServer({ name: "readonly", version });

Object.values(tools).forEach((register) => register(server));

const transport = new StdioServerTransport();
await server.connect(transport);
