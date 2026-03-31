import { describe, it, beforeAll, afterAll, vi } from "vitest";
import { startServer, assertBlocked } from "./helpers.mjs";

// --- Unit tests (mocked exec) ---
vi.mock("../lib/exec.mjs", () => ({
  exec: async (_cmd, args) => ({
    content: [{ type: "text", text: JSON.stringify(args) }],
  }),
  fail: (msg) => ({ content: [{ type: "text", text: msg }], isError: true }),
}));

const { register } = await import("../tools/gh.mjs");

let handler;
register({ tool: (_, __, ___, fn) => { handler = fn; } });

const callMocked = (args) => handler({ args });

const assertAllowed = (expect, result) => {
  expect(result?.isError, `expected allowed, got: ${result?.content?.[0]?.text}`).toBeFalsy();
};

describe.concurrent("gh tool (unit)", () => {
  describe("allowed subcommands", () => {
    it.for([
      ["attestation", "verify"],
      ["cache", "list"],
      ["gist", "list"],
      ["gist", "view"],
      ["issue", "list"],
      ["issue", "status"],
      ["issue", "view"],
      ["label", "list"],
      ["pr", "checks"],
      ["pr", "diff"],
      ["pr", "list"],
      ["pr", "status"],
      ["pr", "view"],
      ["project", "field-list"],
      ["project", "item-list"],
      ["project", "list"],
      ["project", "view"],
      ["release", "list"],
      ["release", "view"],
      ["repo", "list"],
      ["repo", "view"],
      ["ruleset", "check"],
      ["ruleset", "list"],
      ["ruleset", "view"],
      ["run", "list"],
      ["run", "view"],
      ["search", "code"],
      ["search", "commits"],
      ["search", "issues"],
      ["search", "prs"],
      ["search", "repos"],
      ["secret", "list"],
      ["status"],
      ["variable", "list"],
      ["workflow", "list"],
      ["workflow", "view"],
    ].map(args => ({ name: args.join(" "), args })))(
      "allows $name", async ({ args }, { expect }) => {
        assertAllowed(expect, await callMocked(args));
      },
    );

    it("allows subcommand with flags", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["pr", "list", "--state", "open", "--json", "number"]));
    });
  });

  describe("global flags", () => {
    it.for([
      ["--version"],
      ["--help"],
      ["-h"],
    ].map(args => ({ name: args[0], args })))(
      "allows standalone $name", async ({ args }, { expect }) => {
        assertAllowed(expect, await callMocked(args));
      },
    );

    it("blocks --help with extra args", async ({ expect }) => {
      const result = await callMocked(["--help", "repo", "delete"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --version with extra args", async ({ expect }) => {
      const result = await callMocked(["--version", "repo", "delete"]);
      expect(result.isError).toBeTruthy();
    });
  });

  describe("api endpoint handling", () => {
    it.for([
      ["api", "repos/o/r/pulls/1/comments"],
      ["api", "repos/o/r/pulls/1/reviews"],
      ["api", "repos/o/r/pulls/1/reviews/2/comments"],
      ["api", "repos/o/r/deployments"],
      ["api", "repos/o/r/deployments/1/statuses"],
      ["api", "repos/o/r/check-runs/1/annotations"],
      ["api", "repos/o/r/commits/abc/status"],
      ["api", "repos/o/r/commits/abc/statuses"],
      ["api", "repos/o/r/commits/abc/check-runs"],
      ["api", "repos/o/r/commits/abc/check-suites"],
      ["api", "repos/o/r/compare/main...feature"],
      ["api", "repos/o/r/pulls/1/requested_reviewers"],
      ["api", "repos/o/r/environments"],
      ["api", "repos/o/r/contents"],
      ["api", "repos/o/r/contents/README.md"],
      ["api", "repos/o/r/contents/src/main.js"],
    ].map(args => ({ name: args[1], args })))(
      "allows api $name", async ({ args }, { expect }) => {
        assertAllowed(expect, await callMocked(args));
      },
    );

    it("allows api endpoint with flags", async ({ expect }) => {
      assertAllowed(expect, await callMocked([
        "api", "repos/o/r/pulls/1/comments", "--jq", ".[].id",
      ]));
    });

    it("strips leading slash from endpoint", async ({ expect }) => {
      assertAllowed(expect, await callMocked([
        "api", "/repos/o/r/pulls/1/comments",
      ]));
    });

    it("strips query string from endpoint", async ({ expect }) => {
      assertAllowed(expect, await callMocked([
        "api", "repos/o/r/pulls/1/comments?per_page=100",
      ]));
    });

    it("injects --method GET before user flags", async ({ expect }) => {
      const result = await callMocked([
        "api", "repos/o/r/pulls/1/comments", "--jq", ".[].id",
      ]);
      const args = JSON.parse(result.content[0].text);
      const methodIdx = args.indexOf("--method");
      const jqIdx = args.indexOf("--jq");
      expect(methodIdx).toBeGreaterThan(-1);
      expect(args[methodIdx + 1]).toBe("GET");
      expect(methodIdx).toBeLessThan(jqIdx);
    });

    it("--method GET is not defeated by -- end-of-options", async ({ expect }) => {
      const result = await callMocked([
        "api", "repos/o/r/pulls/1/comments", "--",
      ]);
      const args = JSON.parse(result.content[0].text);
      const methodIdx = args.indexOf("--method");
      const dashDashIdx = args.indexOf("--");
      expect(methodIdx).toBeGreaterThan(-1);
      expect(methodIdx).toBeLessThan(dashDashIdx);
    });

    it("blocks disallowed endpoint", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/git/refs"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks bare api (no endpoint)", async ({ expect }) => {
      const result = await callMocked(["api"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks api with flag-like endpoint", async ({ expect }) => {
      const result = await callMocked(["api", "--jq", ".[].id"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --method flag", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "--method", "POST"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks -X flag", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "-X", "POST"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks -XPOST (concatenated short flag)", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "-XPOST"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --input flag", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "--input", "file.json"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --hostname flag (SSRF)", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "--hostname", "evil.com"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks -f flag (body field)", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "-f", "body=text"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks -F flag (@file read)", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "-F", "body=@file.txt"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks -Fbody=@file (concatenated -F)", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "-Fbody=@/etc/passwd"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --field flag", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "--field", "body=text"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --raw-field flag", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "--raw-field", "body=text"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --verbose flag (token leak)", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "--verbose"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks -H flag (header injection)", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "-H", "Accept: text/plain"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks --header flag", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "--header", "X-Custom: val"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks -HAccept:text/plain (concatenated -H)", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments", "-HAccept:text/plain"]);
      expect(result.isError).toBeTruthy();
    });

    it("blocks full URL", async ({ expect }) => {
      const result = await callMocked(["api", "https://api.github.com/repos/o/r/pulls/1/comments"]);
      expect(result.isError).toBeTruthy();
    });

    it("allows contents without path (directory listing)", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["api", "repos/o/r/contents"]));
    });

    it("allows contents with trailing slash (directory listing)", async ({ expect }) => {
      assertAllowed(expect, await callMocked(["api", "repos/o/r/contents/"]));
    });

    it("injects raw Accept header for contents endpoint", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/contents/README.md"]);
      const args = JSON.parse(result.content[0].text);
      const hIdx = args.indexOf("-H");
      expect(hIdx).toBeGreaterThan(-1);
      expect(args[hIdx + 1]).toBe("Accept: application/vnd.github.raw+json");
    });

    it("injects raw Accept header for bare contents endpoint", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/contents"]);
      const args = JSON.parse(result.content[0].text);
      const hIdx = args.indexOf("-H");
      expect(hIdx).toBeGreaterThan(-1);
      expect(args[hIdx + 1]).toBe("Accept: application/vnd.github.raw+json");
    });

    it("does not inject Accept header for non-contents endpoint", async ({ expect }) => {
      const result = await callMocked(["api", "repos/o/r/pulls/1/comments"]);
      const args = JSON.parse(result.content[0].text);
      expect(args.indexOf("-H")).toBe(-1);
    });
  });
});

