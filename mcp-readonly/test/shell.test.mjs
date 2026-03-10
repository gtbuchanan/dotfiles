import { describe, it, beforeAll, afterAll } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

describe.concurrent("shell tool", () => {
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
