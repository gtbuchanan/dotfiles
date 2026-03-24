import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { tmpdir } from "node:os";
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

const callMocked = (args, cwd) => handler({ args, cwd });

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

  describe("cwd parameter", () => {
    const toplevel = execFileSync("git", ["rev-parse", "--show-toplevel"], {
      timeout: 5_000,
    }).toString().trim();

    it("rejects cwd that is not a known worktree", async ({ expect }) => {
      const result = await callMocked(["status"], "/tmp/not-a-worktree");
      expect(result?.isError).toBe(true);
      expect(result.content[0].text).toContain("cwd rejected");
    });

    it("prepends -C for valid worktree cwd", async ({ expect }) => {
      const result = await callMocked(["status"], toplevel);
      const { args } = JSON.parse(result.content[0].text);
      expect(args[0]).toBe("--no-pager");
      expect(args[1]).toBe("-C");
      expect(args[2]).toBe(toplevel);
      expect(args[3]).toBe("status");
    });

    it("omits -C when cwd is not provided", async ({ expect }) => {
      const result = await callMocked(["status"]);
      const { args } = JSON.parse(result.content[0].text);
      expect(args).toEqual(["--no-pager", "status"]);
    });

    it("rejects path traversal from valid worktree", async ({ expect }) => {
      const result = await callMocked(["status"], toplevel + "/../../../tmp");
      expect(result?.isError).toBe(true);
      expect(result.content[0].text).toContain("cwd rejected");
    });

    it("accepts trailing slash (resolve normalizes it)", async ({ expect }) => {
      const result = await callMocked(["status"], toplevel + "/");
      const { args } = JSON.parse(result.content[0].text);
      expect(args[1]).toBe("-C");
    });

    it("treats empty string cwd as absent (no -C injected)", async ({ expect }) => {
      // Zod .min(1) rejects "" at the schema layer; handler-level falsy check is backup
      const result = await callMocked(["status"], "");
      const { args } = JSON.parse(result.content[0].text);
      expect(args).toEqual(["--no-pager", "status"]);
    });

    it.runIf(process.platform === "win32")(
      "accepts case-variant cwd on Windows",
      async ({ expect }) => {
        const swapped =
          toplevel[0] === toplevel[0].toUpperCase()
            ? toplevel[0].toLowerCase() + toplevel.slice(1)
            : toplevel[0].toUpperCase() + toplevel.slice(1);
        const result = await callMocked(["status"], swapped);
        const { args } = JSON.parse(result.content[0].text);
        expect(args[1]).toBe("-C");
      },
    );

    it.runIf(process.platform === "win32")(
      "accepts forward-slash cwd on Windows",
      async ({ expect }) => {
        const result = await callMocked(["status"], toplevel.replace(/\\/g, "/"));
        const { args } = JSON.parse(result.content[0].text);
        expect(args[1]).toBe("-C");
      },
    );
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

  describe("cwd parameter", () => {
    it("rejects cwd that is not a known worktree", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["status"], cwd: "/tmp/not-a-worktree" }));
    });

    it("accepts cwd that is the main worktree", async ({ expect }) => {
      const topResult = await server.callTool("git", { args: ["rev-parse", "--show-toplevel"] });
      const toplevel = topResult?.content?.[0]?.text?.trim();
      assertNotBlocked(expect, await server.callTool("git", { args: ["status"], cwd: toplevel }));
    });

    it("rejects empty string cwd", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: ["status"], cwd: "" }));
    });

    it("rejects path traversal from valid worktree", async ({ expect }) => {
      const topResult = await server.callTool("git", { args: ["rev-parse", "--show-toplevel"] });
      const toplevel = topResult?.content?.[0]?.text?.trim();
      assertBlocked(expect, await server.callTool("git", { args: ["status"], cwd: toplevel + "/../../../tmp" }));
    });

    it("accepts cwd with trailing slash", async ({ expect }) => {
      const topResult = await server.callTool("git", { args: ["rev-parse", "--show-toplevel"] });
      const toplevel = topResult?.content?.[0]?.text?.trim();
      assertNotBlocked(expect, await server.callTool("git", { args: ["status"], cwd: toplevel + "/" }));
    });
  });

  describe("cwd with linked worktree", () => {
    const worktreePath = join(tmpdir(), `mcp-test-wt-${process.pid}`);
    const branchName = `test-cwd-wt-${process.pid}`;

    beforeAll(() => {
      execFileSync("git", ["worktree", "add", "-b", branchName, worktreePath], {
        timeout: 10_000,
      });
    });

    afterAll(() => {
      try { execFileSync("git", ["worktree", "remove", "--force", worktreePath], { timeout: 10_000 }); } catch {}
      try { execFileSync("git", ["branch", "-D", branchName], { timeout: 5_000 }); } catch {}
    });

    it("accepts linked worktree as cwd", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("git", { args: ["status"], cwd: worktreePath }));
    });

    it("resolves HEAD from linked worktree, not main", async ({ expect }) => {
      const result = await server.callTool("git", { args: ["rev-parse", "--abbrev-ref", "HEAD"], cwd: worktreePath });
      const branch = result?.content?.[0]?.text?.trim();
      expect(branch).toBe(branchName);
    });
  });

  describe("edge cases", () => {
    it("blocks empty args", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("git", { args: [] }));
    });
  });
});
