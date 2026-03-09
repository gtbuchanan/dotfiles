import { describe, it, before, after } from "node:test";
import { startServer, assertBlocked } from "./helpers.mjs";

describe("az tool", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  for (const args of [
    ["devops", "project", "create"],
    ["devops", "project", "delete"],
    ["devops", "team", "create"],
    ["devops", "team", "delete"],
    ["devops", "team", "update"],
    ["devops", "wiki", "create"],
    ["devops", "wiki", "delete"],
    ["devops", "wiki", "page", "create"],
    ["devops", "wiki", "page", "update"],
    ["devops", "wiki", "page", "delete"],
    ["devops", "service-endpoint", "create"],
    ["devops", "service-endpoint", "delete"],
    ["devops", "service-endpoint", "update"],
    ["devops", "extension", "install"],
    ["devops", "extension", "uninstall"],
    ["devops", "login"],
    ["devops", "invoke"],
    ["pipelines", "create"],
    ["pipelines", "delete"],
    ["pipelines", "run"],
    ["pipelines", "update"],
    ["pipelines", "build", "queue"],
    ["pipelines", "build", "cancel"],
    ["pipelines", "build", "tag", "add"],
    ["pipelines", "build", "tag", "delete"],
    ["pipelines", "release", "create"],
    ["pipelines", "release", "definition", "create"],
    ["pipelines", "runs", "artifact", "upload"],
    ["pipelines", "runs", "artifact", "download"],
    ["pipelines", "runs", "tag", "add"],
    ["pipelines", "runs", "tag", "delete"],
    ["pipelines", "variable", "create"],
    ["pipelines", "variable", "delete"],
    ["pipelines", "variable", "update"],
    ["pipelines", "variable-group", "create"],
    ["pipelines", "variable-group", "delete"],
    ["pipelines", "variable-group", "update"],
    ["pipelines", "folder", "create"],
    ["pipelines", "folder", "delete"],
    ["pipelines", "folder", "update"],
  ]) {
    it(`blocks ${args.join(" ")}`, async () => {
      assertBlocked(await server.callTool("az", { args }));
    });
  }
});
