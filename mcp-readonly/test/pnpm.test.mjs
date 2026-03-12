import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

// --- Unit tests (mocked execShell) ---
vi.mock("../lib/exec.mjs", () => ({
  execShell: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify(args) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/pnpm.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("pnpm tool (unit)", () => {
  describe("allowed subcommands", () => {
    it.for([
      { name: "audit", args: ["audit"] },
      { name: "bin", args: ["bin"] },
      { name: "licenses list", args: ["licenses", "list"] },
      { name: "list", args: ["list"] },
      { name: "outdated", args: ["outdated"] },
      { name: "root", args: ["root"] },
      { name: "search", args: ["search", "zod"] },
      { name: "store status", args: ["store", "status"] },
      { name: "why", args: ["why", "zod"] },
    ])("allows $name", async ({ args }, { expect }) => {
      assertAllowed(expect, await callMocked(args));
    });
  });
});

// --- Integration tests (real MCP server) ---
describe.concurrent("pnpm tool (integration)", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  describe("blocked subcommands", () => {
    it.for(
      [
        ["add", "lodash"], ["remove", "lodash"], ["install"],
        ["update"], ["run", "build"], ["exec", "tsc"],
        ["publish"], ["init"], ["link"], ["unlink"],
        ["store", "prune"], ["patch", "lodash"],
      ].map(args => ({ name: args.join(" "), args }))
    )("blocks $name", async ({ args }, { expect }) => {
      assertBlocked(expect, await server.callTool("pnpm", { args }));
    });
  });

  describe("blocked flags", () => {
    it("blocks audit --fix", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("pnpm", { args: ["audit", "--fix"] }));
    });

    it("blocks --registry", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("pnpm", { args: ["list", "--registry", "https://evil.com"] }));
    });

    it("blocks --registry=<url>", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("pnpm", { args: ["list", "--registry=https://evil.com"] }));
    });

    it("blocks abbreviated --reg (expands to --registry)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("pnpm", { args: ["list", "--reg", "https://evil.com"] }));
    });

    it("blocks abbreviated --reg=<url>", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("pnpm", { args: ["list", "--reg=https://evil.com"] }));
    });
  });

  describe("allowed subcommands", () => {
    it("allows list", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("pnpm", { args: ["list"] }));
    });

    it("allows why", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("pnpm", { args: ["why", "zod"] }));
    });

    it("allows licenses list", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("pnpm", { args: ["licenses", "list"] }));
    });

    it("allows store status", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("pnpm", { args: ["store", "status"] }));
    });
  });
});
