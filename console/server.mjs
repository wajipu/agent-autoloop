// agent-autoloop 手机控制台：静态页面 + 同源反代（/api/* → 本机 hub 28081）。
// 页面经同源拿数据，手机上不碰跨域，也不把 hub 端口直接暴露给浏览器。
// 静态文件是 React 构建产物 dist/（Mac 上 npm run build 后 scp 上来）。
// 零依赖，Node 自带模块即可跑（服务器上是 /opt/node24）。
import { createServer, request as httpRequest } from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import { extname, join, normalize } from "node:path";

const ROOT = new URL("./dist/", import.meta.url).pathname;
const HUB = { host: "127.0.0.1", port: 28081 };
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

createServer((req, res) => {
  if (req.url.startsWith("/api/")) {
    // 反代到 hub：鉴权交给 hub 自己（Bearer 在页面里，原样透传）。
    const up = httpRequest(
      { ...HUB, method: req.method, path: req.url.slice(4), headers: { ...req.headers, host: "127.0.0.1:28081" } },
      (down) => {
        res.writeHead(down.statusCode ?? 502, down.headers);
        down.pipe(res);
      },
    );
    up.on("error", () => {
      res.writeHead(502, { "content-type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ error: "hub 不可达（127.0.0.1:28081）" }));
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
