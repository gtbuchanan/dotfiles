import { describe, it, before, after, mock } from "node:test";
import { strict as assert } from "node:assert";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

// --- Unit tests (mocked execShell) ---
// Allowed paths hit the real `az` CLI which is slow (~1-2s per call),
// so we mock execShell to keep these fast.

let lastExecArgs;
mock.module("../lib/exec.mjs", {
  namedExports: {
    execShell: async (_cmd, args) => {
      lastExecArgs = args;
      return { content: [{ type: "text", text: "(mocked)" }] };
    },
    fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
  },
});

const { register } = await import("../tools/az.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (result) => {
  assert.ok(!result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`);
};

describe("az tool (unit)", () => {
  describe("allowed subcommands", () => {
    it("allows devops project list", async () => {
      assertAllowed(await callMocked(["devops", "project", "list"]));
    });

    it("allows pipelines list", async () => {
      assertAllowed(await callMocked(["pipelines", "list"]));
    });

    it("allows pipelines build show", async () => {
      assertAllowed(await callMocked(["pipelines", "build", "show", "--id", "1"]));
    });
  });

  describe("allowed devops invoke endpoints", () => {
    for (const [area, resource] of [
      ["build", "builds"],
      ["build", "timeline"],
      ["build", "logs"],
      ["build", "changes"],
      ["build", "artifacts"],
      ["build", "leases"],
      ["test", "runs"],
    ]) {
      it(`allows --area ${area} --resource ${resource}`, async () => {
        assertAllowed(await callMocked(
          ["devops", "invoke", "--area", area, "--resource", resource],
        ));
      });
    }

    it("allows with extra safe flags", async () => {
      assertAllowed(await callMocked(
        ["devops", "invoke", "--area", "build", "--resource", "builds",
          "--route-parameters", "buildId=123", "--query-parameters", "api-version=7.0",
          "--output", "json"],
      ));
    });

    it("allows --area=value --resource=value form", async () => {
      assertAllowed(await callMocked(
        ["devops", "invoke", "--area=build", "--resource=builds"],
      ));
    });

    it("injects --http-method GET into execShell args", async () => {
      const input = ["devops", "invoke", "--area", "build", "--resource", "builds"];
      await callMocked(input);
      assert.ok(lastExecArgs, "execShell should have been called");
      const methodIdx = lastExecArgs.indexOf("--http-method");
      assert.notEqual(methodIdx, -1, "should contain --http-method");
      assert.equal(lastExecArgs[methodIdx + 1], "GET");
    });
  });
});

// --- Integration tests (real MCP server, blocked paths never reach execShell) ---

describe("az tool (integration)", () => {
  let server;
  before(async () => { server = startServer(); await server.initialize(); });
  after(() => server.close());

  const call = (args) => server.callTool("az", { args });

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
      assertBlocked(await call(args));
    });
  }

  for (const args of [
    ["devops", "invoke", "--http-method", "POST", "--area", "build", "--resource", "builds"],
    ["devops", "invoke", "--http-method=DELETE", "--area", "build", "--resource", "builds"],
    ["devops", "invoke", "--in-file", "payload.json", "--area", "build", "--resource", "builds"],
    ["devops", "invoke", "--in-file=payload.json", "--area", "build", "--resource", "builds"],
    ["devops", "invoke", "--out-file", "output.json", "--area", "build", "--resource", "builds"],
    ["devops", "invoke", "--out-file=output.json", "--area", "build", "--resource", "builds"],
  ]) {
    it(`blocks devops invoke ${args.slice(2).join(" ")}`, async () => {
      assertBlocked(await call(args));
    });
  }

  for (const args of [
    ["devops", "invoke", "--area", "git", "--resource", "refs"],
    ["devops", "invoke", "--area", "work", "--resource", "workitems"],
    ["devops", "invoke", "--area=security", "--resource=permissions"],
    ["devops", "invoke", "--area", "build", "--resource", "definitions"],
    ["devops", "invoke"],
    ["devops", "invoke", "--area", "build"],
    ["devops", "invoke", "--resource", "builds"],
  ]) {
    it(`blocks devops invoke endpoint ${args.slice(2).join(" ") || "(bare)"}`, async () => {
      assertBlocked(await call(args));
    });
  }

  it("blocks flags before checking endpoint", async () => {
    assertBlocked(await call(
      ["devops", "invoke", "--http-method", "POST", "--area", "git", "--resource", "refs"],
    ));
  });

  for (const args of [
    ["devops", "invoke", "--http-m", "POST", "--area", "build", "--resource", "builds"],
    ["devops", "invoke", "--http-metho", "PATCH", "--area", "build", "--resource", "builds"],
    ["devops", "invoke", "--in-f", "payload.json", "--area", "build", "--resource", "builds"],
    ["devops", "invoke", "--out-f", "out.json", "--area", "build", "--resource", "builds"],
  ]) {
    it(`blocks abbreviated flag ${args[2]}`, async () => {
      assertBlocked(await call(args));
    });
  }

  for (const args of [
    ["devops", "invoke", "--area", "build", "--resource", "builds", "--area", "security"],
    ["devops", "invoke", "--area", "build", "--resource", "builds", "--resource", "permissions"],
  ]) {
    it(`blocks duplicate flag ${args.slice(2).join(" ")}`, async () => {
      assertBlocked(await call(args));
    });
  }

  for (const [abbrev, args] of [
    ["--out", ["devops", "invoke", "--out", "json", "--area", "build", "--resource", "builds"]],
    ["--o", ["devops", "invoke", "--o", "json", "--area", "build", "--resource", "builds"]],
    ["--are", ["devops", "invoke", "--are", "build", "--resource", "builds"]],
    ["--res", ["devops", "invoke", "--area", "build", "--res", "builds"]],
  ]) {
    it(`blocks abbreviated flag ${abbrev}`, async () => {
      assertBlocked(await call(args));
    });
  }

  it("allows devops project list", async () => {
    assertNotBlocked(await call(["devops", "project", "list"]));
  });
});
