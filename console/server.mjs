// agent-autoloop 手机控制台：静态页面 + 同源反代（/api/* → 本机 hub 28081）。
// 页面经同源拿数据，手机上不碰跨域，也不把 hub 端口直接暴露给浏览器。
// 静态文件是 React 构建产物 dist/（Mac 上 npm run build 后 scp 上来）。
// 零依赖，Node 自带模块即可跑（服务器上是 /opt/node24）。
import { createServer, request as httpRequest } from "node:http";
import { createReadStream, existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { extname, join, normalize } from "node:path";

const ROOT = new URL("./dist/", import.meta.url).pathname;
const HUB = { host: process.env.HUB_HOST ?? "127.0.0.1", port: Number(process.env.HUB_PORT ?? 28081) };
const PORT = Number(process.env.PORT ?? 28090);
const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".webmanifest": "application/manifest+json",
  ".png": "image/png",
  ".json": "application/json; charset=utf-8",
};

const YUNXIAO_CONFIG =
  process.env.YUNXIAO_CONFIG ?? join(homedir(), ".agent-autoloop/work/yunxiao-watch/config.json");
const YUNXIAO_BASE = process.env.YUNXIAO_BASE ?? "https://openapi-rdc.aliyuncs.com";

function yunxiaoConfig() {
  return JSON.parse(readFileSync(YUNXIAO_CONFIG, "utf8"));
}

