// Official Standard API-equivalent USD prices per million tokens, verified 2026-11-10.
// https://developers.openai.com/api/docs/pricing
// https://developers.openai.com/api/docs/models/gpt-6.1-sol
import { closeSync, globSync, openSync, readSync, statSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

const PRICES: Record<string, { input: number; cached: number; write: number; output: number }> = {
  "gpt-6.1-sol": { input: 2, cached: 0.1, write: 2.5, output: 10 },
  "gpt-6.1-terra": { input: 1, cached: 0.05, write: 1.25, output: 5 },
  "gpt-6-astra": { input: 10, cached: 1, write: 12.5, output: 50 },
  "gpt-6-luna": { input: 0.1, cached: 0.01, write: 0.125, output: 0.5 },
};
const files = new Map<string, string>();
const LIMIT = 32 * 1024 * 1024;

/** Price requests, never a session aggregate: each request has its own long-context threshold. */
export function estimateRequests(log: string, startedAt: number, complete = true): number | undefined {
  let model: string | undefined;
  let previous = "";
  let total = 0;
  let requests = 0;
  let firstTimestamp: number | undefined;
  for (const line of log.split("\n")) {
    let event: any;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }
    if (!event || typeof event !== "object") continue;
    const at = Date.parse(event.timestamp);
    if (!Number.isFinite(at)) continue;
    firstTimestamp ??= at;
    const payload = event.payload;
    if (event.type === "turn_context") model = payload?.model;
    if (event.type !== "event_msg" || payload?.type !== "token_count" || !payload.info) continue;
    const info = payload.info;
    const fingerprint = JSON.stringify(info.total_token_usage);
    if (!fingerprint || fingerprint === previous) continue;
    previous = fingerprint;
    if (at < startedAt) continue;
    const price = model && PRICES[model];
    const usage = info.last_token_usage;
    if (!price || !usage) return undefined;
    const input = usage.input_tokens;
    const cached = usage.cached_input_tokens ?? 0;
    const write = usage.cache_write_input_tokens ?? 0;
    const output = usage.output_tokens;
    if (![input, cached, write, output].every((n) => Number.isSafeInteger(n) && n >= 0) || cached + write > input)
      return undefined;
    const long = input > 272_000;
    // Output already includes reasoning. Cache writes use Standard's 30-minute reference rate.
    total +=
      (((input - cached - write) * price.input + cached * price.cached + write * price.write) * (long ? 2 : 1)) / 1e6 +
      (output * price.output * (long ? 1.5 : 1)) / 1e6;
    requests++;
  }
  // A truncated tail must still cover the entire launch, not just its last requests.
  return requests && firstTimestamp !== undefined && (complete || firstTimestamp <= startedAt) && Number.isFinite(total)
    ? total
    : undefined;
}

/** Read native local usage only after exit. No transcript or credentials leave this machine. */
export function estimateCost(session: string, startedAt: number): number | undefined {
  if (!/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(session)) return undefined;
  const home = process.env.CODEX_HOME ?? path.join(homedir(), ".codex");
  const key = `${home}:${session}`;
  try {
    let file = files.get(key);
    if (!file) {
      const matches = [...globSync(`sessions/**/rollout-*-${session}.jsonl`, { cwd: home })];
      if (matches.length !== 1) return undefined;
      file = path.join(home, matches[0]);
      files.set(key, file);
    }
    const size = statSync(file).size;
    const offset = Math.max(0, size - LIMIT);
    const buffer = Buffer.alloc(Math.min(size, LIMIT));
    const fd = openSync(file, "r");
    let bytes: number;
    try {
      bytes = readSync(fd, buffer, 0, buffer.length, offset);
    } finally {
      closeSync(fd);
    }
    let log = buffer.subarray(0, bytes).toString("utf8");
    if (offset) log = log.slice(log.indexOf("\n") + 1);
    return estimateRequests(log, startedAt, offset === 0);
  } catch {
    return undefined;
  }
}
