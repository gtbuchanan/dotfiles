import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

const EXEC_OPTS = { timeout: 10_000, maxBuffer: 2 * 1024 * 1024 };

const IS_WIN = process.platform === "win32";

export const text = (stdout, stderr) => ({
  content: [{ type: "text", text: (stdout + stderr).trimEnd() || "(no output)" }],
});

export const fail = (msg) => ({
  content: [{ type: "text", text: msg }],
  isError: true,
});

export const exec = async (cmd, args) => {
  try {
    const { stdout, stderr } = await run(cmd, args, EXEC_OPTS);
    return text(stdout, stderr);
  } catch (err) {
    if (err.stdout || err.stderr) return text(err.stdout || "", err.stderr || "");
    return fail(err.message);
  }
};

export const execShell = async (cmd, args) => {
  if (!IS_WIN) return exec(cmd, args);
  return exec("bash", ["-c", 'exec "$@"', "--", cmd, ...args]);
};
