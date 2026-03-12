import { describe, it } from "vitest";
import { text, fail } from "../lib/exec.mjs";

// exec() and execShell() are integration-tested through every tool test.
// These unit tests cover the pure helper functions.

describe("text()", () => {
  it("combines stdout and stderr", ({ expect }) => {
    const result = text("hello\n", "warn\n");
    expect(result.content[0].text).toBe("hello\nwarn");
  });

  it("trims trailing whitespace", ({ expect }) => {
    const result = text("hello  \n\n", "");
    expect(result.content[0].text).toBe("hello");
  });

  it("returns (no output) for empty strings", ({ expect }) => {
    const result = text("", "");
    expect(result.content[0].text).toBe("(no output)");
  });

  it("returns (no output) for whitespace-only", ({ expect }) => {
    const result = text("  \n", "  \n");
    expect(result.content[0].text).toBe("(no output)");
  });

  it("does not set isError", ({ expect }) => {
    const result = text("ok", "");
    expect(result.isError).toBeUndefined();
  });
});

describe("fail()", () => {
  it("returns isError: true", ({ expect }) => {
    const result = fail("bad");
    expect(result.isError).toBe(true);
  });

  it("includes the message", ({ expect }) => {
    const result = fail("something went wrong");
    expect(result.content[0].text).toBe("something went wrong");
  });

  it("handles empty message", ({ expect }) => {
    const result = fail("");
    expect(result.content[0].text).toBe("");
  });
});
