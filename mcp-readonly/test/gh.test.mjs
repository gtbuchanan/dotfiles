import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked } from "./helpers.mjs";

// --- Unit tests (mocked exec) ---
vi.mock("../lib/exec.mjs", () => ({
  exec: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify(args) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/gh.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("gh tool (unit)", () => {
  describe("allowed subcommands", () => {
    it.for([
      ["attestation", "verify"],
      ["cache", "list"],
      ["gist", "list"],
      ["gist", "view"],
      ["issue", "list"],
      ["issue", "status"],
      ["issue", "view"],
      ["label", "list"],
      ["pr", "checks"],
      ["pr", "diff"],
      ["pr", "list"],
      ["pr", "status"],
      ["pr", "view"],
      ["project", "field-list"],
      ["project", "item-list"],
      ["project", "list"],
      ["project", "view"],
      ["release", "list"],
      ["release", "view"],
      ["repo", "list"],
      ["repo", "view"],
      ["ruleset", "check"],
      ["ruleset", "list"],
      ["ruleset", "view"],
      ["run", "list"],
      ["run", "view"],
      ["search", "code"],
      ["search", "commits"],
      ["search", "issues"],
      ["search", "prs"],
      ["search", "repos"],
      ["secret", "list"],
      ["status"],
      ["variable", "list"],
      ["workflow", "list"],
      ["workflow", "view"],
    ].map(args => ({ name: args.join(" "), args })))(
      "allows $name", async ({ args }, { expect }) => {
        assertAllowed(expect, await callMocked(args));
      },
    );

    it("allows subcommand with flags", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["pr", "list", "--state", "open", "--json", "number"]));
    });
  });

  describe("global flags", () => {
    it.for([
      ["--version"],
      ["--help"],
      ["-h"],
    ].map(args => ({ name: args[0], args })))(
      "allows standalone $name", async ({ args }, { expect }) => {
        assertAllowed(expect, await callMocked(args));
      },
    );

    it("blocks --help with extra args", async ({ expect }) => {
      const result = await callMocked(["--help", "repo", "delete"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --version with extra args", async ({ expect }) => {
      const result = await callMocked(["--version", "repo", "delete"]);
      expect(result.isError).toBeTruthy();
    });
  });
});

// --- Integration tests (real MCP server) ---
describe.concurrent("gh tool (integration)", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  it.for(
    [
      ["issue", "create"], ["issue", "close"], ["issue", "delete"], ["issue", "edit"],
      ["pr", "create"], ["pr", "close"], ["pr", "merge"], ["pr", "edit"],
      ["repo", "create"], ["repo", "delete"],
      ["auth", "login"],
      ["gist", "create"], ["gist", "delete"], ["gist", "edit"],
      ["label", "create"], ["label", "delete"], ["label", "edit"],
      ["release", "create"], ["release", "delete"], ["release", "edit"],
      ["workflow", "run"], ["workflow", "enable"], ["workflow", "disable"],
      ["secret", "set"], ["secret", "delete"],
      ["variable", "get"], ["variable", "set"], ["variable", "delete"],
      ["project", "create"], ["project", "delete"], ["project", "edit"],
      ["cache", "delete"],
      ["ruleset", "create"],
    ].map(args => ({ name: args.join(" "), args }))
  )("blocks $name", async ({ args }, { expect }) => {
    assertBlocked(expect, await server.callTool("gh", { args }));
  });
});
