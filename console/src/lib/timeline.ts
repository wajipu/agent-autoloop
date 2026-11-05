// 把 cli/why.ts 的 fact→时间线口径原样移植：触发事件 → 领取 → 开始 → 提问/回答 → 结束/重试。
import type { Fact } from "@/types";

export type Step = { at?: string | number; text: string; cont?: boolean };

const parseJson = <T>(raw: unknown, fallback: T): T => {
  try {
    return JSON.parse(String(raw ?? "")) as T;
  } catch {
    return fallback;
  }
};

export function timeline(id: number, facts: Fact[]): Step[] {
  const allChanges = (facts ?? []).flatMap((fact) => fact.changes ?? []);
  const relations = new Map<string, Record<string, any>>();
  for (const { table, key, row } of allChanges) {
    if (table !== "run_events") continue;
    if (row) relations.set(key, row);
    else relations.delete(key);
  }
  const ownRelations = [...relations.values()].filter((r) => r.run_id === id);
  const events = new Set<number>(ownRelations.map((r) => r.event_id));
  const runs = allChanges
    .filter(({ table, row }) => table === "runs" && row?.id === id)
    .map(({ row }) => row as Record<string, any>);
  const links = new Map<number, string>();
  for (const run of runs) if (run.issued && run.link) links.set(run.issued, run.link);
  const versions = new Set<number>(runs.map((r) => r.rules_version));
  const rulesAt = new Map<number, any>();
  for (const fact of facts) {
    if (fact.type !== "rules") continue;
    const config = (fact.changes ?? []).find((c) => c.table === "config" && c.key === "rules");
    if (config?.row?.value) rulesAt.set(fact.seq, config.row.value);
  }
  const out: Step[] = [];
  const add = (at: string | number, text: string) => out.push({ at, text });
  const eventText = (e: Record<string, any>) => `来源 ${e.source} · 类型 ${e.type} · 对象 ${e.subject || "无"}`;
  const previous = new Map<string, Record<string, any>>();
  const started = new Set<number>();

  const tellRun = (fact: Fact, row: Record<string, any>, before: Record<string, any> | undefined, receipt: boolean) => {
    if (row.claimed_at && row.claimed_at !== before?.claimed_at) {
      const agent = rulesAt.get(row.rules_version)?.agents?.[row.agent];
      add(row.claimed_at, `${agent?.worker ?? "worker"} 领取（${agent?.name ?? row.agent}）`);
    }
    if (fact.type === "started" && !started.has(row.issued)) {
      add(fact.at, "开始处理");
      started.add(row.issued);
    }
    if (row.link && row.link === links.get(row.issued) && row.link !== before?.link) add(fact.at, `会话：${row.link}`);
    if (row.finished_at && row.finished_at !== before?.finished_at) {
      add(row.finished_at, `结束：${row.summary || (row.state === "cancelled" ? "已停止" : "没有填写结论")}`);
    }
    if (receipt && row.state === "queued" && row.attempts !== before?.attempts) {
      add(fact.at, `本次未完成：${row.error}；重试时间 ${row.not_before ?? ""}`);
    }
    if (receipt) for (const rejected of parseJson<any[]>(row.last_answer, [])) add(fact.at, `未执行：${rejected.reason}`);
  };

  const tellCard = (row: Record<string, any>, before: Record<string, any> | undefined, receipt: boolean) => {
    const own = row.run_id === id;
    if (!before && own && !row.fyi) {
      const options = parseJson<string[]>(row.options, []);
      add(row.created_at, `${row.kind === "ask" ? "提问" : "通知"}：${row.title}`);
      if (row.text) for (const line of String(row.text).split("\n")) out.push({ text: line, cont: true });
      if (options.length) out.push({ text: `选项：${options.join(" / ")}`, cont: true });
    }
    if (row.decided_at && row.decided_at !== before?.decided_at && (own || events.has(row.answer_event))) {
      const answer = row.answer ?? parseJson<string[]>(row.options, [])[row.choice];
      add(row.decided_at, `${row.by || "本人"}回答「${row.title}」：${answer}`);
      if (own) {
        for (const { event_id, run_id } of relations.values()) {
          if (event_id === row.answer_event && run_id !== id) add(row.decided_at, `回答后继续：第 ${run_id} 轮`);
        }
      }
    }
    if (row.state === "closed" && before?.state !== "closed" && (receipt || own) && !row.fyi) {
      add(row.closed_at, `结案：${row.title}；${row.result}`);
    }
  };

  for (const fact of facts ?? []) {
    if (fact.type === "rules" && versions.has(fact.seq)) add(fact.at, `规则版本 #${fact.seq}`);
    const changes = new Map((fact.changes ?? []).map((c) => [`${c.table}:${c.key}`, c]));
    const receipt = fact.type === "finish" && Boolean(changes.get(`runs:${id}`)?.row);
    for (const [changed, { table, key, row }] of changes) {
      const before = previous.get(changed);
      if (table === "events" && row && !before && events.has(row.id)) add(row.received_at, `触发事件：${eventText(row)}`);
      if (table === "runs" && row?.id === id) tellRun(fact, row, before, receipt);
      if (table === "cards" && row) tellCard(row, before, receipt);
      if (receipt && table === "timers") add(fact.at, row ? `安排复查：${row.about}；时间 ${row.at}` : `取消复查：${before?.key ?? key}`);
      if (receipt && table === "events" && row && !before && !events.has(row.id)) add(fact.at, `发出事件：${eventText(row)}`);
      if (row) previous.set(changed, row);
      else previous.delete(changed);
    }
  }
  return out;
}
