import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

// --- Unit tests (mocked exec) ---
vi.mock("../lib/exec.mjs", () => ({
  exec: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify({ cmd: _cmd, args }) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/git.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("git tool (unit)", () => {
  describe("--no-pager injection", () => {
    it("injects --no-pager as first arg", async ({ expect }) => {
      const result = await callMocked(["log", "--oneline", "-1"]);
      const { args } = JSON.parse(result.content[0].text);
      expect(args[0]).toBe("--no-pager");
    });

    it("preserves original args after --no-pager", async ({ expect }) => {
      const result = await callMocked(["status"]);
      const { args } = JSON.parse(result.content[0].text);
      expect(args).toEqual(["--no-pager", "status"]);
    });
  });

  describe("allowed subcommands", () => {
    it.for(["blame", "branch", "describe", "diff", "log", "ls-files", "ls-tree", "merge-base", "rev-parse", "shortlog", "show", "status"])(
      "allows %s", async (sub, { expect }) => {
        assertAllowed(expect, await callMocked([sub]));
      },
    );

    it("allows remote (bare)", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["remote"]));
    });

    it("allows stash list", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["stash", "list"]));
    });

    it("allows worktree list", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["worktree", "list"]));
    });

    it("allows reflog show", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["reflog", "show"]));
    });

    it("allows bare reflog (= reflog show)", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["reflog"]));
    });
  });
});

// --- Integration tests (real MCP server) ---
describe.concurrent("git tool (integration)", () => {
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

    it("allows diff", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["diff"] }));
    });

    it("allows diff with flags", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["diff", "--stat"] }));
    });

    it("allows show HEAD", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["show", "HEAD", "--stat"] }));
    });

    it("allows rev-parse HEAD", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["rev-parse", "HEAD"] }));
    });

    it("allows rev-parse --git-dir", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["rev-parse", "--git-dir"] }));
    });

    it("allows blame HEAD -- README.md", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["blame", "HEAD", "--", "README.md"] }));
    });

    it("allows describe", async ({ expect }) => {
      // May fail if no tags exist, but should not be blocked
      const result = await server.callTool("git", { args: ["describe", "--tags"] });
      expect(result?.isError).not.toBe(true);
    });

    it("allows merge-base HEAD HEAD", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["merge-base", "HEAD", "HEAD"] }));
    });

    it("allows shortlog -1 HEAD", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["shortlog", "-1", "HEAD"] }));
    });

    it("allows ls-files", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["ls-files"] }));
    });

    it("allows ls-files -o (--others)", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["ls-files", "-o"] }));
    });

    it("allows ls-tree HEAD", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["ls-tree", "HEAD"] }));
    });

    it("allows worktree list", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["worktree", "list"] }));
    });

    it("allows reflog show", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["reflog", "show"] }));
    });

    it("allows bare reflog", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["reflog"] }));
    });

    it("allows reflog exists HEAD", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["reflog", "exists", "HEAD"] }));
    });
  });

  describe("blocked branch mutation flags", () => {
    it.for(["-D", "-d", "-m", "-M", "-c", "-C", "--delete", "--move", "--copy", "--force", "--set-upstream-to", "--unset-upstream", "--edit-description"])(
      "blocks branch %s", async (flag, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: ["branch", flag, "test"] }));
      },
    );

    it("blocks --set-upstream-to=value (equals form)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["branch", "--set-upstream-to=origin/main", "test"] }));
    });
  });

  describe("blocked flag abbreviations", () => {
    it.for([
      { flag: "--outp", sub: "show", desc: "--output abbreviation" },
      { flag: "--del", sub: "branch", desc: "--delete abbreviation" },
      { flag: "--mov", sub: "branch", desc: "--move abbreviation" },
      { flag: "--cop", sub: "branch", desc: "--copy abbreviation" },
      { flag: "--forc", sub: "branch", desc: "--force abbreviation" },
      { flag: "--edit", sub: "branch", desc: "--edit-description abbreviation" },
    ])("blocks $desc ($flag) on $sub", async ({ flag, sub }, { expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: [sub, flag, "test"] }));
    });
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

    it("blocks stash -- list (implicit push with pathspec)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["stash", "--", "list"] }));
    });

    it.for(["push", "pop", "apply", "drop", "clear", "save", "create", "store"])(
      "blocks stash %s", async (sub, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: ["stash", sub] }));
      },
    );
  });

  describe("worktree subcommand filtering", () => {
    it("allows worktree list", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["worktree", "list"] }));
    });

    it("blocks bare worktree", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["worktree"] }));
    });

    it.for(["add", "remove", "move", "prune", "lock", "unlock", "repair"])(
      "blocks worktree %s", async (sub, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: ["worktree", sub] }));
      },
    );
  });

  describe("reflog subcommand filtering", () => {
    it("allows bare reflog (= reflog show)", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["reflog"] }));
    });

    it("allows reflog show", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["reflog", "show"] }));
    });

    it("allows reflog exists HEAD", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["reflog", "exists", "HEAD"] }));
    });

    it.for(["delete", "expire"])(
      "blocks reflog %s", async (sub, { expect }) => {
        assertBlocked(expect, await server.callTool("git", { args: ["reflog", sub] }));
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

    it("blocks diff -ao (combined short flags with -o)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["diff", "-ao", "/tmp/evil.txt"] }));
    });

    it("blocks diff -abo (combined short flags with -o at end)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["diff", "-abo", "/tmp/evil.txt"] }));
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
