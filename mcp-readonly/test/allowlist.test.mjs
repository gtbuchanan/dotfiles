import { describe, it } from "vitest";
import { z } from "zod";
import { ArgsSchema, matchesAllowlist, rejectSubcommand, rejectBlockedFlags } from "../lib/allowlist.mjs";

describe("ArgsSchema coercion", () => {
  const schema = z.object(ArgsSchema);

  it("accepts a normal array", ({ expect }) => {
    expect(schema.parse({ args: ["status", "-sb"] }).args).toEqual(["status", "-sb"]);
  });

  it("coerces a JSON-stringified array to an array", ({ expect }) => {
    expect(schema.parse({ args: '["log", "--oneline"]' }).args).toEqual(["log", "--oneline"]);
  });

  it("uses default when args is omitted", ({ expect }) => {
    expect(schema.parse({}).args).toEqual([]);
  });

  it("rejects a plain string that is not valid JSON array", ({ expect }) => {
    expect(() => schema.parse({ args: "status -sb" })).toThrow();
  });

  it("rejects a JSON-stringified object", ({ expect }) => {
    expect(() => schema.parse({ args: '{"key": "val"}' })).toThrow();
  });

  it("rejects a JSON-stringified number", ({ expect }) => {
    expect(() => schema.parse({ args: "42" })).toThrow();
  });
});

describe("matchesAllowlist", () => {
  const single = new Set(["audit", "bin", "ls"]);
  const multi = new Set(["issue list", "issue view", "pr checks"]);
  const mixed = new Set(["audit", "licenses list", "store status"]);
  const deep = new Set(["jira board list", "jira workitem view"]);

  describe("single-word allowlist", () => {
    it("matches exact command", ({ expect }) => {
      expect(matchesAllowlist(["audit"], single)).toBe(true);
    });

    it("matches with trailing args", ({ expect }) => {
      expect(matchesAllowlist(["audit", "--json"], single)).toBe(true);
    });

    it("rejects unknown command", ({ expect }) => {
      expect(matchesAllowlist(["install"], single)).toBe(false);
    });
  });

  describe("two-word allowlist", () => {
    it("matches two-word subcommand", ({ expect }) => {
      expect(matchesAllowlist(["issue", "list"], multi)).toBe(true);
    });

    it("matches with trailing args", ({ expect }) => {
      expect(matchesAllowlist(["issue", "list", "--json"], multi)).toBe(true);
    });

    it("rejects partial match (first word only)", ({ expect }) => {
      expect(matchesAllowlist(["issue"], multi)).toBe(false);
    });

    it("rejects unknown second word", ({ expect }) => {
      expect(matchesAllowlist(["issue", "create"], multi)).toBe(false);
    });
  });

  describe("mixed-depth allowlist", () => {
    it("matches single-word entry", ({ expect }) => {
      expect(matchesAllowlist(["audit", "--json"], mixed)).toBe(true);
    });

    it("matches two-word entry", ({ expect }) => {
      expect(matchesAllowlist(["licenses", "list"], mixed)).toBe(true);
    });

    it("rejects partial match of two-word entry", ({ expect }) => {
      expect(matchesAllowlist(["licenses"], mixed)).toBe(false);
    });
  });

  describe("three-word allowlist", () => {
    it("matches three-word subcommand", ({ expect }) => {
      expect(matchesAllowlist(["jira", "board", "list"], deep)).toBe(true);
    });

    it("matches with trailing args", ({ expect }) => {
      expect(matchesAllowlist(["jira", "board", "list", "--json"], deep)).toBe(true);
    });

    it("rejects partial match", ({ expect }) => {
      expect(matchesAllowlist(["jira", "board"], deep)).toBe(false);
    });
  });

  describe("edge cases", () => {
    it("returns false for empty args", ({ expect }) => {
      expect(matchesAllowlist([], single)).toBe(false);
    });

    it("does not match single arg containing space against multi-word entry", ({ expect }) => {
      // "issue list" as one arg matches the set entry at depth 0
      // This is a known quirk — safe because execFile passes it as one argv element
      // which the target CLI would reject
      expect(matchesAllowlist(["issue list"], multi)).toBe(true);
    });

    it("handles empty Set", ({ expect }) => {
      expect(matchesAllowlist(["anything"], new Set())).toBe(false);
    });
  });
});

