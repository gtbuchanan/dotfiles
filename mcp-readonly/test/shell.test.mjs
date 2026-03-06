import { describe, it, before, after } from "node:test";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

describe("shell tool", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  describe("blocked commands", () => {
    for (const cmd of [
      "rm", "mv", "cp", "chmod", "chown", "mkdir", "rmdir", "touch", "dd",
      "tee", "sed", "awk", "bash", "sh", "cmd", "powershell", "node",
      "python", "py", "printenv", "rg", "bat", "cat", "delta", "diff",
      "head", "tail",
    ]) {
      it(`blocks ${cmd}`, async () => {
        assertBlocked(await server.callTool("shell", { command: cmd, args: [] }));
      });
    }
  });

  describe("path traversal in command name", () => {
    it("blocks /bin/rm", async () => {
      assertBlocked(await server.callTool("shell", { command: "/bin/rm", args: [] }));
    });

    it("blocks ../../bin/rm", async () => {
      assertBlocked(await server.callTool("shell", { command: "../../bin/rm", args: [] }));
    });
  });

  describe("empty command", () => {
    it("blocks empty command", async () => {
      assertBlocked(await server.callTool("shell", { command: "", args: [] }));
    });
  });

  describe("allowed commands", () => {
    it("allows ls", async () => {
      assertNotBlocked(await server.callTool("shell", { command: "ls", args: ["."] }));
    });
  });
});
