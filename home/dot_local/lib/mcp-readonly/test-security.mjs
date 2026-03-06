/**
 * Security tests for the read-only MCP server.
 *
 * Spawns the actual server as a child process and communicates over JSON-RPC/stdio.
 * Each test category targets a specific threat vector:
 *
 * - Subcommand allowlists: only explicitly permitted subcommands execute.
 * - Write-flag blocking: flags that write to files (--output, -o, --no-index) are rejected.
 * - Shell injection: execFile (no shell) prevents metacharacter expansion (;, &&, |, $(), ``).
 * - Command allowlist: only named shell utilities are permitted; path traversal is rejected.
 * - Secret-leaking commands: printenv, chezmoi data, rg, and file-reading utils are blocked.
 * - cwd rejection: no parameter allows callers to change the working directory.
 */

import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVER_PATH = join(__dirname, "index.mjs");

// --- MCP Client ---

const startServer = () => {
  const proc = spawn("node", [SERVER_PATH], {
    stdio: ["pipe", "pipe", "pipe"],
    cwd: process.cwd(),
  });

  const rl = createInterface({ input: proc.stdout });
  const pending = new Map();
  let nextId = 1;

  rl.on("line", (line) => {
    try {
      const msg = JSON.parse(line);
      if (msg.id && pending.has(msg.id)) {
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      }
    } catch { /* ignore non-JSON lines */ }
  });

  const send = (method, params) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, resolve);
      const msg = JSON.stringify({ jsonrpc: "2.0", id, method, params });
      proc.stdin.write(msg + "\n");
      setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error(`Timeout waiting for response to ${method}`));
        }
      }, 15_000);
    });

  const initialize = () =>
    send("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "test", version: "1.0.0" },
    });

  const callTool = async (name, args) => {
    const resp = await send("tools/call", { name, arguments: args });
    if (resp.error) return { isError: true, content: [{ type: "text", text: resp.error.message }] };
    return resp.result;
  };

  const close = () => {
    proc.stdin.end();
    proc.kill();
  };

  return { initialize, callTool, close };
};

// --- Test framework ---

let passed = 0;
let failed = 0;
const failures = [];

const assert = (condition, name) => {
  if (condition) {
    passed++;
  } else {
    failed++;
    failures.push(name);
    console.log(`  FAIL: ${name}`);
  }
};

const assertBlocked = (result, name) => {
  const txt = result?.content?.[0]?.text || "";
  assert(result?.isError || txt.includes("not allowed"), name);
};

const assertNotBlocked = (result, name) => {
  assert(!result?.isError, name);
};

// --- Start server and run tests ---

const server = startServer();
await server.initialize();

console.log("=== Git tool tests ===");

// Blocked subcommands
for (const sub of ["push", "pull", "fetch", "checkout", "reset", "rebase", "merge", "commit", "add", "rm", "clean", "stash"]) {
  const r = await server.callTool("git", { args: [sub] });
  assertBlocked(r, `git ${sub} should be blocked`);
}

// Allowed subcommands
const r1 = await server.callTool("git", { args: ["status"] });
assertNotBlocked(r1, "git status should be allowed");

const r2 = await server.callTool("git", { args: ["log", "--oneline", "-5"] });
assertNotBlocked(r2, "git log should be allowed");

// Blocked branch mutation flags
for (const flag of ["-D", "-d", "-m", "-M", "--delete", "--move", "--copy", "--force", "--set-upstream-to", "--unset-upstream"]) {
  const r = await server.callTool("git", { args: ["branch", flag, "test"] });
  assertBlocked(r, `git branch ${flag} should be blocked`);
}

// Allowed branch listing
const r3 = await server.callTool("git", { args: ["branch", "-a"] });
assertNotBlocked(r3, "git branch -a should be allowed");

console.log("\n=== Git write-flag blocking ===");

// --output writes to a file (works on log, diff, show)
for (const sub of ["log", "diff", "show"]) {
  const r = await server.callTool("git", { args: [sub, "--output=/tmp/evil.txt"] });
  assertBlocked(r, `git ${sub} --output=<path> should be blocked`);
}
const rOutput = await server.callTool("git", { args: ["log", "--output", "/tmp/evil.txt"] });
assertBlocked(rOutput, "git log --output <path> should be blocked");

// -o is a short alias for --output in git diff/log
const rShortO = await server.callTool("git", { args: ["diff", "-o", "/tmp/evil.txt"] });
assertBlocked(rShortO, "git diff -o should be blocked");

