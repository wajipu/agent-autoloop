// 看板/回答/停轮次用 owner 密钥，提交任务用 app 事件源密钥；都只存本机 localStorage。
export const ownerKey = () => localStorage.getItem("al.owner") ?? "";
export const appKey = () => localStorage.getItem("al.app") ?? "";

export async function api<T>(path: string, init: RequestInit = {}, key: string = ownerKey()): Promise<T> {
  if (!key) throw new Error("还没填密钥：到「设置」里填 owner 密钥");
  const res = await fetch("/api" + path, {
    ...init,
    headers: {
      authorization: `Bearer ${key}`,
      ...(init.body ? { "content-type": "application/json" } : {}),
      ...(init.headers ?? {}),
    },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((body as { error?: string }).error ?? `HTTP ${res.status}`);
  return body as T;
}
