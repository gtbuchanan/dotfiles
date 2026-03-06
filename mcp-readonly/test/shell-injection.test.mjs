import { describe, it, before, after } from "node:test";
import { strict as assert } from "node:assert";
import { tmpdir } from "node:os";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { startServer } from "./helpers.mjs";

describe("shell injection", () => {
  let server;
  let tmpDir;
  let canaryFile;

  before(async () => {
    server = startServer();
    await server.initialize();
    tmpDir = await mkdtemp(join(tmpdir(), "mcp-test-"));
    canaryFile = join(tmpDir, "canary.txt").replace(/\\/g, "/");
    await writeFile(canaryFile, "ORIGINAL", "utf8");
  });

  after(async () => {
    server.close();
    await rm(tmpDir, { recursive: true });
  });

  const assertCanaryIntact = async (label) => {
    const content = await readFile(canaryFile, "utf8");
    assert.equal(content, "ORIGINAL", `canary modified by ${label}`);
  };

  describe("via git args", () => {
    const injections = () => [
      ["status", ";", "rm"],
      ["status", "&&", "rm"],
      ["status", "||", "rm"],
      ["status", "|", "rm"],
      ["status", "$(rm {f})"],
      ["status", "`rm {f}`"],
    ];

    for (const template of injections()) {
      const args = template.map((a) => a.replace("{f}", "CANARY"));
      it(`prevents: git ${args.join(" ")}`, async () => {
        const realArgs = template.map((a) => a.replace("{f}", canaryFile));
        await server.callTool("git", { args: realArgs });
        await assertCanaryIntact(`git ${args.join(" ")}`);
      });
    }
  });

  describe("via shell args", () => {
    const injections = () => [
      { command: "ls", args: ["; rm {f}"] },
      { command: "ls", args: ["&& rm {f}"] },
      { command: "ls", args: ["| rm {f}"] },
      { command: "ls", args: ["$(rm {f})"] },
      { command: "ls", args: ["`rm {f}`"] },
      { command: "ls", args: [";", "rm", "{f}"] },
      { command: "ls", args: ["&&", "rm", "{f}"] },
      { command: "ls", args: ["||", "rm", "{f}"] },
      { command: "ls", args: ["|", "rm", "{f}"] },
      { command: "ls", args: ['" ; rm {f} #'] },
      { command: "ls", args: ["' ; rm {f} #"] },
      { command: "ls", args: ["\nrm {f}"] },
      { command: "ls", args: ["\r\nrm {f}"] },
      { command: "ls", args: ["\0rm {f}"] },
    ];

    for (const template of injections()) {
      const label = `${template.command} ${template.args.map((a) => JSON.stringify(a.replace("{f}", "CANARY"))).join(" ")}`;
      it(`prevents: ${label}`, async () => {
        const call = {
          command: template.command,
          args: template.args.map((a) => a.replace("{f}", canaryFile)),
        };
        await server.callTool("shell", call);
        await assertCanaryIntact(label);
      });
    }
  });

  describe("blocked rm via shell tool", () => {
    it("blocks rm and preserves canary", async () => {
      const result = await server.callTool("shell", { command: "rm", args: [canaryFile] });
      const txt = result?.content?.[0]?.text || "";
      assert.ok(result?.isError || txt.includes("not allowed"));
      await assertCanaryIntact("shell rm");
    });
  });
});
