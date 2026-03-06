import { describe, it, before, after } from "node:test";
import { startServer, assertBlocked } from "./helpers.mjs";

describe("gh tool", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  for (const args of [
    ["issue", "create"], ["issue", "close"], ["issue", "delete"], ["issue", "edit"],
    ["pr", "create"], ["pr", "close"], ["pr", "merge"], ["pr", "edit"],
    ["repo", "create"], ["repo", "delete"],
    ["auth", "login"],
  ]) {
    it(`blocks ${args.join(" ")}`, async () => {
      assertBlocked(await server.callTool("gh", { args }));
    });
  }
});
