import { describe, it, beforeAll, afterAll } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

describe.concurrent("npm tool", () => {
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
