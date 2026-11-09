import { useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { mdhm, rel } from "@/lib/format";
import { getIssue, type Issue, type IssueDetail } from "@/lib/yunxiao";

function MetaRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3 py-1 text-[13.5px]">
      <span className="shrink-0 text-muted-foreground">{label}</span>
      <span className="text-right break-all">{children}</span>
    </div>
  );
}

/** 工作项详情：底部抽屉，正文按纯文本排（云效的 document 是 Markdown，先不做渲染）。 */
export function IssueSheet({
  issue,
  open,
  onOpenChange,
}: {
  issue: Issue | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [detail, setDetail] = useState<IssueDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !issue) return;
    setDetail(null);
    setError(null);
    getIssue(issue.serialNumber)
      .then(setDetail)
      .catch((e) => setError((e as Error).message));
  }, [open, issue]);

  if (!issue) return null;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-h-[92dvh] max-w-2xl gap-0 overflow-y-auto rounded-t-2xl p-0">
        <div className="mx-auto mt-2 h-1 w-9 rounded-full bg-muted" />
        <SheetHeader className="mt-1 pb-2">
          <SheetDescription className="text-xs tabular-nums">
            {issue.serialNumber} · {issue.status} · {rel(issue.gmtModified)}更新
          </SheetDescription>
          <SheetTitle className="text-left text-[15px] leading-relaxed">{issue.subject}</SheetTitle>
        </SheetHeader>

        <div className="space-y-3 px-4 pb-6">
          <div>
            <MetaRow label="类型">{issue.category || "—"}</MetaRow>
            {issue.assignee ? <MetaRow label="负责人">{issue.assignee}</MetaRow> : null}
            <MetaRow label="创建">{mdhm(issue.gmtCreate)}</MetaRow>
            <MetaRow label="更新">{mdhm(issue.gmtModified)}</MetaRow>
            {detail?.labels?.length ? <MetaRow label="标签">{detail.labels.join("、")}</MetaRow> : null}
          </div>

          <Separator />

          {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}
          {!detail && !error && (
            <div className="space-y-2">
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-11/12" />
              <Skeleton className="h-4 w-4/5" />
            </div>
          )}
          {detail && (
            <p className="text-[13.5px] leading-relaxed whitespace-pre-wrap text-foreground/90">
              {detail.document?.trim() || "（这条工作项没有正文）"}
            </p>
          )}

          <Button variant="outline" className="w-full" asChild>
            <a href={issue.url} target="_blank" rel="noreferrer">
              在云效打开
            </a>
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}
