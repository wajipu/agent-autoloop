const pad = (n: number) => String(n).padStart(2, "0");

export const hm = (v: string | number) => {
  const d = new Date(v);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

export const hms = (v: string | number) => {
  const d = new Date(v);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
};

export const mdhm = (v: string | number) => {
  const d = new Date(v);
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
};

export function rel(v: string | number | null | undefined) {
  if (!v) return "";
  const gap = Date.now() - new Date(v).getTime();
  if (gap < 60e3) return "刚刚";
  if (gap < 3600e3) return `${Math.floor(gap / 60e3)} 分钟前`;
  if (gap < 86400e3) return `${Math.floor(gap / 3600e3)} 小时前`;
  return `${Math.floor(gap / 86400e3)} 天前`;
}

export const money = (c: number | undefined | null) => `$${Number(c ?? 0).toFixed(2)}`;

export const tok = (u: { input: number; output: number } | null | undefined) =>
  u ? `${Math.round((u.input + u.output) / 1000)}k` : "—";

/** run.state 存的是库里的原始值（claimed=在跑），转成给人看的词。 */
export const stateOf = (s: string) =>
  ({ claimed: "在跑", queued: "排队", unknown: "未知", done: "完成", cancelled: "已停止", nothing: "无事" })[s] ?? s;

export const LIVE_STATES = ["claimed", "queued", "unknown"];
