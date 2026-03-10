import { describe, it, beforeAll, afterAll } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

describe.concurrent("git tool", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  describe("blocked subcommands", () => {
    it.for(["push", "pull", "fetch", "checkout", "reset", "rebase", "merge", "commit", "add", "rm", "clean"])(
      "blocks %s", async (sub, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: [sub] }));
      },
    );
  });

  describe("allowed subcommands", () => {
    it("allows status", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["status"] }));
    });

    it("allows log", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["log", "--oneline", "-5"] }));
    });

    it("allows log with flags", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["log", "--all", "--oneline", "-1"] }));
    });

    it("allows branch -a", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["branch", "-a"] }));
    });
  });

  describe("blocked branch mutation flags", () => {
    it.for(["-D", "-d", "-m", "-M", "--delete", "--move", "--copy", "--force", "--set-upstream-to", "--unset-upstream"])(
      "blocks branch %s", async (flag, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: ["branch", flag, "test"] }));
      },
    );
  });

  describe("remote subcommand filtering", () => {
    it("allows bare remote (list)", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["remote"] }));
    });

    it("allows remote -v", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["remote", "-v"] }));
    });

    it("allows remote --verbose", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["remote", "--verbose"] }));
    });

    it("allows remote get-url origin", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["remote", "get-url", "origin"] }));
    });

    it("allows remote get-url --push origin", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["remote", "get-url", "--push", "origin"] }));
    });

    it("allows remote get-url --all origin", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["remote", "get-url", "--all", "origin"] }));
    });

    it.for(["show", "add", "remove", "rename", "set-url", "set-head", "prune", "update"])(
      "blocks remote %s", async (sub, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: ["remote", sub, "origin"] }));
      },
    );

    it("blocks unknown flags on remote", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["remote", "--unknown-flag"] }));
    });
  });

  describe("stash subcommand filtering", () => {
    it("allows stash list", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["stash", "list"] }));
    });

    it("allows stash show", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["stash", "show"] }));
    });

    it("blocks bare stash (implicit push)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["stash"] }));
    });

    it.for(["push", "pop", "apply", "drop", "clear", "save", "create", "store"])(
      "blocks stash %s", async (sub, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: ["stash", sub] }));
      },
    );
  });

  describe("write-flag blocking", () => {
    it.for(["log", "diff", "show"])(
      "blocks %s --output=<path>", async (sub, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: [sub, "--output=/tmp/evil.txt"] }));
      },
    );

    it("blocks log --output <path>", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["log", "--output", "/tmp/evil.txt"] }));
    });

    it("blocks diff -o", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["diff", "-o", "/tmp/evil.txt"] }));
    });

    it("blocks diff -ofile.txt (no space)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["diff", "-ofile.txt"] }));
    });

    it("blocks diff --no-index", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["diff", "--no-index", "/etc/passwd", "/dev/null"] }));
    });
  });

  describe("--no-pager injection", () => {
    it("does not hang on pager", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["log", "--oneline", "-1"] }));
    });
  });

  describe("edge cases", () => {
    it("blocks empty args", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: [] }));
    });

    it("ignores cwd parameter", async ({ expect }) => {
      const result = await server.callTool("git", { args: ["status"], cwd: "/tmp" });
      const txt = result?.content?.[0]?.text || "";
      expect(txt).not.toContain("/tmp");
    });
  });
});
