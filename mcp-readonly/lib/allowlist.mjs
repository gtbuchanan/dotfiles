import { z } from "zod";
import { fail } from "./exec.mjs";

export const ArgsSchema = {
  args: z.array(z.string()).describe("Command arguments"),
};

const maxDepthOf = (allowlist) =>
  Math.max(...[...allowlist].map((s) => s.split(" ").length));

export const matchesAllowlist = (args, allowlist) => {
  const depth = maxDepthOf(allowlist);
  let key = "";
  for (let i = 0; i < Math.min(args.length, depth); i++) {
    key = i === 0 ? args[0] : key + " " + args[i];
    if (allowlist.has(key)) return true;
  }
  return false;
};

export const rejectSubcommand = (args, allowlist) => {
  const depth = maxDepthOf(allowlist);
  return fail(`Subcommand not allowed: ${args.slice(0, depth).join(" ")}. Allowed: ${[...allowlist].join(", ")}`);
};

export const rejectBlockedFlags = (args, blockedFlags) => {
  const flag = args.slice(1).find((a) =>
    blockedFlags.has(a) || [...blockedFlags].some((f) => a.startsWith(f + "=")),
  );
  return flag ? fail(`Flag not allowed: ${flag}`) : null;
};
