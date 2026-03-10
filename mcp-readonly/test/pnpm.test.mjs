import { describe, it, beforeAll, afterAll } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

describe.concurrent("pnpm tool", () => {
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
