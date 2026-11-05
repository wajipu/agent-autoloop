import { useCallback, useEffect, useState } from "react";
import { Settings } from "lucide-react";

import { AskCard } from "@/components/AskCard";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { api, ownerKey } from "@/lib/api";
import { money, rel, tok } from "@/lib/format";
import type { HubState } from "@/types";
import { cn } from "@/lib/utils";

const Dot = ({ on }: { on: boolean }) => (
  <span
    className={cn(
      "inline-block size-2 rounded-full",
      on ? "bg-emerald-500 shadow-[0_0_0_3px] shadow-emerald-500/20" : "bg-zinc-400 dark:bg-zinc-600",
    )}
  />
);

function Tile({ value, label, tone }: { value: string | number; label: string; tone?: string }) {
  return (
    <Card className="gap-0 py-3">
      <CardContent className="px-3.5">
        <div className={cn("text-[22px] leading-tight font-semibold tabular-nums", tone)}>{value}</div>
        <div className="text-xs text-muted-foreground">{label}</div>
      </CardContent>
    </Card>
  );
}

export function NoKeyCard() {
  return (
    <Card className="items-center py-10">
      <CardContent className="flex flex-col items-center gap-3 text-center">
        <p className="text-sm text-muted-foreground">这个页签要 owner 密钥</p>
        <Button onClick={() => window.dispatchEvent(new CustomEvent("al-go-settings"))}>
          <Settings /> 去设置
        </Button>
      </CardContent>
    </Card>
  );
}

export function OverviewView({ nonce, onState }: { nonce: number; onState: (st: HubState) => void }) {
  const [st, setSt] = useState<HubState | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!ownerKey()) return;
    try {
      const data = await api<HubState>("/v1/state");
      setSt(data);
      setError(null);
      onState(data);
    } catch (e) {
      setError((e as Error).message);
    }
  }, [onState]);

  useEffect(() => {
    load();
  }, [load, nonce]);

  if (!ownerKey()) return <NoKeyCard />;
  if (error)
    return (
      <Card className="py-10">
        <CardContent className="text-center text-sm text-muted-foreground">{error}</CardContent>
      </Card>
    );
  if (!st)
    return (
      <div className="grid grid-cols-3 gap-2.5">
        {Array.from({ length: 6 }).map((_, i) => (
          <Skeleton key={i} className="h-[68px] rounded-xl" />
        ))}
      </div>
    );

  const t = st.totals;
  return (
    <div className="space-y-2.5">
      <div className="grid grid-cols-3 gap-2.5">
        <Tile value={t.running} label="在跑" tone="text-sky-600 dark:text-sky-400" />
        <Tile value={t.queued} label="排队" />
        <Tile value={t.attention} label="等你拍板" tone={t.attention > 0 ? "text-amber-600 dark:text-amber-400" : undefined} />
        <Tile value={t.doneToday} label="今日完成" tone="text-emerald-600 dark:text-emerald-400" />
        <Tile value={money(t.usage.cost)} label="累计花费" />
        <Tile value={tok(t.usage)} label="累计 token" />
      </div>

      <Card className="gap-0 py-3">
        <CardHeader className="pb-1">
          <CardTitle className="text-[13px] font-medium text-muted-foreground">等你拍板 · {st.cards.length}</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2.5">
          {st.cards.length ? st.cards.map((c) => <AskCard key={c.id} card={c} onDone={load} />) : (
            <p className="py-3 text-center text-sm text-muted-foreground">没有等你的卡片</p>
          )}
        </CardContent>
      </Card>

      <Card className="gap-0 py-3">
        <CardHeader className="pb-1">
          <CardTitle className="text-[13px] font-medium text-muted-foreground">Agent</CardTitle>
        </CardHeader>
        <CardContent className="divide-y divide-dashed divide-border">
          {st.agents.map((a) => (
            <div key={a.id} className="flex items-baseline justify-between gap-2 py-2 first:pt-0 last:pb-0">
              <span className="flex items-center gap-2 text-sm font-medium">
                <Dot on={a.online} />
                {a.name}
                <span className="text-xs font-normal text-muted-foreground">{a.worker}</span>
              </span>
              <span className="text-xs text-muted-foreground">
                {a.use} · {rel(a.seenAt)}
              </span>
            </div>
          ))}
        </CardContent>
      </Card>

      <Card className="gap-0 py-3">
        <CardHeader className="pb-1">
          <CardTitle className="text-[13px] font-medium text-muted-foreground">通道</CardTitle>
        </CardHeader>
        <CardContent className="divide-y divide-dashed divide-border">
          {st.channels.map((c) => (
            <div key={c.id} className="flex items-baseline justify-between gap-2 py-2 first:pt-0 last:pb-0">
              <span className="flex items-center gap-2 text-sm font-medium">
                <Dot on={c.online} />
                {c.name}
              </span>
              <span className="text-xs text-muted-foreground">{rel(c.seenAt)}</span>
            </div>
          ))}
        </CardContent>
      </Card>

      {st.recentCards.length > 0 && (
        <Card className="gap-0 py-3">
          <CardHeader className="pb-1">
            <CardTitle className="text-[13px] font-medium text-muted-foreground">最近卡片</CardTitle>
          </CardHeader>
          <CardContent className="divide-y divide-dashed divide-border">
            {st.recentCards.slice(0, 6).map((c) => {
              const answer = c.answer ?? (c.choice != null ? c.options[c.choice] : null) ?? c.result;
              const state = c.closedAt ? "已结案" : c.decidedAt ? "已回答" : "等你";
              return (
                <div key={c.id} className="flex items-baseline justify-between gap-3 py-2 first:pt-0 last:pb-0">
                  <span className="min-w-0 flex-1 truncate text-sm">{c.title}</span>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {state}
                    {answer ? ` · ${String(answer).slice(0, 16)}` : ""}
                  </span>
                </div>
              );
            })}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
