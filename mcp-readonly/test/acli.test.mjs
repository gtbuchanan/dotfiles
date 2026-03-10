import { describe, it, beforeAll, afterAll } from "vitest";
import { startServer, assertBlocked } from "./helpers.mjs";

describe.concurrent("acli tool", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  it.for(
    [
      ["jira", "workitem", "create"],
      ["jira", "workitem", "edit"],
      ["jira", "workitem", "delete"],
      ["jira", "workitem", "assign"],
      ["jira", "workitem", "transition"],
      ["jira", "workitem", "comment", "create"],
    ].map(args => ({ name: args.join(" "), args }))
  )("blocks $name", async ({ args }, { expect }) => {
    assertBlocked(expect, await server.callTool("acli", { args }));
  });
});
