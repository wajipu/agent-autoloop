// 云效（Projex）工作项：走 console/server.mjs 的同源接口，AK 留在服务器那侧，浏览器不碰。
export type IssueCategory = "Bug" | "Task" | "Req";

export type Issue = {
  identifier: string;
  serialNumber: string;
  subject: string;
  status: string;
  category: IssueCategory;
  assignedTo: string;
  gmtCreate: number;
  gmtModified: number;
  url: string;
};

export type IssueDetail = Issue & { document: string; tags: string[] };

export const CATEGORIES: { id: IssueCategory; label: string }[] = [
  { id: "Bug", label: "缺陷" },
  { id: "Task", label: "任务" },
  { id: "Req", label: "需求" },
];

async function get<T>(path: string): Promise<T> {
  const res = await fetch(path, { headers: { accept: "application/json" } });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((body as { error?: string }).error ?? `HTTP ${res.status}`);
  return body as T;
}

export function listIssues(category: IssueCategory, status: string, q: string) {
  const params = new URLSearchParams({ category });
  if (status) params.set("status", status);
  if (q) params.set("q", q);
  return get<{ total: number; items: Issue[]; statuses: string[] }>(`/yunxiao/items?${params}`);
}

export function getIssue(identifier: string) {
  return get<IssueDetail>(`/yunxiao/items/${identifier}`);
}
