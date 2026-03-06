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
import * as tools from "./tools/index.mjs";

const server = new McpServer({ name: "readonly", version: "1.0.0" });

Object.values(tools).forEach((register) => register(server));

const transport = new StdioServerTransport();
await server.connect(transport);
