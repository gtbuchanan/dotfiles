import { describe, it, beforeAll, afterAll } from "vitest";
import { tmpdir } from "node:os";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import { startServer } from "./helpers.mjs";

describe.concurrent("shell injection", () => {
  let server;
  let tmpDir;
  let canaryFile;

  beforeAll(async () => {
    server = startServer();
    await server.initialize();
    tmpDir = await mkdtemp(join(tmpdir(), "mcp-test-"));
    canaryFile = join(tmpDir, "canary.txt").replace(/\\/g, "/");
    await writeFile(canaryFile, "ORIGINAL", "utf8");
  });

  afterAll(async () => {
    server.close();
    await rm(tmpDir, { recursive: true });
  });

  const assertCanaryIntact = async (expect, label) => {
    const content = await readFile(canaryFile, "utf8");
    expect(content, `canary modified by ${label}`).toBe("ORIGINAL");
  };

  describe("via git args", () => {
    it.for(
      [
        ["status", ";", "rm"],
        ["status", "&&", "rm"],
        ["status", "||", "rm"],
        ["status", "|", "rm"],
        ["status", "$(rm {f})"],
        ["status", "`rm {f}`"],
      ].map(t => ({
        label: t.map(a => a.replace("{f}", "CANARY")).join(" "),
        template: t,
      }))
    )("prevents: git $label", async ({ label, template }, { expect }) => {
      const realArgs = template.map(a => a.replace("{f}", canaryFile));
      await server.callTool("git", { args: realArgs });
      await assertCanaryIntact(expect, `git ${label}`);
    });
  });

  describe("via shell args", () => {
    it.for(
      [
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
      ].map(t => ({
        label: `${t.command} ${t.args.map(a => JSON.stringify(a.replace("{f}", "CANARY"))).join(" ")}`,
        template: t,
      }))
    )("prevents: $label", async ({ label, template }, { expect }) => {
      const call = {
        command: template.command,
        args: template.args.map(a => a.replace("{f}", canaryFile)),
      };
      await server.callTool("shell", call);
      await assertCanaryIntact(expect, label);
    });
  });

  describe("blocked rm via shell tool", () => {
    it("blocks rm and preserves canary", async ({ expect }) => {
      const result = await server.callTool("shell", { command: "rm", args: [canaryFile] });
      const txt = result?.content?.[0]?.text || "";
      expect(result?.isError || txt.includes("not allowed")).toBe(true);
      await assertCanaryIntact(expect, "shell rm");
    });
  });
});