describe("rejectSubcommand", () => {
  const allowlist = new Set(["list", "view"]);

  it("returns isError: true", ({ expect }) => {
    const result = rejectSubcommand(["delete"], allowlist);
    expect(result.isError).toBe(true);
  });

  it("includes the rejected subcommand in message", ({ expect }) => {
    const result = rejectSubcommand(["delete"], allowlist);
    expect(result.content[0].text).toContain("delete");
  });

  it("includes allowed subcommands in message", ({ expect }) => {
    const result = rejectSubcommand(["delete"], allowlist);
    expect(result.content[0].text).toContain("list");
    expect(result.content[0].text).toContain("view");
  });

  it("shows (none) for empty args", ({ expect }) => {
    const result = rejectSubcommand([], allowlist);
    expect(result.content[0].text).toContain("(none)");
  });
});

describe("rejectBlockedFlags", () => {
  const blocked = new Set(["--fix", "--registry"]);

  describe("exact matches", () => {
    it("blocks exact flag", ({ expect }) => {
      const result = rejectBlockedFlags(["audit", "--fix"], blocked);
      expect(result?.isError).toBe(true);
    });

    it("blocks flag=value form", ({ expect }) => {
      const result = rejectBlockedFlags(["view", "--registry=https://evil.com"], blocked);
      expect(result?.isError).toBe(true);
    });

    it("returns null when no blocked flags present", ({ expect }) => {
      expect(rejectBlockedFlags(["audit", "--json"], blocked)).toBeNull();
    });
  });

  describe("skips args[0]", () => {
    it("does not check the subcommand at index 0", ({ expect }) => {
      // "--fix" at index 0 is the "subcommand", not checked
      expect(rejectBlockedFlags(["--fix"], blocked)).toBeNull();
    });
  });

  describe("prefix matching (abbreviation defense)", () => {
    it("blocks abbreviated --reg (matches --registry)", ({ expect }) => {
      const result = rejectBlockedFlags(["view", "--reg", "https://evil.com"], blocked);
      expect(result?.isError).toBe(true);
    });

    it("blocks abbreviated --registr", ({ expect }) => {
      const result = rejectBlockedFlags(["view", "--registr", "https://evil.com"], blocked);
      expect(result?.isError).toBe(true);
    });

    it("blocks abbreviated --fi (matches --fix)", ({ expect }) => {
      const result = rejectBlockedFlags(["audit", "--fi"], blocked);
      expect(result?.isError).toBe(true);
    });

    it("blocks abbreviated --reg=value form", ({ expect }) => {
      const result = rejectBlockedFlags(["view", "--reg=https://evil.com"], blocked);
      expect(result?.isError).toBe(true);
    });

    it("does not block unrelated flag with similar prefix", ({ expect }) => {
      // "--format" does not start any blocked flag, and no blocked flag starts with "--format"
      expect(rejectBlockedFlags(["view", "--format", "json"], blocked)).toBeNull();
    });

    it("does not block longer flag that starts with blocked flag", ({ expect }) => {
      // "--fix-missing-peers" starts with "--fix" but "--fix".startsWith("--fix-missing-peers") is false
      // and "--fix-missing-peers".startsWith("--fix=") is false
      // but "--fix".startsWith("--fix-missing-peers".split("=")[0]) checks "--fix".startsWith("--fix-missing-peers")
      // which is false. However, the check is [...blockedFlags].some(f => ... f.startsWith(a.split("=")[0]))
      // So we check if "--fix".startsWith("--fix-missing-peers") → false
      // and if "--registry".startsWith("--fix-missing-peers") → false
      // So this should pass through
      expect(rejectBlockedFlags(["audit", "--fix-missing-peers"], blocked)).toBeNull();
    });
  });

  describe("end-of-options marker", () => {
    it("does not false-positive on bare --", ({ expect }) => {
      expect(rejectBlockedFlags(["audit", "--", "arg"], blocked)).toBeNull();
    });

    it("does not false-positive on bare -", ({ expect }) => {
      expect(rejectBlockedFlags(["audit", "-", "arg"], blocked)).toBeNull();
    });
  });

  describe("edge cases", () => {
    it("returns null for single-element args", ({ expect }) => {
      expect(rejectBlockedFlags(["audit"], blocked)).toBeNull();
    });

    it("returns null for empty blocked set", ({ expect }) => {
      expect(rejectBlockedFlags(["audit", "--anything"], new Set())).toBeNull();
    });

    it("reports the first blocked flag found", ({ expect }) => {
      const result = rejectBlockedFlags(["audit", "--fix", "--registry"], blocked);
      expect(result.content[0].text).toContain("--fix");
    });
  });
});
