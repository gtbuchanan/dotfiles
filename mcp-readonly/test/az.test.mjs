import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked, assertNotBlocked } from "./helpers.mjs";

// --- Unit tests (mocked execShell) ---
// Allowed paths hit the real `az` CLI which is slow (~1-2s per call),
// so we mock execShell to keep these fast.
// The mock encodes received args in its response so each test can
// inspect its own return value without shared mutable state.

vi.mock("../lib/exec.mjs", () => ({
  execShell: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify(args) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/az.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("az tool (unit)", () => {
  describe("allowed subcommands", () => {
    it("allows devops project list", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["devops", "project", "list"]));
    });

    it("allows pipelines list", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["pipelines", "list"]));
    });

    it("allows pipelines build show", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["pipelines", "build", "show", "--id", "1"]));
    });
  });

  describe("allowed devops invoke endpoints", () => {
    it.for([
      { area: "build", resource: "builds" },
      { area: "build", resource: "timeline" },
      { area: "build", resource: "logs" },
      { area: "build", resource: "changes" },
      { area: "build", resource: "artifacts" },
      { area: "build", resource: "leases" },
      { area: "test", resource: "runs" },
    ])("allows --area $area --resource $resource", async ({ area, resource }, { expect }) => {
      assertAllowed(expect, await callMocked(
        ["devops", "invoke", "--area", area, "--resource", resource],
      ));
    });

    it("allows with extra safe flags", async ({ expect }) => {
      assertAllowed(expect, await callMocked(
        ["devops", "invoke", "--area", "build", "--resource", "builds",
          "--route-parameters", "buildId=123", "--query-parameters", "api-version=7.0",
          "--output", "json"],
      ));
    });

    it("allows --area=value --resource=value form", async ({ expect }) => {
      assertAllowed(expect, await callMocked(
        ["devops", "invoke", "--area=build", "--resource=builds"],
      ));
    });

    it("injects --http-method GET into execShell args", async ({ expect }) => {
      const result = await callMocked(
        ["devops", "invoke", "--area", "build", "--resource", "builds"],
      );
      const args = JSON.parse(result.content[0].text);
      const methodIdx = args.indexOf("--http-method");
      expect(methodIdx, "should contain --http-method").not.toBe(-1);
      expect(args[methodIdx + 1]).toBe("GET");
    });
  });
});

// --- Integration tests (real MCP server, blocked paths never reach execShell) ---

describe.concurrent("az tool (integration)", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  const call = (args) => server.callTool("az", { args });

  describe("blocked subcommands", () => {
    it.for(
      [
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
      ].map(args => ({ name: args.join(" "), args }))
    )("blocks $name", async ({ args }, { expect }) => {
      assertBlocked(expect, await call(args));
    });
  });

  describe("blocked devops invoke flags", () => {
    it.for(
      [
        ["devops", "invoke", "--http-method", "POST", "--area", "build", "--resource", "builds"],
        ["devops", "invoke", "--http-method=DELETE", "--area", "build", "--resource", "builds"],
        ["devops", "invoke", "--in-file", "payload.json", "--area", "build", "--resource", "builds"],
        ["devops", "invoke", "--in-file=payload.json", "--area", "build", "--resource", "builds"],
        ["devops", "invoke", "--out-file", "output.json", "--area", "build", "--resource", "builds"],
        ["devops", "invoke", "--out-file=output.json", "--area", "build", "--resource", "builds"],
      ].map(args => ({ name: args.slice(2).join(" "), args }))
    )("blocks devops invoke $name", async ({ args }, { expect }) => {
      assertBlocked(expect, await call(args));
    });
  });

  describe("blocked devops invoke endpoints", () => {
    it.for(
      [
        ["devops", "invoke", "--area", "git", "--resource", "refs"],
        ["devops", "invoke", "--area", "work", "--resource", "workitems"],
        ["devops", "invoke", "--area=security", "--resource=permissions"],
        ["devops", "invoke", "--area", "build", "--resource", "definitions"],
        ["devops", "invoke"],
        ["devops", "invoke", "--area", "build"],
        ["devops", "invoke", "--resource", "builds"],
      ].map(args => ({ name: args.slice(2).join(" ") || "(bare)", args }))
    )("blocks devops invoke endpoint $name", async ({ args }, { expect }) => {
      assertBlocked(expect, await call(args));
    });
  });

  it("blocks flags before checking endpoint", async ({ expect }) => {
    assertBlocked(expect, await call(
      ["devops", "invoke", "--http-method", "POST", "--area", "git", "--resource", "refs"],
    ));
  });

  describe("blocked abbreviated flags", () => {
    it.for([
      { name: "--http-m", args: ["devops", "invoke", "--http-m", "POST", "--area", "build", "--resource", "builds"] },
      { name: "--http-metho", args: ["devops", "invoke", "--http-metho", "PATCH", "--area", "build", "--resource", "builds"] },
      { name: "--in-f", args: ["devops", "invoke", "--in-f", "payload.json", "--area", "build", "--resource", "builds"] },
      { name: "--out-f", args: ["devops", "invoke", "--out-f", "out.json", "--area", "build", "--resource", "builds"] },
      { name: "--out", args: ["devops", "invoke", "--out", "json", "--area", "build", "--resource", "builds"] },
      { name: "--o", args: ["devops", "invoke", "--o", "json", "--area", "build", "--resource", "builds"] },
      { name: "--are", args: ["devops", "invoke", "--are", "build", "--resource", "builds"] },
      { name: "--res", args: ["devops", "invoke", "--area", "build", "--res", "builds"] },
    ])("blocks abbreviated flag $name", async ({ args }, { expect }) => {
      assertBlocked(expect, await call(args));
    });
  });

  describe("blocked duplicate flags", () => {
    it.for(
      [
        ["devops", "invoke", "--area", "build", "--resource", "builds", "--area", "security"],
        ["devops", "invoke", "--area", "build", "--resource", "builds", "--resource", "permissions"],
      ].map(args => ({ name: args.slice(2).join(" "), args }))
    )("blocks duplicate flag $name", async ({ args }, { expect }) => {
      assertBlocked(expect, await call(args));
    });
  });

  it("allows devops project list", async ({ expect }) => {
    assertNotBlocked(expect, await call(["devops", "project", "list"]));
  });
});
