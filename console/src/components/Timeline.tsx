import type { Step } from "@/lib/timeline";
import { mdhm } from "@/lib/format";

export function Timeline({ steps }: { steps: Step[] }) {
  if (!steps.length) return <p className="px-1 text-sm text-muted-foreground">没有过程记录</p>;
  return (
    <ol className="relative ml-1.5 border-l border-border">
      {steps.map((step, i) => (
        <li key={i} className="relative py-1.5 pl-4 text-sm leading-relaxed">
          <span className="absolute top-[10px] -left-[4.5px] size-[7px] rounded-full bg-primary ring-[3px] ring-background" />
          {step.at != null && (
            <span className="mr-1.5 align-middle text-xs tabular-nums text-muted-foreground">{mdhm(step.at)}</span>
          )}
          <span className={step.cont ? "whitespace-pre-wrap text-muted-foreground" : ""}>{step.text}</span>
        </li>
      ))}
    </ol>
  );
}
