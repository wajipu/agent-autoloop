// 附件落盘：App 上传的图片/PDF 存进 HOME/uploads，取回走 masterKey 派生的能力令牌，库表零污染。
import { createHmac, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { HOME } from "./home.ts";
import { environment } from "./runtime.ts";

const UPLOADS = join(HOME, "uploads");
const ID = /^[a-f0-9]{16}$/;

const attachToken = (id: string) =>
  createHmac("sha256", environment.secret).update(`attach:${id}`).digest("hex").slice(0, 32);

const typeOf = (name: string) =>
  /\.jpe?g$/i.test(name) ? "image/jpeg"
  : /\.png$/i.test(name) ? "image/png"
  : /\.gif$/i.test(name) ? "image/gif"
  : /\.webp$/i.test(name) ? "image/webp"
  : /\.pdf$/i.test(name) ? "application/pdf"
  : "application/octet-stream";

export function saveAttachment(name: string, bytes: Uint8Array) {
  const id = randomBytes(8).toString("hex");
  mkdirSync(UPLOADS, { recursive: true });
  // 保留中文名与常规文件字符，其余压成下划线；太长只留尾部（扩展名在最后）。
  const safe =
    name.replace(/[^\w.\u4e00-\u9fa5-]+/g, "_").replace(/^[._-]+|[_-]+$/g, "").slice(-80) || "附件";
  writeFileSync(join(UPLOADS, id), bytes);
  writeFileSync(join(UPLOADS, `${id}.json`), JSON.stringify({ name: safe, at: new Date().toISOString() }));
  return { id, name: safe, token: attachToken(id) };
}

export function readAttachment(id: string) {
  if (!ID.test(id)) return undefined;
  const file = join(UPLOADS, id);
  const meta = `${file}.json`;
  if (!existsSync(file) || !existsSync(meta)) return undefined;
  try {
    const { name } = JSON.parse(readFileSync(meta, "utf8")) as { name: string };
    return { id, name, type: typeOf(name), token: attachToken(id), bytes: readFileSync(file) };
  } catch {
    return undefined;
  }
}
