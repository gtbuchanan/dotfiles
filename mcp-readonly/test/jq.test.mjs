import { describe, it, before, after } from "node:test";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";
import { tmpdir } from "node:os";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { join } from "node:path";

describe("jq file argument blocking", () => {
  let server;
  let tmpDir;
  let canaryFile;

  before(async () => {
    server = startServer();
    await server.initialize();
    tmpDir = await mkdtemp(join(tmpdir(), "mcp-test-"));
    canaryFile = join(tmpDir, "canary.txt").replace(/\\/g, "/");
    await writeFile(canaryFile, "ORIGINAL", "utf8");
  });

  after(async () => {
    server.close();
    await rm(tmpDir, { recursive: true });
  });

  describe("allowed (no file args)", () => {
    it("allows -n empty", async () => {
      assertNotBlocked(await server.callTool("shell", { command: "jq", args: ["-n", "empty"] }));
    });

    it("allows --arg with filter only", async () => {
      assertNotBlocked(await server.callTool("shell", { command: "jq", args: ["--arg", "k", "v", "-n", ".foo"] }));
    });

    it("allows --argjson with filter only", async () => {
      assertNotBlocked(await server.callTool("shell", { command: "jq", args: ["--argjson", "k", "123", "-n", "$k"] }));
    });

    it("allows -r -n with filter only", async () => {
      assertNotBlocked(await server.callTool("shell", { command: "jq", args: ["-r", "-n", ".foo"] }));
    });
  });

  describe("blocked (file args)", () => {
    it("blocks jq . /etc/passwd", async () => {
      assertBlocked(await server.callTool("shell", { command: "jq", args: [".", "/etc/passwd"] }));
    });

    it("blocks jq . <canary>", async () => {
      assertBlocked(await server.callTool("shell", { command: "jq", args: [".", canaryFile] }));
    });

    it("blocks --arg k v . <file>", async () => {
      assertBlocked(await server.callTool("shell", { command: "jq", args: ["--arg", "k", "v", ".", canaryFile] }));
    });
  });

  describe("blocked file-reading flags", () => {
    for (const flag of ["--slurpfile", "--rawfile", "--from-file", "-f"]) {
      it(`blocks ${flag}`, async () => {
        assertBlocked(await server.callTool("shell", { command: "jq", args: [flag, "x", canaryFile] }));
      });
    }

    it("blocks -L (library path)", async () => {
      assertBlocked(await server.callTool("shell", { command: "jq", args: ["-L", "/tmp", "-n", "empty"] }));
    });
  });
});