// -o with no space (e.g. -ofile.txt) should also be blocked
const rShortONoSpace = await server.callTool("git", { args: ["diff", "-ofile.txt"] });
assertBlocked(rShortONoSpace, "git diff -ofile.txt (no space) should be blocked");

// --no-index lets git diff read arbitrary files outside the repo
const rNoIndex = await server.callTool("git", { args: ["diff", "--no-index", "/etc/passwd", "/dev/null"] });
assertBlocked(rNoIndex, "git diff --no-index should be blocked");

console.log("\n=== Shell injection tests (execFile prevents shell expansion) ===");

// Create a temp dir with a canary file
const tmpDir = await mkdtemp(join(tmpdir(), "mcp-test-"));
const canaryFile = join(tmpDir, "canary.txt").replace(/\\/g, "/");
await writeFile(canaryFile, "ORIGINAL", "utf8");

// Try shell injection via git args
const injections = [
  ["status", ";", "rm", canaryFile],
  ["status", "&&", "rm", canaryFile],
  ["status", "||", "rm", canaryFile],
  ["status", "|", "rm", canaryFile],
  ["status", "$(rm " + canaryFile + ")"],
  ["status", "`rm " + canaryFile + "`"],
];

for (const args of injections) {
  await server.callTool("git", { args });
  const content = await readFile(canaryFile, "utf8");
  assert(content === "ORIGINAL", `git injection via "${args.join(" ")}" should not delete canary`);
}

// Try shell injection via shell tool args
// On Windows, shell tool uses: bash -c 'exec "$@"' -- <cmd> ...args
// exec "$@" with quoted $@ should prevent shell expansion of args
const shellInjections = [
  { command: "ls", args: ["; rm " + canaryFile] },
  { command: "ls", args: ["&& rm " + canaryFile] },
  { command: "ls", args: ["| rm " + canaryFile] },
  { command: "ls", args: ["$(rm " + canaryFile + ")"] },
  { command: "ls", args: ["`rm " + canaryFile + "`"] },
  // Args split across multiple array elements (bash word splitting)
  { command: "ls", args: [";", "rm", canaryFile] },
  { command: "ls", args: ["&&", "rm", canaryFile] },
  { command: "ls", args: ["||", "rm", canaryFile] },
  { command: "ls", args: ["|", "rm", canaryFile] },
  // Nested quoting / escape attempts
  { command: "ls", args: ['" ; rm ' + canaryFile + ' #'] },
  { command: "ls", args: ["' ; rm " + canaryFile + " #"] },
  // Newline injection (could break out of exec in some shells)
  { command: "ls", args: ["\nrm " + canaryFile] },
  { command: "ls", args: ["\r\nrm " + canaryFile] },
  // Null byte injection
  { command: "ls", args: ["\0rm " + canaryFile] },
];

for (const call of shellInjections) {
  await server.callTool("shell", call);
  const content = await readFile(canaryFile, "utf8");
  assert(content === "ORIGINAL", `shell injection via "${call.command} ${call.args.map(a => JSON.stringify(a)).join(" ")}" should not delete canary`);
}

// Try to use a disallowed command through shell tool
const r4 = await server.callTool("shell", { command: "rm", args: [canaryFile] });
assertBlocked(r4, "shell rm should be blocked");
const canaryContent = await readFile(canaryFile, "utf8");
assert(canaryContent === "ORIGINAL", "canary should still exist after blocked rm");

// Try command with path traversal in command name
const r5 = await server.callTool("shell", { command: "/bin/rm", args: [canaryFile] });
assertBlocked(r5, "shell /bin/rm should be blocked");

const r6 = await server.callTool("shell", { command: "../../bin/rm", args: [canaryFile] });
assertBlocked(r6, "shell ../../bin/rm should be blocked");

// Verify shell tool actually works for allowed commands (execShell path)
const lsResult = await server.callTool("shell", { command: "ls", args: [tmpDir.replace(/\\/g, "/")] });
assertNotBlocked(lsResult, "shell ls should be allowed");
assert(lsResult?.content?.[0]?.text?.includes("canary.txt"), "shell ls should list canary file");

console.log("\n=== Shell tool - blocked commands ===");

// Destructive commands, interpreters, and commands excluded by design:
// - printenv: leaks secrets via environment variables
// - rg: redundant with host Grep tool; allows searching arbitrary paths
// - bat, cat, delta, diff, head, tail: redundant with host Read tool
for (const cmd of ["rm", "mv", "cp", "chmod", "chown", "mkdir", "rmdir", "touch", "dd", "tee", "sed", "awk", "bash", "sh", "cmd", "powershell", "node", "python", "py", "printenv", "rg", "bat", "cat", "delta", "diff", "head", "tail"]) {
  const r = await server.callTool("shell", { command: cmd, args: [] });
  assertBlocked(r, `shell ${cmd} should be blocked`);
}

