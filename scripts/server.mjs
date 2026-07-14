import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";

const sessionsRoot = path.join(
  process.env.CODEX_HOME || path.join(os.homedir(), ".codex"),
  "sessions",
);

function newestJsonl(dir) {
  if (!fs.existsSync(dir)) return null;
  let newest = null;
  const pending = [dir];
  while (pending.length) {
    const current = pending.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) pending.push(fullPath);
      else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        const mtimeMs = fs.statSync(fullPath).mtimeMs;
        if (!newest || mtimeMs > newest.mtimeMs) newest = { fullPath, mtimeMs };
      }
    }
  }
  return newest?.fullPath || null;
}

function latestRateLimits(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  const lines = content.trimEnd().split(/\r?\n/);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    if (!lines[index].includes('"rate_limits"')) continue;
    try {
      const item = JSON.parse(lines[index]);
      const limits = item?.payload?.rate_limits;
      if (limits) return { limits, timestamp: item.timestamp || null };
    } catch {
      // A partially written last line is normal while Codex is running.
    }
  }
  return null;
}

function windowInfo(window) {
  if (!window) return null;
  const usedPercent = Number(window.used_percent);
  const resetsAt = Number(window.resets_at);
  return {
    used_percent: Number.isFinite(usedPercent) ? usedPercent : null,
    remaining_percent: Number.isFinite(usedPercent)
      ? Math.max(0, Math.round((100 - usedPercent) * 100) / 100)
      : null,
    window_minutes: window.window_minutes ?? null,
    resets_at: Number.isFinite(resetsAt)
      ? new Date(resetsAt * 1000).toISOString()
      : null,
  };
}

export function readQuota() {
  const filePath = newestJsonl(sessionsRoot);
  if (!filePath) {
    throw new Error(`No Codex session logs found under ${sessionsRoot}`);
  }
  const snapshot = latestRateLimits(filePath);
  if (!snapshot) {
    throw new Error("The newest Codex session has no rate-limit snapshot yet.");
  }
  const { limits, timestamp } = snapshot;
  return {
    source: "local_codex_session",
    observed_at: timestamp,
    limit_id: limits.limit_id ?? null,
    limit_name: limits.limit_name ?? null,
    primary: windowInfo(limits.primary),
    secondary: windowInfo(limits.secondary),
    credits: limits.credits
      ? {
          has_credits: limits.credits.has_credits ?? null,
          unlimited: limits.credits.unlimited ?? null,
          balance: limits.credits.balance ?? null,
        }
      : null,
    plan_type: limits.plan_type ?? null,
    rate_limit_reached_type: limits.rate_limit_reached_type ?? null,
    note: "This is the latest local snapshot written by Codex, not a billing API response.",
  };
}

function reply(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

async function handle(message) {
  if (message.method === "initialize") {
    return {
      protocolVersion: message.params?.protocolVersion || "2025-03-26",
      capabilities: { tools: {} },
      serverInfo: { name: "codex-usage-widget", version: "0.1.0" },
    };
  }
  if (message.method === "tools/list") {
    return {
      tools: [
        {
          name: "get_codex_usage",
          description: "Read the latest local Codex quota and rate-limit snapshot.",
          inputSchema: { type: "object", properties: {}, additionalProperties: false },
        },
      ],
    };
  }
  if (message.method === "tools/call") {
    if (message.params?.name !== "get_codex_usage") {
      throw new Error(`Unknown tool: ${message.params?.name}`);
    }
    const quota = readQuota();
    return {
      content: [{ type: "text", text: JSON.stringify(quota, null, 2) }],
      structuredContent: quota,
    };
  }
  return {};
}

if (process.argv.includes("--json")) {
  try {
    process.stdout.write(`${JSON.stringify(readQuota(), null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
} else {
  const input = readline.createInterface({ input: process.stdin });
  input.on("line", async (line) => {
    let message;
    try {
      message = JSON.parse(line);
      if (!Object.hasOwn(message, "id")) return;
      const result = await handle(message);
      reply({ jsonrpc: "2.0", id: message.id, result });
    } catch (error) {
      reply({
        jsonrpc: "2.0",
        id: message?.id ?? null,
        error: { code: -32603, message: error.message },
      });
    }
  });
}

