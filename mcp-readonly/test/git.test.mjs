import { describe, it, before, after } from "node:test";
import { strict as assert } from "node:assert";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

describe("git tool", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  describe("blocked subcommands", () => {
    for (const sub of ["push", "pull", "fetch", "checkout", "reset", "rebase", "merge", "commit", "add", "rm", "clean", "stash"]) {
      it(`blocks ${sub}`, async () => {
        assertBlocked(await server.callTool("git", { args: [sub] }));
      });
    }
  });

  describe("allowed subcommands", () => {
    it("allows status", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["status"] }));
    });

    it("allows log", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["log", "--oneline", "-5"] }));
    });

    it("allows log with flags", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["log", "--all", "--oneline", "-1"] }));
    });

    it("allows branch -a", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["branch", "-a"] }));
    });
  });

  describe("blocked branch mutation flags", () => {
    for (const flag of ["-D", "-d", "-m", "-M", "--delete", "--move", "--copy", "--force", "--set-upstream-to", "--unset-upstream"]) {
      it(`blocks branch ${flag}`, async () => {
        assertBlocked(await server.callTool("git", { args: ["branch", flag, "test"] }));
      });
    }
  });

  describe("remote subcommand filtering", () => {
    it("allows bare remote (list)", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["remote"] }));
    });

    it("allows remote -v", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["remote", "-v"] }));
    });

    it("allows remote --verbose", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["remote", "--verbose"] }));
    });

    it("allows remote get-url origin", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["remote", "get-url", "origin"] }));
    });

    it("allows remote get-url --push origin", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["remote", "get-url", "--push", "origin"] }));
    });

    it("allows remote get-url --all origin", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["remote", "get-url", "--all", "origin"] }));
    });

    for (const sub of ["show", "add", "remove", "rename", "set-url", "set-head", "prune", "update"]) {
      it(`blocks remote ${sub}`, async () => {
        assertBlocked(await server.callTool("git", { args: ["remote", sub, "origin"] }));
      });
    }

    it("blocks unknown flags on remote", async () => {
      assertBlocked(await server.callTool("git", { args: ["remote", "--unknown-flag"] }));
    });
  });

  describe("write-flag blocking", () => {
    for (const sub of ["log", "diff", "show"]) {
      it(`blocks ${sub} --output=<path>`, async () => {
        assertBlocked(await server.callTool("git", { args: [sub, "--output=/tmp/evil.txt"] }));
      });
    }

    it("blocks log --output <path>", async () => {
      assertBlocked(await server.callTool("git", { args: ["log", "--output", "/tmp/evil.txt"] }));
    });

    it("blocks diff -o", async () => {
      assertBlocked(await server.callTool("git", { args: ["diff", "-o", "/tmp/evil.txt"] }));
    });

    it("blocks diff -ofile.txt (no space)", async () => {
      assertBlocked(await server.callTool("git", { args: ["diff", "-ofile.txt"] }));
    });

    it("blocks diff --no-index", async () => {
      assertBlocked(await server.callTool("git", { args: ["diff", "--no-index", "/etc/passwd", "/dev/null"] }));
    });
  });

  describe("--no-pager injection", () => {
    it("does not hang on pager", async () => {
      assertNotBlocked(await server.callTool("git", { args: ["log", "--oneline", "-1"] }));
    });
  });

  describe("edge cases", () => {
    it("blocks empty args", async () => {
      assertBlocked(await server.callTool("git", { args: [] }));
    });

    it("ignores cwd parameter", async () => {
      const result = await server.callTool("git", { args: ["status"], cwd: "/tmp" });
      const txt = result?.content?.[0]?.text || "";
      assert.ok(!txt.includes("/tmp"));
    });
  });
});
