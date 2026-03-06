import { describe, it, before, after } from "node:test";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

describe("pnpm tool", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  describe("blocked subcommands", () => {
    for (const args of [
      ["add", "lodash"], ["remove", "lodash"], ["install"],
      ["update"], ["run", "build"], ["exec", "tsc"],
      ["publish"], ["init"], ["link"], ["unlink"],
      ["store", "prune"], ["patch", "lodash"],
    ]) {
      it(`blocks ${args.join(" ")}`, async () => {
        assertBlocked(await server.callTool("pnpm", { args }));
      });
    }
  });

  describe("blocked flags", () => {
    it("blocks audit --fix", async () => {
      assertBlocked(await server.callTool("pnpm", { args: ["audit", "--fix"] }));
    });

    it("blocks --registry", async () => {
      assertBlocked(await server.callTool("pnpm", { args: ["list", "--registry", "https://evil.com"] }));
    });

    it("blocks --registry=<url>", async () => {
      assertBlocked(await server.callTool("pnpm", { args: ["list", "--registry=https://evil.com"] }));
    });
  });

  describe("allowed subcommands", () => {
    it("allows list", async () => {
      assertNotBlocked(await server.callTool("pnpm", { args: ["list"] }));
    });

    it("allows why", async () => {
      assertNotBlocked(await server.callTool("pnpm", { args: ["why", "zod"] }));
    });

    it("allows licenses list", async () => {
      assertNotBlocked(await server.callTool("pnpm", { args: ["licenses", "list"] }));
    });

    it("allows store status", async () => {
      assertNotBlocked(await server.callTool("pnpm", { args: ["store", "status"] }));
    });
  });
});
