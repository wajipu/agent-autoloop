import { useEffect, useState } from "react";
import { toast } from "sonner";

import { StateBadge } from "@/components/StateBadge";
import { Timeline } from "@/components/Timeline";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { api } from "@/lib/api";
import { LIVE_STATES, mdhm, money, rel, tok } from "@/lib/format";
import { timeline, type Step } from "@/lib/timeline";
import type { AgentInfo, Fact, RunRow } from "@/types";

function MetaRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3 py-1 text-[13.5px]">
      <span className="shrink-0 text-muted-foreground">{label}</span>
      <span className="text-right break-all">{children}</span>
    </div>
  );
}

/** 轮次详情：底部抽屉，元信息 + 停止 + why 时间线。 */
export function RunSheet({
  run,
  agents,
  open,
  onOpenChange,
  onChanged,
}: {
  run: RunRow | null;
  agents: AgentInfo[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onChanged: () => void;
}) {
  const [steps, setSteps] = useState<Step[] | null>(null);
  const [stopping, setStopping] = useState(false);

  useEffect(() => {
    if (!open || !run) return;
    setSteps(null);
    api<Fact[]>(`/v1/runs/${run.id}/why`)
      .then((facts) => setSteps(timeline(run.id, facts)))
      .catch((e) => {
        toast.error((e as Error).message);
        setSteps([]);
      });
  }, [open, run]);

  if (!run) return null;
  const live = LIVE_STATES.includes(run.state);
  const agentName = agents.find((a) => a.id === run.agent)?.name ?? run.agent;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-h-[92dvh] max-w-2xl gap-0 overflow-y-auto rounded-t-2xl p-0">
        <div className="mx-auto mt-2 h-1 w-9 rounded-full bg-muted" />
        <SheetHeader className="mt-1 pb-2">
          <SheetTitle className="flex flex-wrap items-center gap-2 text-base">
            第 {run.id} 轮 · {run.rule}
            <StateBadge state={run.state} attempts={run.attempts} />
          </SheetTitle>
          <SheetDescription>
            {agentName} · {rel(run.createdAt)} 发起
          </SheetDescription>
        </SheetHeader>

        <div className="px-4 pb-4">
          <div className="mb-2">
            <MetaRow label="Agent">{agentName}</MetaRow>
            {run.events.length > 0 && <MetaRow label="触发事件">{run.events.map((e) => `${e.type} ${e.subject}`).join("、")}</MetaRow>}
            {run.attempts > 0 && <MetaRow label="尝试次数">{run.attempts}</MetaRow>}
            {run.usage && (
              <MetaRow label="用量">
                {tok(run.usage)} · {money(run.usage.cost)}
              </MetaRow>
            )}
            {run.link && (
              <MetaRow label="会话">
                <a className="text-primary underline" href={run.link} target="_blank" rel="noreferrer">
                  打开
                </a>
              </MetaRow>
            )}
            {run.error && (
              <MetaRow label="错误">
                <span className="text-destructive">{run.error}</span>
              </MetaRow>
            )}
            {run.finishedAt && <MetaRow label="结束于">{mdhm(run.finishedAt)}</MetaRow>}
          </div>

          {live && (
            <Button
              variant="destructive"
              className="mb-3 w-full"
              disabled={stopping}
              onClick={async () => {
                setStopping(true);
                try {
                  await api(`/v1/runs/${run.id}/cancel`, { method: "POST" });
                  toast.success("已发停止");
                  onOpenChange(false);
                  onChanged();
                } catch (e) {
                  toast.error((e as Error).message);
                } finally {
                  setStopping(false);
                }
              }}
            >
              停止这一轮
            </Button>
          )}

          <Separator className="mb-3" />
          <p className="mb-2 text-[13px] font-medium text-muted-foreground">过程时间线</p>
          {steps === null ? <Skeleton className="h-40 rounded-lg" /> : <Timeline steps={steps} />}
        </div>
      </SheetContent>
    </Sheet>
  );
}
