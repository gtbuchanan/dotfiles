import { describe, it, beforeAll, afterAll } from "vitest";
import { startServer, assertBlocked } from "./helpers.mjs";

describe.concurrent("gh tool", () => {
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