console.log("\n=== GH tool tests ===");

for (const args of [
  ["issue", "create"], ["issue", "close"], ["issue", "delete"], ["issue", "edit"],
  ["pr", "create"], ["pr", "close"], ["pr", "merge"], ["pr", "edit"],
  ["repo", "create"], ["repo", "delete"],
  ["auth", "login"],
]) {
  const r = await server.callTool("gh", { args });
  assertBlocked(r, `gh ${args.join(" ")} should be blocked`);
}

console.log("\n=== Chezmoi tool tests ===");

// data: excluded because it leaks template variables that may contain secrets
for (const args of [
  ["apply"], ["add"], ["data"], ["edit"], ["forget"], ["init"],
  ["remove"], ["re-add"], ["update"], ["destroy"],
]) {
  const r = await server.callTool("chezmoi", { args });
  assertBlocked(r, `chezmoi ${args.join(" ")} should be blocked`);
}

console.log("\n=== ACLI tool tests ===");

for (const args of [
  ["jira", "workitem", "create"],
  ["jira", "workitem", "edit"],
  ["jira", "workitem", "delete"],
  ["jira", "workitem", "assign"],
  ["jira", "workitem", "transition"],
  ["jira", "workitem", "comment", "create"],
]) {
  const r = await server.callTool("acli", { args });
  assertBlocked(r, `acli ${args.join(" ")} should be blocked`);
}

console.log("\n=== npm tool tests ===");

// Blocked subcommands (mutating operations)
for (const args of [
  ["install"], ["ci"], ["update"], ["uninstall", "lodash"],
  ["run", "build"], ["exec", "tsc"], ["publish"], ["init"],
  ["link"], ["pack"], ["prune"], ["rebuild"], ["dedupe"],
]) {
  const r = await server.callTool("npm", { args });
  assertBlocked(r, `npm ${args.join(" ")} should be blocked`);
}

// Blocked flags
const npmAuditFix = await server.callTool("npm", { args: ["audit", "--fix"] });
assertBlocked(npmAuditFix, "npm audit --fix should be blocked");

// --registry (SSRF / data exfiltration)
const npmRegistry = await server.callTool("npm", { args: ["view", "zod", "--registry", "https://evil.com"] });
assertBlocked(npmRegistry, "npm --registry should be blocked");

const npmRegistryEq = await server.callTool("npm", { args: ["view", "zod", "--registry=https://evil.com"] });
assertBlocked(npmRegistryEq, "npm --registry=<url> should be blocked");

// Allowed subcommands
const npmLs = await server.callTool("npm", { args: ["ls"] });
assertNotBlocked(npmLs, "npm ls should be allowed");

const npmExplain = await server.callTool("npm", { args: ["explain", "zod"] });
assertNotBlocked(npmExplain, "npm explain should be allowed");

const npmView = await server.callTool("npm", { args: ["view", "zod"] });
assertNotBlocked(npmView, "npm view should be allowed");

console.log("\n=== pnpm tool tests ===");

// Blocked subcommands (mutating operations)
for (const args of [
  ["add", "lodash"], ["remove", "lodash"], ["install"],
  ["update"], ["run", "build"], ["exec", "tsc"],
  ["publish"], ["init"], ["link"], ["unlink"],
  ["store", "prune"], ["patch", "lodash"],
]) {
  const r = await server.callTool("pnpm", { args });
  assertBlocked(r, `pnpm ${args.join(" ")} should be blocked`);
}

// Blocked flags
const pnpmAuditFix = await server.callTool("pnpm", { args: ["audit", "--fix"] });
assertBlocked(pnpmAuditFix, "pnpm audit --fix should be blocked");

// --registry (SSRF / data exfiltration)
const pnpmRegistry = await server.callTool("pnpm", { args: ["list", "--registry", "https://evil.com"] });
assertBlocked(pnpmRegistry, "pnpm --registry should be blocked");

const pnpmRegistryEq = await server.callTool("pnpm", { args: ["list", "--registry=https://evil.com"] });
assertBlocked(pnpmRegistryEq, "pnpm --registry=<url> should be blocked");

