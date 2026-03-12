import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked } from "./helpers.mjs";

// --- Unit tests (mocked exec) ---
vi.mock("../lib/exec.mjs", () => ({
  exec: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify(args) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/chezmoi.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("chezmoi tool (unit)", () => {
  describe("allowed subcommands", () => {
    it.for(["diff", "doctor", "managed", "source-path", "status", "target-path", "verify"])(
      "allows %s", async (sub, { expect }) => {
        assertAllowed(expect, await callMocked([sub]));
      },
    );

    it("allows subcommand with flags", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["status", "--include", "files"]));
    });
  });
});

// --- Integration tests (real MCP server) ---
describe.concurrent("chezmoi tool (integration)", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  it.for(
    [
      ["apply"], ["add"], ["data"], ["edit"], ["forget"], ["init"],
      ["remove"], ["re-add"], ["update"], ["destroy"], ["state", "dump"],
      ["cat-config"],
    ].map(args => ({ name: args.join(" "), args }))
  )("blocks $name", async ({ args }, { expect }) => {
    assertBlocked(expect, await server.callTool("chezmoi", { args }));
  });
});
