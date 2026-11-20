// hub HTTP API 的载荷类型，字段照 /v1/state 与 /v1/runs/<id>/why 的真实返回写。
export type Usage = { input: number; output: number; cost: number };

export type Totals = {
  running: number;
  queued: number;
  retrying: number;
  unknown: number;
  done: number;
  doneToday: number;
  nothing: number;
  usage: Usage;
  attention: number;
};

export type AgentInfo = {
  id: string;
  name: string;
  use: string;
  worker: string;
  seenAt: string | null;
  online: boolean;
  totals: Totals;
};

export type ChannelInfo = { id: string; name: string; seenAt: string | null; online: boolean };

/** cardView（kernel/query.ts）：options 已解析成数组，rule 代替 run_id，时间字段是驼峰。 */
export type CardView = {
  id: number;
  kind: "ask" | "fyi";
  state: string;
  title: string;
  text: string | null;
  options: string[];
  choice: number | null;
  answer: string | null;
  by: string | null;
  result: string | null;
  rule: string | null;
  createdAt: string;
  decidedAt: string | null;
  closedAt: string | null;
};

export type RunRow = {
  id: number;
  rule: string;
  agent: string;
  state: string; // claimed / queued / unknown / done / cancelled / nothing
  attempts: number;
  createdAt: string;
  claimedAt: string | null;
  finishedAt: string | null;
  notBefore: string | null;
  summary: string;
  error: string;
  link: string;
  session: string | null;
  usage: Usage | null;
  stopping: boolean;
  events: { source: string; type: string; subject: string; summary: string; link: string }[];
};

export type HubState = {
  now: string;
  timezone: string;
  totals: Totals;
  cards: CardView[];
  recentCards: CardView[];
  agents: AgentInfo[];
  channels: ChannelInfo[];
  runs: RunRow[];
  hasMore: boolean;
  nextBefore: number | null;
};

/** /v1/runs/<id>/why 的原始事实；changes 里 row 是累计整行，options/last_answer 是 JSON 字符串。 */
export type Fact = {
  version?: number;
  seq: number;
  at: number;
  type: string;
  changes: { table: string; key: string; row: Record<string, any> | null }[];
};
