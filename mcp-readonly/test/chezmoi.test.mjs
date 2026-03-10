import { describe, it, beforeAll, afterAll } from "vitest";
import { startServer, assertBlocked } from "./helpers.mjs";

describe.concurrent("chezmoi tool", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  it.for(
    [
      ["apply"], ["add"], ["data"], ["edit"], ["forget"], ["init"],
      ["remove"], ["re-add"], ["update"], ["destroy"], ["state", "dump"],
    ].map(args => ({ name: args.join(" "), args }))
  )("blocks $name", async ({ args }, { expect }) => {
    assertBlocked(expect, await server.callTool("chezmoi", { args }));
  });
});
