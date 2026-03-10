/**
 * Shared MCP test client for integration tests.
 *
 * Spawns the MCP server as a child process and communicates over JSON-RPC/stdio.
 */

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVER_PATH = join(__dirname, "..", "index.mjs");

export const startServer = () => {
  const proc = spawn("node", [SERVER_PATH], {
    stdio: ["pipe", "pipe", "pipe"],
    cwd: process.cwd(),
  });

  const rl = createInterface({ input: proc.stdout });
  const pending = new Map();
  const timers = new Map();
  let nextId = 1;

  rl.on("line", (line) => {
    try {
      const msg = JSON.parse(line);
      if (msg.id && pending.has(msg.id)) {
        clearTimeout(timers.get(msg.id));
        timers.delete(msg.id);
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      }
    } catch { /* ignore non-JSON lines */ }
  });

  const send = (method, params) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, resolve);
      const msg = JSON.stringify({ jsonrpc: "2.0", id, method, params });
      proc.stdin.write(msg + "\n");
      timers.set(id, setTimeout(() => {
        timers.delete(id);
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error(`Timeout waiting for response to ${method}`));
        }
      }, 15_000));
    });

  const initialize = () =>
    send("initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "test", version: "1.0.0" },
    });

  const callTool = async (name, args) => {
    const resp = await send("tools/call", { name, arguments: args });
    if (resp.error) return { isError: true, content: [{ type: "text", text: resp.error.message }] };
    return resp.result;
  };

  const close = () => {
    rl.close();
    proc.stdin.end();
    proc.kill();
  };

  return { initialize, callTool, close };
};

export const assertBlocked = (expect, result, message) => {
  const txt = result?.content?.[0]?.text || "";
  expect(result?.isError || txt.includes("not allowed"), message).toBe(true);
};

export const assertNotBlocked = (expect, result, message) => {
  expect(result?.isError, message).toBeFalsy();
};
