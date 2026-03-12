import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

// --- Unit tests (mocked execShell) ---
vi.mock("../lib/exec.mjs", () => ({
  execShell: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify({ cmd: _cmd, args }) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/npm.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("npm tool (unit)", () => {
  describe("allowed subcommands", () => {
    it.for(["audit", "bin", "explain", "fund", "ls", "outdated", "root", "search", "view"])(
      "allows %s", async (sub, { expect }) => {
        assertAllowed(expect, await callMocked([sub]));
      },
    );
  });

  describe("--ignore-scripts injection", () => {
    it("injects --ignore-scripts as first arg", async ({ expect }) => {
      const result = await callMocked(["ls"]);
      const { args } = JSON.parse(result.content[0].text);
      expect(args[0]).toBe("--ignore-scripts");
    });

    it("prepends --ignore-scripts before subcommand", async ({ expect }) => {
      const result = await callMocked(["view", "zod"]);
      const { args } = JSON.parse(result.content[0].text);
      expect(args).toEqual(["--ignore-scripts", "view", "zod"]);
    });
  });
});

// --- Integration tests (real MCP server) ---
describe.concurrent("npm tool (integration)", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  describe("blocked subcommands", () => {
    it.for(
      [
        ["install"], ["ci"], ["update"], ["uninstall", "lodash"],
        ["run", "build"], ["exec", "tsc"], ["publish"], ["init"],
        ["link"], ["pack"], ["prune"], ["rebuild"], ["dedupe"],
      ].map(args => ({ name: args.join(" "), args }))
    )("blocks $name", async ({ args }, { expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args }));
    });
  });

  describe("blocked flags", () => {
    it("blocks audit --fix", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args: ["audit", "--fix"] }));
    });

    it("blocks --registry", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args: ["view", "zod", "--registry", "https://evil.com"] }));
    });

    it("blocks --registry=<url>", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args: ["view", "zod", "--registry=https://evil.com"] }));
    });

    it("blocks --no-ignore-scripts (overrides injected --ignore-scripts)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args: ["audit", "--no-ignore-scripts"] }));
    });

    it("blocks abbreviated --reg (npm expands to --registry)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args: ["view", "zod", "--reg", "https://evil.com"] }));
    });

    it("blocks abbreviated --reg=<url>", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args: ["view", "zod", "--reg=https://evil.com"] }));
    });

    it("blocks abbreviated --fi (matches --fix)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args: ["audit", "--fi"] }));
    });

    it("blocks --ignore-scripts=false (overrides injected --ignore-scripts)", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("npm", { args: ["audit", "--ignore-scripts=false"] }));
    });
  });

  describe("allowed subcommands", () => {
    it("allows ls", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("npm", { args: ["ls"] }));
    });

    it("allows explain", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("npm", { args: ["explain", "zod"] }));
    });

    it("allows view", async ({ expect }) => {
      assertNotBlocked(expect, await server.callTool("npm", { args: ["view", "zod"] }));
    });
  });
});
