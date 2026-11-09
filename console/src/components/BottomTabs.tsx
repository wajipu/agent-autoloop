import { History, LayoutDashboard, ListTodo, Send, Settings } from "lucide-react";

import { cn } from "@/lib/utils";

const TABS = [
  { id: "overview", label: "总览", icon: LayoutDashboard },
  { id: "issues", label: "工作项", icon: ListTodo },
  { id: "runs", label: "轮次", icon: History },
  { id: "submit", label: "提交", icon: Send },
  { id: "settings", label: "设置", icon: Settings },
] as const;

export type View = (typeof TABS)[number]["id"];

export function BottomTabs({ view, onChange }: { view: View; onChange: (v: View) => void }) {
  return (
    <nav className="fixed inset-x-0 bottom-0 z-10 border-t bg-background/90 backdrop-blur">
      <div className="mx-auto grid max-w-2xl grid-cols-5 pb-[env(safe-area-inset-bottom)]">
        {TABS.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            className={cn(
              "flex flex-col items-center gap-0.5 py-2 text-xs font-medium transition-colors",
              view === id ? "text-primary" : "text-muted-foreground",
            )}
            onClick={() => onChange(id)}
          >
            <Icon className="size-5" />
            {label}
          </button>
        ))}
      </div>
    </nav>
  );
}
