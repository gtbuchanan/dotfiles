import { describe, it, before, after } from "node:test";
import { startServer, assertBlocked } from "./helpers.mjs";

describe("chezmoi tool", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  for (const args of [
    ["apply"], ["add"], ["data"], ["edit"], ["forget"], ["init"],
    ["remove"], ["re-add"], ["update"], ["destroy"], ["state", "dump"],
  ]) {
    it(`blocks ${args.join(" ")}`, async () => {
      assertBlocked(await server.callTool("chezmoi", { args }));
    });
  }
});
