import { useCallback, useEffect, useState } from "react";

import { NoKeyCard } from "@/components/OverviewView";
import { RunSheet } from "@/components/RunSheet";
import { StateBadge } from "@/components/StateBadge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { api, ownerKey } from "@/lib/api";
import { LIVE_STATES, rel } from "@/lib/format";
import type { AgentInfo, HubState, RunRow } from "@/types";

/** 轮次列表：首屏来自 /v1/state，翻页用 ?before=，默认藏掉定时轮询的噪音。 */
export function RunsView({ nonce, onState }: { nonce: number; onState: (st: HubState) => void }) {
  const [first, setFirst] = useState<RunRow[] | null>(null);
  const [older, setOlder] = useState<RunRow[]>([]);
  const [agents, setAgents] = useState<AgentInfo[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [nextBefore, setNextBefore] = useState<number | null>(null);
  const [hidePoll, setHidePoll] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [openId, setOpenId] = useState<number | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  const load = useCallback(async () => {
    if (!ownerKey()) return;
    try {
      const st = await api<HubState>("/v1/state");
      setFirst(st.runs);
      setAgents(st.agents);
      setHasMore(st.hasMore);
      setNextBefore(st.nextBefore);
      setError(null);
      onState(st);
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
  if (first === null)
    return (
      <div className="space-y-2.5">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-[64px] rounded-xl" />
        ))}
      </div>
    );

  const all = [...first, ...older].filter((r) => (hidePoll ? r.rule !== "盯 Linear" : true));
  const live = all.filter((r) => LIVE_STATES.includes(r.state));
  const rest = all.filter((r) => !LIVE_STATES.includes(r.state));
  const current = all.find((r) => r.id === openId) ?? null;

  const loadOlder = async () => {
    if (nextBefore == null) return;
    setLoadingMore(true);
    try {
      const st = await api<HubState>(`/v1/state?before=${nextBefore}`);
      setOlder((prev) => [...prev, ...st.runs]);
      setHasMore(st.hasMore);
      setNextBefore(st.nextBefore);
    } catch {
      setHasMore(false);
    } finally {
      setLoadingMore(false);
    }
  };

  const Row = ({ run }: { run: RunRow }) => (
    <Button
      variant="ghost"
      className="h-auto w-full justify-start rounded-xl border bg-card px-3.5 py-3 shadow-sm"
      onClick={() => setOpenId(run.id)}
    >
      <div className="w-full space-y-0.5 text-left">
        <div className="flex items-center gap-2">
          <span className="text-xs tabular-nums text-muted-foreground">#{run.id}</span>
          <span className="min-w-0 flex-1 truncate text-sm font-medium">{run.rule}</span>
          <StateBadge state={run.state} attempts={run.attempts} />
        </div>
        <p className="line-clamp-2 text-xs leading-relaxed text-muted-foreground">{run.summary || rel(run.createdAt)}</p>
      </div>
    </Button>
  );

  return (
    <div className="space-y-2.5">
      <div className="flex items-center justify-between px-0.5">
        <Label className="gap-2.5 text-[13px] text-muted-foreground">
          <Switch checked={hidePoll} onCheckedChange={setHidePoll} />
          隐藏定时轮询
        </Label>
        <span className="text-xs text-muted-foreground">
          共 {all.length} 轮{hasMore ? "（还有更早）" : ""}
        </span>
      </div>

      {live.map((run) => (
        <Row key={run.id} run={run} />
      ))}
      {rest.map((run) => (
        <Row key={run.id} run={run} />
      ))}
      {all.length === 0 && <p className="py-10 text-center text-sm text-muted-foreground">没有轮次</p>}

      {hasMore && (
        <Button variant="outline" className="w-full" disabled={loadingMore} onClick={loadOlder}>
          {loadingMore ? "加载中…" : "加载更早"}
        </Button>
      )}

      <RunSheet
        run={current}
        agents={agents}
        open={openId !== null}
        onOpenChange={(o) => !o && setOpenId(null)}
        onChanged={() => {
          setOlder([]);
          load();
        }}
      />
    </div>
  );
}