// --- Integration tests (real MCP server) ---
describe.concurrent("gh tool (integration)", () => {
  let server;
  beforeAll(async () => { server = startServer(); await server.initialize(); });
  afterAll(() => server.close());

  it.for(
    [
      ["issue", "create"], ["issue", "close"], ["issue", "delete"], ["issue", "edit"],
      ["pr", "create"], ["pr", "close"], ["pr", "merge"], ["pr", "edit"],
      ["repo", "create"], ["repo", "delete"],
      ["auth", "login"],
      ["gist", "create"], ["gist", "delete"], ["gist", "edit"],
      ["label", "create"], ["label", "delete"], ["label", "edit"],
      ["release", "create"], ["release", "delete"], ["release", "edit"],
      ["workflow", "run"], ["workflow", "enable"], ["workflow", "disable"],
      ["secret", "set"], ["secret", "delete"],
      ["variable", "get"], ["variable", "set"], ["variable", "delete"],
      ["project", "create"], ["project", "delete"], ["project", "edit"],
      ["cache", "delete"],
      ["ruleset", "create"],
    ].map(args => ({ name: args.join(" "), args }))
  )("blocks $name", async ({ args }, { expect }) => {
    assertBlocked(expect, await server.callTool("gh", { args }));
  });

  describe("blocked api endpoints", () => {
    it.for([
      ["api", "repos/o/r/git/refs"],
      ["api", "repos/o/r/pulls/1/merge"],
      ["api", "gists"],
      ["api", "user/repos"],
      ["api", "graphql"],
    ].map(args => ({ name: args[1], args })))(
      "blocks api $name", async ({ args }, { expect }) => {
        assertBlocked(expect, await server.callTool("gh", { args }));
      },
    );
  });

  describe("blocked api flags", () => {
    it.for([
      { name: "--method POST", args: ["api", "repos/o/r/pulls/1/comments", "--method", "POST"] },
      { name: "--method=DELETE", args: ["api", "repos/o/r/pulls/1/comments", "--method=DELETE"] },
      { name: "-X POST", args: ["api", "repos/o/r/pulls/1/comments", "-X", "POST"] },
      { name: "-XPOST (concatenated)", args: ["api", "repos/o/r/pulls/1/comments", "-XPOST"] },
      { name: "-XDELETE (concatenated)", args: ["api", "repos/o/r/pulls/1/comments", "-XDELETE"] },
      { name: "--input", args: ["api", "repos/o/r/pulls/1/comments", "--input", "file.json"] },
      { name: "--input=file", args: ["api", "repos/o/r/pulls/1/comments", "--input=file.json"] },
      { name: "--meth (abbreviated)", args: ["api", "repos/o/r/pulls/1/comments", "--meth", "POST"] },
      { name: "--hostname (SSRF)", args: ["api", "repos/o/r/pulls/1/comments", "--hostname", "evil.com"] },
      { name: "--hostname=evil (SSRF)", args: ["api", "repos/o/r/pulls/1/comments", "--hostname=evil.com"] },
      { name: "-f (body field)", args: ["api", "repos/o/r/pulls/1/comments", "-f", "body=text"] },
      { name: "-fkey=val (concatenated)", args: ["api", "repos/o/r/pulls/1/comments", "-fkey=val"] },
      { name: "-F (@file read)", args: ["api", "repos/o/r/pulls/1/comments", "-F", "x=@file"] },
      { name: "-Fx=@file (concatenated)", args: ["api", "repos/o/r/pulls/1/comments", "-Fx=@/etc/passwd"] },
      { name: "--field", args: ["api", "repos/o/r/pulls/1/comments", "--field", "body=text"] },
      { name: "--raw-field", args: ["api", "repos/o/r/pulls/1/comments", "--raw-field", "body=text"] },
      { name: "--verbose (token leak)", args: ["api", "repos/o/r/pulls/1/comments", "--verbose"] },
      { name: "-H (header injection)", args: ["api", "repos/o/r/pulls/1/comments", "-H", "Accept: text/plain"] },
      { name: "--header", args: ["api", "repos/o/r/pulls/1/comments", "--header", "X-Custom: val"] },
      { name: "-HAccept:... (concatenated)", args: ["api", "repos/o/r/pulls/1/comments", "-HAccept:text/plain"] },
    ])("blocks api $name", async ({ args }, { expect }) => {
      assertBlocked(expect, await server.callTool("gh", { args }));
    });
  });

  describe("blocked api full URLs", () => {
    it("blocks https:// URL", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("gh", {
        args: ["api", "https://api.github.com/repos/o/r/pulls/1/comments"],
      }));
    });

    it("blocks http:// URL", async ({ expect }) => {
      assertBlocked(expect, await server.callTool("gh", {
        args: ["api", "http://api.github.com/repos/o/r/pulls/1/comments"],
      }));
    });
  });

  it("blocks bare api", async ({ expect }) => {
    assertBlocked(expect, await server.callTool("gh", { args: ["api"] }));
  });
});
