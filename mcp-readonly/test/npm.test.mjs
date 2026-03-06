import { describe, it, before, after } from "node:test";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

describe("npm tool", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  describe("blocked subcommands", () => {
    for (const args of [
      ["install"], ["ci"], ["update"], ["uninstall", "lodash"],
      ["run", "build"], ["exec", "tsc"], ["publish"], ["init"],
      ["link"], ["pack"], ["prune"], ["rebuild"], ["dedupe"],
    ]) {
      it(`blocks ${args.join(" ")}`, async () => {
        assertBlocked(await server.callTool("npm", { args }));
      });
    }
  });

  describe("blocked flags", () => {
    it("blocks audit --fix", async () => {
      assertBlocked(await server.callTool("npm", { args: ["audit", "--fix"] }));
    });

    it("blocks --registry", async () => {
      assertBlocked(await server.callTool("npm", { args: ["view", "zod", "--registry", "https://evil.com"] }));
    });

    it("blocks --registry=<url>", async () => {
      assertBlocked(await server.callTool("npm", { args: ["view", "zod", "--registry=https://evil.com"] }));
    });
  });

  describe("allowed subcommands", () => {
    it("allows ls", async () => {
      assertNotBlocked(await server.callTool("npm", { args: ["ls"] }));
    });

    it("allows explain", async () => {
      assertNotBlocked(await server.callTool("npm", { args: ["explain", "zod"] }));
    });

    it("allows view", async () => {
      assertNotBlocked(await server.callTool("npm", { args: ["view", "zod"] }));
    });
  });
});