/** 令牌：环境变量优先，其次 config 指的 env 文件。浏览器永远拿不到。 */
function yunxiaoToken(config) {
  const name = config.org.tokenEnv ?? "YUNXIAO_TOKEN";
  if (process.env[name]) return process.env[name];
  const file = config.org.envFile?.replace(/^~/, homedir());
  if (!file || !existsSync(file)) return "";
  for (const line of readFileSync(file, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const cut = trimmed.indexOf("=");
    if (cut > 0 && trimmed.slice(0, cut).trim() === name) {
      return trimmed.slice(cut + 1).trim().replace(/^["']|["']$/g, "");
    }
  }
  return "";
}

async function yunxiaoApi(config, path, init = {}) {
  const res = await fetch(`${YUNXIAO_BASE}${path}`, {
    ...init,
    headers: {
      "x-yunxiao-token": yunxiaoToken(config),
      accept: "application/json",
      ...(init.body ? { "content-type": "application/json" } : {}),
    },
    signal: AbortSignal.timeout(30000),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`云效返回 ${res.status}：${text.slice(0, 160)}`);
  return JSON.parse(text);
}

function workitemUrl(config, item) {
  return encodeURI(
    (config.link ?? "https://devops.aliyun.com/projex/project/{projectId}/workitem/{workitemId}")
      .replace("{projectId}", config.projectId)
      .replace("{organizationId}", config.org.id)
      .replace("{workitemId}", item.id)
      .replace("{serialNumber}", item.serialNumber ?? ""),
  );
}

const slim = (item, config) => ({
  id: item.id,
  serialNumber: item.serialNumber,
  subject: item.subject,
  status: item.status?.name ?? "",
  category: item.workitemType?.name ?? "",
  assignee: item.assignedTo?.name ?? "",
  gmtCreate: item.gmtCreate,
  gmtModified: item.gmtModified,
  url: workitemUrl(config, item),
});

/** 富文本正文转纯文本。 */
function htmlToText(html) {
  return html
    .replace(/<(script|style)[\s\S]*?<\/\1>/gi, "")
    .replace(/<\/(p|div|li|h[1-6]|tr|article)>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

async function yunxiao(req, res, url) {
  const config = yunxiaoConfig();
  const send = (code, body) => {
    res.writeHead(code, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
    res.end(JSON.stringify(body));
  };
  const org = config.org.id;

  const detailMatch = url.pathname.match(/^\/yunxiao\/items\/([A-Za-z0-9-]+)$/);
  try {
    if (detailMatch) {
      const item = await yunxiaoApi(
        config,
        `/oapi/v1/projex/organizations/${org}/workitems/${encodeURIComponent(detailMatch[1])}`,
      );
      const raw = item.description;
      let text = typeof raw === "string" ? raw : (raw?.htmlValue ?? "");
      if (typeof text === "string" && text.trim().startsWith("{")) {
        try {
          text = JSON.parse(text)?.htmlValue ?? "";
        } catch {
          /* 不是 JSON，原样当正文 */
        }
      }
      return send(200, {
        ...slim(item, config),
        document: text ? (text.includes("<") ? htmlToText(text) : text.trim()) : "",
        labels: (item.labels ?? []).map((label) => label.name).filter(Boolean),
      });
    }

    if (url.pathname === "/yunxiao/meta") {
      let projectName = "";
      try {
        const project = await yunxiaoApi(config, `/oapi/v1/projex/organizations/${org}/projects/${config.projectId}`);
        projectName = project.name ?? "";
      } catch {
        /* 项目名拿不到不影响用 */
      }
      return send(200, {
        org: config.org.name ?? config.org.id,
        project: projectName,
        defaultCategory: config.defaultCategory ?? "Task",
      });
    }

    if (url.pathname === "/yunxiao/items") {
      const category = url.searchParams.get("category") || "Task";
      const status = url.searchParams.get("status") || "";
      const q = (url.searchParams.get("q") || "").trim().toLowerCase();
      const all = [];
      for (let page = 1; page <= 5; page += 1) {
        const batch = await yunxiaoApi(config, `/oapi/v1/projex/organizations/${org}/workitems:search`, {
          method: "POST",
          body: JSON.stringify({ category, spaceId: config.projectId, spaceType: "Project", page, perPage: 100 }),
        });
        const list = Array.isArray(batch) ? batch : [];
        all.push(...list);
        if (list.length < 100) break;
      }
      let items = all.map((item) => slim(item, config));
      const statuses = [...new Set(items.map((item) => item.status).filter(Boolean))];
      if (status) items = items.filter((item) => item.status === status);
      if (q) {
        items = items.filter(
          (item) =>
            String(item.subject ?? "").toLowerCase().includes(q) ||
            String(item.serialNumber ?? "").toLowerCase().includes(q),
        );
      }
      return send(200, { total: all.length, items, statuses });
    }
  } catch (error) {
    return send(502, { error: String(error.message ?? error) });
  }
  return send(404, { error: "not found" });
}

createServer((req, res) => {
  const url = new URL(req.url ?? "/", "http://127.0.0.1");
  if (url.pathname.startsWith("/yunxiao/")) {
    yunxiao(req, res, url);
    return;
  }
  if (req.url.startsWith("/api/")) {
    // 反代到 hub：鉴权交给 hub 自己（Bearer 在页面里，原样透传）。
    const up = httpRequest(
      { ...HUB, method: req.method, path: req.url.slice(4), headers: { ...req.headers, host: `${HUB.host}:${HUB.port}` } },
      (down) => {
        res.writeHead(down.statusCode ?? 502, down.headers);
        down.pipe(res);
      },
    );
    up.on("error", () => {
      res.writeHead(502, { "content-type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ error: `hub 不可达（${HUB.host}:${HUB.port}）` }));
    });
    req.pipe(up);
    return;
  }
  let path = decodeURIComponent((req.url ?? "/").split("?")[0]);
  if (path === "/") path = "/index.html";
  const file = join(ROOT, normalize(path));
  if (!file.startsWith(ROOT) || !existsSync(file) || !statSync(file).isFile()) {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    res.end("not found");
    return;
  }
  res.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream", "cache-control": "no-cache" });
  createReadStream(file).pipe(res);
}).listen(PORT, "0.0.0.0", () => console.log(`console on 0.0.0.0:${PORT}`));
