import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked } from "./helpers.mjs";

// --- Unit tests (mocked exec) ---
vi.mock("../lib/exec.mjs", () => ({
  exec: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify(args) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/acli.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("acli tool (unit)", () => {
  describe("allowed subcommands", () => {
    it.for([
      ["jira", "board", "list"],
      ["jira", "filter", "list"],
      ["jira", "project", "list"],
      ["jira", "sprint", "list"],
      ["jira", "workitem", "comment", "list"],
      ["jira", "workitem", "list"],
      ["jira", "workitem", "search"],
      ["jira", "workitem", "view"],
    ].map(args => ({ name: args.join(" "), args })))(
      "allows $name", async ({ args }, { expect }) => {
        assertAllowed(expect, await callMocked(args));
      },
    );

    it("allows subcommand with flags", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["jira", "workitem", "list", "--project", "FOO"]));
    });
  });
});

// --- Integration tests (real MCP server) ---
describe.concurrent("acli tool (integration)", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  it.for(
    [
      ["jira", "workitem", "create"],
      ["jira", "workitem", "edit"],
      ["jira", "workitem", "delete"],
      ["jira", "workitem", "assign"],
      ["jira", "workitem", "transition"],
      ["jira", "workitem", "comment", "create"],
    ].map(args => ({ name: args.join(" "), args }))
  )("blocks $name", async ({ args }, { expect }) => {
    assertBlocked(expect, await server.callTool("acli", { args }));
  });
});
