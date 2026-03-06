import { describe, it, before, after } from "node:test";
import { startServer, assertBlocked } from "./helpers.mjs";

describe("acli tool", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  for (const args of [
    ["jira", "workitem", "create"],
    ["jira", "workitem", "edit"],
    ["jira", "workitem", "delete"],
    ["jira", "workitem", "assign"],
    ["jira", "workitem", "transition"],
    ["jira", "workitem", "comment", "create"],
  ]) {
    it(`blocks ${args.join(" ")}`, async () => {
      assertBlocked(await server.callTool("acli", { args }));
    });
  }
});
