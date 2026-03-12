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
      ["issue", "list"],
      ["issue", "view"],
      ["pr", "checks"],
      ["pr", "diff"],
      ["pr", "list"],
      ["pr", "status"],
      ["pr", "view"],
      ["repo", "view"],
      ["run", "list"],
      ["run", "view"],
      ["search", "code"],
      ["search", "commits"],
      ["search", "issues"],
      ["search", "prs"],
      ["search", "repos"],
    ].map(args => ({ name: args.join(" "), args })))(
      "allows $name", async ({ args }, { expect }) => {
        assertAllowed(expect, await callMocked(args));
      },
    );

    it("allows subcommand with flags", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["pr", "list", "--state", "open", "--json", "number"]));
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
    ].map(args => ({ name: args.join(" "), args }))
  )("blocks $name", async ({ args }, { expect }) => {
    assertBlocked(expect, await server.callTool("gh", { args }));
  });
});
