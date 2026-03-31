import { exec } from "../lib/exec.mjs";
import {
  ArgsSchema, matchesAllowlist, rejectSubcommand,
  rejectBlockedFlags, matchesApiPath, rejectApiEndpoint,
  normalizeApiPath,
} from "../lib/allowlist.mjs";

const GLOBAL_FLAGS = new Set(["--version", "--help", "-h"]);

const SUBCOMMANDS = new Set([
  "attestation verify",
  "cache list",
  "gist list", "gist view",
  "issue list", "issue status", "issue view",
  "label list",
  "pr checks", "pr diff", "pr list", "pr status", "pr view",
  "project field-list", "project item-list", "project list", "project view",
  "release list", "release view",
  "repo list", "repo view",
  "ruleset check", "ruleset list", "ruleset view",
  "run list", "run view",
  "search code", "search commits", "search issues", "search prs", "search repos",
  "secret list",
  "status",
  // variable get: excluded because it returns plaintext values, which may
  // contain internal URLs, hostnames, or other quasi-sensitive configuration
  // that should not be exposed to an LLM. variable list only shows names.
  "variable list",
  "workflow list", "workflow view",
]);

const API_PATHS = [
  // PR review comments (primary motivator — gh pr view --json comments misses
  // inline review comments; only returns issue/conversation comments)
  "repos/*/*/pulls/*/comments",
  "repos/*/*/pulls/*/reviews",
  "repos/*/*/pulls/*/reviews/*/comments",
  // Deployments (no gh subcommand)
  "repos/*/*/deployments",
  "repos/*/*/deployments/*/statuses",
  // Check annotations (no gh subcommand for annotations specifically)
  "repos/*/*/check-runs/*/annotations",
  // Commit statuses and checks (no gh subcommand)
  "repos/*/*/commits/*/status",
  "repos/*/*/commits/*/statuses",
  "repos/*/*/commits/*/check-runs",
  "repos/*/*/commits/*/check-suites",
  // Compare refs (base...head is a single segment)
  "repos/*/*/compare/*",
  // PR requested reviewers
  "repos/*/*/pulls/*/requested_reviewers",
  // Deployment environments
  "repos/*/*/environments",
  // Repository contents (bare = directory listing, ** = file/nested path)
  "repos/*/*/contents",
  "repos/*/*/contents/**",
];

// --method / -X: override HTTP verb to POST/PUT/DELETE/PATCH
// --input: reads arbitrary files and sends as request body
// -f / --field / -F / --raw-field: sends body fields; -F reads @file paths; imply POST
// --hostname: SSRF — redirects request (with auth token) to arbitrary host
// --verbose: dumps full request/response including Authorization header (token leak)
// -H / --header: arbitrary HTTP header injection (Accept override, API versioning, etc.)
const API_BLOCKED_FLAGS = new Set([
  "--method", "-X", "--input",
  "-f", "--field", "-F", "--raw-field",
  "--hostname", "--verbose",
  "-H", "--header",
]);

export const register = (server) =>
  server.tool(
    "gh",
    "Run read-only GitHub CLI commands (--version, --help, attestation verify, cache list, gist list/view, issue list/status/view, label list, pr checks/diff/list/status/view, project field-list/item-list/list/view, release list/view, repo list/view, ruleset check/list/view, run list/view, search code/commits/issues/prs/repos, secret list, status, variable list, workflow list/view, api GET: pulls/reviews+reviewers, deployments+environments, check-runs+suites, commits/statuses, compare, contents)",
    ArgsSchema,
    async ({ args }) => {
      const isGlobal = args.length === 1 && GLOBAL_FLAGS.has(args[0]);
      if (isGlobal) return exec("gh", args);

      if (args[0] === "api") {
        const endpoint = args[1];
        if (!endpoint || endpoint.startsWith("-"))
          return rejectApiEndpoint(endpoint, API_PATHS);
        const rejected = rejectBlockedFlags(args, API_BLOCKED_FLAGS);
        if (rejected) return rejected;
        if (!matchesApiPath(endpoint, API_PATHS))
          return rejectApiEndpoint(endpoint, API_PATHS);
        // Auto-inject raw Accept header for contents endpoints so file
        // responses return plain text instead of base64-encoded JSON.
        // Directory listings are unaffected — GitHub ignores the media type
        // for directory responses and still returns JSON.
        const [top,,, kind] = normalizeApiPath(endpoint).split("/");
        const rawAccept = top === "repos" && kind === "contents"
          ? ["-H", "Accept: application/vnd.github.raw+json"] : [];
        // Inject --method GET immediately after the endpoint, before any
        // user-supplied flags. Appending it at the end would be defeated by
        // a `--` (end-of-options marker) in user args, since everything after
        // `--` is treated as positional, making the injected flag a no-op.
        return exec("gh", ["api", endpoint, "--method", "GET", ...rawAccept, ...args.slice(2)]);
      }

      if (!matchesAllowlist(args, SUBCOMMANDS))
        return rejectSubcommand(args, SUBCOMMANDS);
      return exec("gh", args);
    },
  );
