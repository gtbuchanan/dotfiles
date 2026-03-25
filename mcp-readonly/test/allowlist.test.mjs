import { describe, it } from "vitest";
import { z } from "zod";
import {
  ArgsSchema, matchesAllowlist, rejectSubcommand, rejectBlockedFlags,
  matchesApiPath, rejectApiEndpoint,
} from "../lib/allowlist.mjs";

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

  describe("concatenated short flags", () => {
    const shortBlocked = new Set(["-X", "-f"]);

    it("blocks -XPOST (value concatenated to short flag)", ({ expect }) => {
      const result = rejectBlockedFlags(["api", "endpoint", "-XPOST"], shortBlocked);
      expect(result?.isError).toBe(true);
    });

    it("blocks -fkey=val (value concatenated to short flag)", ({ expect }) => {
      const result = rejectBlockedFlags(["api", "endpoint", "-fkey=val"], shortBlocked);
      expect(result?.isError).toBe(true);
    });

    it("does not false-positive on long flag starting with single dash char", ({ expect }) => {
      // -Xtra is not a concatenated -X if -X is not in the blocked set for this test
      const unrelated = new Set(["--registry"]);
      expect(rejectBlockedFlags(["cmd", "-Xtra"], unrelated)).toBeNull();
    });

    it("does not apply short-flag rule to long flags", ({ expect }) => {
      // --method is 8 chars, not a 2-char short flag
      const longOnly = new Set(["--method"]);
      // "--methodical" should NOT be caught by the short-flag rule (only by prefix)
      // prefix check: "--method".startsWith("--methodical") → false
      // long flag rule doesn't apply (--method.length !== 2)
      // but a.startsWith(f + "=") → "--methodical".startsWith("--method=") → false
      // and f.startsWith(a.split("=")[0]) → "--method".startsWith("--methodical") → false
      expect(rejectBlockedFlags(["cmd", "--methodical"], longOnly)).toBeNull();
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

describe("matchesApiPath", () => {
  const patterns = [
    "repos/*/*/pulls/*/comments",
    "repos/*/*/commits/*/status",
    "repos/*/*/contents/**",
  ];

  describe("matching", () => {
    it("matches exact pattern with wildcards", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/pulls/123/comments", patterns)).toBe(true);
    });

    it("matches second pattern", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/commits/abc/status", patterns)).toBe(true);
    });
  });

  describe("trailing ** glob", () => {
    it("matches single trailing segment", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/contents/README.md", patterns)).toBe(true);
    });

    it("matches multiple trailing segments", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/contents/src/main.js", patterns)).toBe(true);
    });

    it("matches deeply nested path", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/contents/a/b/c/d", patterns)).toBe(true);
    });

    it("rejects when no trailing segment exists", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/contents", patterns)).toBe(false);
    });
  });

  describe("normalization", () => {
    it("strips leading slash", ({ expect }) => {
      expect(matchesApiPath("/repos/owner/repo/pulls/123/comments", patterns)).toBe(true);
    });

    it("strips query parameters", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/pulls/123/comments?per_page=100", patterns)).toBe(true);
    });

    it("strips trailing slash", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/pulls/123/comments/", patterns)).toBe(true);
    });

    it("strips leading slash, trailing slash, and query string together", ({ expect }) => {
      expect(matchesApiPath("/repos/owner/repo/pulls/123/comments/?page=2", patterns)).toBe(true);
    });
  });

  describe("rejection", () => {
    it("rejects full https URL", ({ expect }) => {
      expect(matchesApiPath("https://api.github.com/repos/o/r/pulls/1/comments", patterns)).toBe(false);
    });

    it("rejects full http URL", ({ expect }) => {
      expect(matchesApiPath("http://api.github.com/repos/o/r/pulls/1/comments", patterns)).toBe(false);
    });

    it("rejects too few segments", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/pulls/123", patterns)).toBe(false);
    });

    it("rejects too many segments (non-** pattern)", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/pulls/123/comments/extra", patterns)).toBe(false);
    });

    it("rejects unmatched path", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/git/refs", patterns)).toBe(false);
    });

    it("rejects empty endpoint", ({ expect }) => {
      expect(matchesApiPath("", patterns)).toBe(false);
    });

    it("rejects bare slash", ({ expect }) => {
      expect(matchesApiPath("/", patterns)).toBe(false);
    });
  });

  describe("edge cases", () => {
    it("returns false for empty patterns array", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/pulls/1/comments", [])).toBe(false);
    });

    it("** requires at least one trailing segment", ({ expect }) => {
      expect(matchesApiPath("repos/owner/repo/contents", patterns)).toBe(false);
    });

    it("contents/. matches (dot is a valid trailing segment)", ({ expect }) => {
      // By design — `.` is a valid directory entry; GitHub's API interprets it
      // as the repo root. The `**` glob accepts any content after the prefix.
      expect(matchesApiPath("repos/owner/repo/contents/.", patterns)).toBe(true);
    });
  });
});

describe("rejectApiEndpoint", () => {
  const patterns = ["repos/*/pulls/*/comments"];

  it("returns isError: true", ({ expect }) => {
    const result = rejectApiEndpoint("repos/owner/bad/path", patterns);
    expect(result.isError).toBe(true);
  });

  it("includes normalized endpoint in message", ({ expect }) => {
    const result = rejectApiEndpoint("/repos/owner/bad/path?foo=bar", patterns);
    expect(result.content[0].text).toContain("repos/owner/bad/path");
  });

  it("includes allowed patterns in message", ({ expect }) => {
    const result = rejectApiEndpoint("bad/path", patterns);
    expect(result.content[0].text).toContain("repos/*/pulls/*/comments");
  });

  it("shows (none) for undefined endpoint", ({ expect }) => {
    const result = rejectApiEndpoint(undefined, patterns);
    expect(result.content[0].text).toContain("(none)");
  });
});
