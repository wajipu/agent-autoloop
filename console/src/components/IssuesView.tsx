import { useCallback, useEffect, useState } from "react";
import { Search } from "lucide-react";

import { IssueSheet } from "@/components/IssueSheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { rel } from "@/lib/format";
import { CATEGORIES, listIssues, type Issue, type IssueCategory } from "@/lib/yunxiao";

/** 状态上色：待办类偏黄，进行中偏蓝，结束偏灰。 */
function statusColor(status: string) {
  if (/完成|关闭|已解决/.test(status)) return "bg-emerald-500";
  if (/进行|开发|处理中|测试/.test(status)) return "bg-sky-500";
  if (/拒绝|取消|挂起/.test(status)) return "bg-zinc-400";
  return "bg-amber-500";
}

export function IssuesView({ nonce }: { nonce: number }) {
  const [category, setCategory] = useState<IssueCategory>("Bug");
  const [status, setStatus] = useState("");
  const [q, setQ] = useState("");
  const [items, setItems] = useState<Issue[] | null>(null);
  const [statuses, setStatuses] = useState<string[]>([]);
  const [total, setTotal] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const answer = await listIssues(category, status, q);
      setItems(answer.items);
      setStatuses(answer.statuses);
      setTotal(answer.total);
    } catch (e) {
      setError((e as Error).message);
      setItems([]);
    }
  }, [category, status, q]);

  useEffect(() => {
    const timer = setTimeout(load, q ? 250 : 0);
    return () => clearTimeout(timer);
  }, [load, nonce, q]);

  const current = items?.find((item) => item.identifier === openId) ?? null;

  return (
    <div className="space-y-2.5">
      <div className="flex gap-1.5">
        {CATEGORIES.map(({ id, label }) => (
          <Button
            key={id}
            size="sm"
            variant={category === id ? "default" : "outline"}
            className="flex-1"
            onClick={() => {
              setCategory(id);
              setStatus("");
            }}
          >
            {label}
          </Button>
        ))}
      </div>

      <div className="relative">
        <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input className="pl-9" placeholder="搜标题或编号" value={q} onChange={(e) => setQ(e.target.value)} />
      </div>

      {statuses.length > 0 && (
        <div className="flex gap-1.5 overflow-x-auto pb-0.5">
          {["", ...statuses].map((value) => (
            <button
              key={value || "all"}
              className={cn(
                "shrink-0 rounded-full border px-3 py-1 text-xs transition-colors",
                status === value ? "border-primary bg-primary text-primary-foreground" : "bg-card text-muted-foreground",
              )}
              onClick={() => setStatus(value)}
            >
              {value || "全部"}
            </button>
          ))}
        </div>
      )}

      {error && <p className="py-8 text-center text-sm text-red-600 dark:text-red-400">{error}</p>}

      {items === null && !error && (
        <div className="space-y-2">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-[62px] rounded-xl" />
          ))}
        </div>
      )}

      {items?.map((issue) => (
        <Button
          key={issue.identifier}
          variant="ghost"
          className="h-auto w-full justify-start rounded-xl border bg-card px-3.5 py-3 shadow-sm"
          onClick={() => setOpenId(issue.identifier)}
        >
          <div className="flex w-full items-start gap-2.5 text-left">
            <span className={cn("mt-1.5 size-2 shrink-0 rounded-full", statusColor(issue.status))} />
            <div className="min-w-0 flex-1 space-y-1">
              <p className="line-clamp-2 text-sm leading-snug font-medium">{issue.subject}</p>
              <div className="flex items-center gap-2 text-xs text-muted-foreground">
                <span className="tabular-nums">{issue.serialNumber}</span>
                <span className="truncate">{issue.status}</span>
                <span className="ml-auto shrink-0">{rel(issue.gmtModified)}</span>
              </div>
            </div>
          </div>
        </Button>
      ))}

      {items && items.length === 0 && !error && (
        <p className="py-10 text-center text-sm text-muted-foreground">没有工作项</p>
      )}

      {items && items.length > 0 && (
        <p className="pt-1 pb-2 text-center text-xs text-muted-foreground">
          显示 {items.length} 条{total > items.length ? `，云效上共 ${total} 条` : ""}
        </p>
      )}

      <IssueSheet issue={current} open={openId !== null} onOpenChange={(o) => !o && setOpenId(null)} />
    </div>
  );
}
