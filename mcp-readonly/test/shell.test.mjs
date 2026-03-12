import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

// --- Unit tests (mocked execShell) ---
vi.mock("../lib/exec.mjs", () => ({
  execShell: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify({ cmd: _cmd, args }) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/shell.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (command, args = []) => handler({ command, args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("shell tool (unit)", () => {
  describe("allowed commands", () => {
    it.for([
      "basename", "date", "dirname", "eza", "file", "jq", "ls", "pwd",
      "readlink", "realpath", "stat", "wc", "which", "whoami",
    ])("allows %s", async (cmd, { expect }) => {
      assertAllowed(expect, await callMocked(cmd));
    });
  });
});

// --- Integration tests (real MCP server) ---
describe.concurrent("shell tool (integration)", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  describe("blocked commands", () => {
    it.for([
      "rm", "mv", "cp", "chmod", "chown", "mkdir", "rmdir", "touch", "dd",
      "tee", "sed", "awk", "bash", "sh", "cmd", "powershell", "node",
      "python", "py", "printenv", "rg", "bat", "cat", "delta", "diff",
      "head", "tail",
    ])("blocks %s", async (cmd, { expect }) => {
      assertBlocked(expect, await server.callTool("shell", { command: cmd, args: [] }));
    });
  });

  describe("path traversal in command name", () => {
    it("blocks /bin/rm", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("shell", { command: "/bin/rm", args: [] }));
    });

    it("blocks ../../bin/rm", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("shell", { command: "../../bin/rm", args: [] }));
    });
  });

  describe("empty command", () => {
    it("blocks empty command", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("shell", { command: "", args: [] }));
    });
  });

  describe("allowed commands", () => {
    it("allows ls", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("shell", { command: "ls", args: ["."] }));
    });
  });
});
