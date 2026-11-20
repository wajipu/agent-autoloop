import { Badge } from "@/components/ui/badge";
import { stateOf } from "@/lib/format";
import { cn } from "@/lib/utils";

const COLORS: Record<string, string> = {
  claimed: "border-sky-500/25 bg-sky-500/12 text-sky-600 dark:text-sky-400",
  queued: "border-amber-500/25 bg-amber-500/12 text-amber-600 dark:text-amber-400",
  unknown: "border-amber-500/25 bg-amber-500/12 text-amber-600 dark:text-amber-400",
  done: "border-emerald-500/25 bg-emerald-500/12 text-emerald-600 dark:text-emerald-400",
  cancelled: "border-zinc-500/25 bg-zinc-500/10 text-zinc-500 dark:text-zinc-400",
  nothing: "border-zinc-500/25 bg-zinc-500/10 text-zinc-500 dark:text-zinc-400",
};

/** 排队且已有尝试次数算「重试」，用红色区分。 */
export function StateBadge({ state, attempts = 0 }: { state: string; attempts?: number }) {
  const retry = state === "queued" && attempts > 0;
  const label = retry ? "重试" : stateOf(state);
  const color = retry ? "border-red-500/25 bg-red-500/12 text-red-600 dark:text-red-400" : COLORS[state] ?? "";
  return (
    <Badge variant="outline" className={cn("shrink-0", color)}>
      {label}
    </Badge>
  );
}