// Allowed subcommands
const pnpmList = await server.callTool("pnpm", { args: ["list"] });
assertNotBlocked(pnpmList, "pnpm list should be allowed");

const pnpmWhy = await server.callTool("pnpm", { args: ["why", "zod"] });
assertNotBlocked(pnpmWhy, "pnpm why should be allowed");

const pnpmLicenses = await server.callTool("pnpm", { args: ["licenses", "list"] });
assertNotBlocked(pnpmLicenses, "pnpm licenses list should be allowed");

const pnpmStoreStatus = await server.callTool("pnpm", { args: ["store", "status"] });
assertNotBlocked(pnpmStoreStatus, "pnpm store status should be allowed");

console.log("\n=== jq file argument blocking ===");

// jq with filter only (no file) should be allowed
const jqFilter = await server.callTool("shell", { command: "jq", args: ["-n", "empty"] });
assertNotBlocked(jqFilter, "jq -n empty (no file) should be allowed");

// jq with file argument should be blocked
const jqFile = await server.callTool("shell", { command: "jq", args: [".", "/etc/passwd"] });
assertBlocked(jqFile, "jq . /etc/passwd should be blocked");

const jqFileHome = await server.callTool("shell", { command: "jq", args: [".", canaryFile] });
assertBlocked(jqFileHome, "jq . <canary> should be blocked");

// jq with --arg (pair flag: name + value) followed by filter + file should still block the file
const jqArgFile = await server.callTool("shell", { command: "jq", args: ["--arg", "k", "v", ".", canaryFile] });
assertBlocked(jqArgFile, "jq --arg k v . <file> should be blocked");

// jq with --arg (pair flag) followed by filter only should be allowed
const jqArgNoFile = await server.callTool("shell", { command: "jq", args: ["--arg", "k", "v", "-n", ".foo"] });
assertNotBlocked(jqArgNoFile, "jq --arg k v -n .foo (no file) should be allowed");

// jq with --argjson (pair flag) followed by filter only should be allowed
const jqArgJson = await server.callTool("shell", { command: "jq", args: ["--argjson", "k", "123", "-n", "$k"] });
assertNotBlocked(jqArgJson, "jq --argjson k 123 -n $k (no file) should be allowed");

// jq file-reading flags should be blocked entirely
for (const flag of ["--slurpfile", "--rawfile", "--from-file", "-f"]) {
  const r = await server.callTool("shell", { command: "jq", args: [flag, "x", canaryFile] });
  assertBlocked(r, `jq ${flag} should be blocked (reads files)`);
}

// jq -L (library path) should be blocked
const jqLibPath = await server.callTool("shell", { command: "jq", args: ["-L", "/tmp", "-n", "empty"] });
assertBlocked(jqLibPath, "jq -L should be blocked");

// jq with only flags and filter should be allowed
const jqFlagsOnly = await server.callTool("shell", { command: "jq", args: ["-r", "-n", ".foo"] });
assertNotBlocked(jqFlagsOnly, "jq -r -n .foo (no file) should be allowed");

console.log("\n=== git --no-pager injection ===");

// Verify git commands don't hang on pager (--no-pager is injected)
const gitLogPager = await server.callTool("git", { args: ["log", "--oneline", "-1"] });
assertNotBlocked(gitLogPager, "git log with injected --no-pager should work");

console.log("\n=== Edge cases ===");

// Empty args
const r7 = await server.callTool("git", { args: [] });
assertBlocked(r7, "git with empty args should be blocked");

const r8 = await server.callTool("shell", { command: "", args: [] });
assertBlocked(r8, "shell with empty command should be blocked");

// Flags to allowed commands should pass through
const r9 = await server.callTool("git", { args: ["log", "--all", "--oneline", "-1"] });
assertNotBlocked(r9, "git log --all should be allowed");

// cwd was removed from the schema to prevent agents from reading files in
// arbitrary directories. MCP SDK strips unknown parameters, so passing cwd
// should have no effect on the command's working directory.
const rCwd = await server.callTool("git", { args: ["status"], cwd: "/tmp" });
const rCwdText = rCwd?.content?.[0]?.text || "";
assert(!rCwdText.includes("/tmp"), "git should ignore cwd parameter (not in schema)");

// Cleanup
await rm(tmpDir, { recursive: true });
server.close();

// --- Summary ---
console.log(`\n${"=".repeat(40)}`);
console.log(`Results: ${passed} passed, ${failed} failed`);
if (failures.length > 0) {
  console.log("\nFailures:");
  for (const f of failures) console.log(`  - ${f}`);
  process.exit(1);
}
