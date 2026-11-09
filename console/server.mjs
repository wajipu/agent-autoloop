// agent-autoloop 手机控制台：静态页面 + 同源反代（/api/* → 本机 hub 28081）。
// 页面经同源拿数据，手机上不碰跨域，也不把 hub 端口直接暴露给浏览器。
// 静态文件是 React 构建产物 dist/（Mac 上 npm run build 后 scp 上来）。
// 零依赖，Node 自带模块即可跑（服务器上是 /opt/node24）。
import { createServer, request as httpRequest } from "node:http";
import { createReadStream, existsSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { extname, join, normalize } from "node:path";
import { execFile } from "node:child_process";

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
const YUNXIAO_CLI = process.env.YUNXIAO_ALIYUN_CLI ?? "/opt/homebrew/bin/aliyun";

function yunxiaoConfig() {
  return JSON.parse(readFileSync(YUNXIAO_CONFIG, "utf8"));
}

/** 调云效 OpenAPI：AK 只在本机 CLI 里，浏览器看不到。 */
function devops(action, args, region) {
  return new Promise((resolve, reject) => {
    execFile(
      YUNXIAO_CLI,
      ["devops", action, ...args, "--region", region],
      { maxBuffer: 64 * 1024 * 1024, timeout: 30000 },
      (error, stdout, stderr) => {
        if (error) {
          const text = String(stderr || stdout || error.message).replace(/\x1b\[[0-9;]*m/g, "").trim();
          reject(new Error(text.split("\n").slice(0, 3).join(" / ").slice(0, 300)));
          return;
        }
        try {
          resolve(JSON.parse(stdout));
        } catch {
          reject(new Error("云效返回的不是 JSON"));
        }
      },
    );
  });
}

const slim = (item, config) => ({
  identifier: item.identifier,
  serialNumber: item.serialNumber,
  subject: item.subject,
  status: item.status,
  category: item.categoryIdentifier,
  assignedTo: item.assignedTo,
  gmtCreate: item.gmtCreate,
  gmtModified: item.gmtModified,
  url: encodeURI(
    (config.link ?? "https://devops.aliyun.com/projex/project/{projectId}/workitem/{workitemId}")
      .replace("{projectId}", config.projectId)
      .replace("{organizationId}", config.organizationId)
      .replace("{workitemId}", item.identifier),
  ),
});

async function yunxiao(req, res, url) {
  const config = yunxiaoConfig();
  const region = config.region ?? "cn-hangzhou";
  const send = (code, body) => {
    res.writeHead(code, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
    res.end(JSON.stringify(body));
  };

  const detailMatch = url.pathname.match(/^\/yunxiao\/items\/([A-Za-z0-9]+)$/);
  try {
    if (detailMatch) {
      const body = await devops(
        "GetWorkItemInfo",
        ["--organizationId", config.organizationId, "--workitemId", detailMatch[1]],
        region,
      );
      if (body.success === false) return send(502, { error: body.errorMsg || "云效拒绝了这次查询" });
      const item = body.workitem ?? {};
      return send(200, {
        ...slim(item, config),
        document: item.document ?? "",
        tags: (item.tag ?? []).map((tag) => tag.name).filter(Boolean),
      });
    }

    if (url.pathname === "/yunxiao/items") {
      const category = url.searchParams.get("category") || "Bug";
      const status = url.searchParams.get("status") || "";
      const q = (url.searchParams.get("q") || "").trim().toLowerCase();
      const body = await devops(
        "ListWorkitems",
        [
          "--organizationId",
          config.organizationId,
          "--spaceType",
          "Project",
          "--spaceIdentifier",
          config.projectId,
          "--category",
          category,
          "--maxResults",
          "200",
        ],
        region,
      );
      if (body.success === false) return send(502, { error: body.errorMsg || "云效拒绝了这次查询" });
      let items = (body.workitems ?? []).map((item) => slim(item, config));
      if (status) items = items.filter((item) => item.status === status);
      if (q) {
        items = items.filter(
          (item) =>
            String(item.subject ?? "").toLowerCase().includes(q) ||
            String(item.serialNumber ?? "").toLowerCase().includes(q),
        );
      }
      const statuses = [...new Set((body.workitems ?? []).map((item) => item.status).filter(Boolean))];
      return send(200, { total: body.totalCount ?? items.length, items, statuses });
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
