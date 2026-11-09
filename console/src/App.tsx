import { useCallback, useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";

import { BottomTabs, type View } from "@/components/BottomTabs";
import { IssuesView } from "@/components/IssuesView";
import { OverviewView } from "@/components/OverviewView";
import { RunsView } from "@/components/RunsView";
import { SettingsView } from "@/components/SettingsView";
import { SubmitView } from "@/components/SubmitView";
import { Button } from "@/components/ui/button";
import { Toaster } from "@/components/ui/sonner";
import { hms } from "@/lib/format";
import type { HubState } from "@/types";

export default function App() {
  const [view, setView] = useState<View>(() => {
    const hash = window.location.hash.replace("#", "");
    return (["overview", "issues", "runs", "submit", "settings"] as string[]).includes(hash) ? (hash as View) : "overview";
  });
  const [nonce, setNonce] = useState(0);
  const [updated, setUpdated] = useState<string>("");

  const go = useCallback((next: View) => {
    setView(next);
    window.location.hash = next;
  }, []);

  const bump = useCallback(() => setNonce((n) => n + 1), []);
  const onState = useCallback((st: HubState) => setUpdated(st.now), []);

  // 页面可见时每 15 秒刷一次动态页签；切页签也会拉最新。
  useEffect(() => {
    const timer = setInterval(() => {
      if (document.visibilityState === "visible" && (view === "overview" || view === "runs")) bump();
    }, 15000);
    return () => clearInterval(timer);
  }, [view, bump]);

  useEffect(() => {
    const jump = () => go("settings");
    window.addEventListener("al-go-settings", jump);
    return () => window.removeEventListener("al-go-settings", jump);
  }, [go]);

  return (
    <div className="min-h-dvh">
      <header className="sticky top-0 z-10 border-b bg-background/85 pt-[env(safe-area-inset-top)] backdrop-blur">
        <div className="mx-auto flex max-w-2xl items-center justify-between px-4 py-2.5">
          <div className="flex items-center gap-1.5 text-[15px] font-bold tracking-wide">
            <span className="text-lg leading-none font-black text-primary">↻</span>
            autoloop
          </div>
          <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
            {updated && <span className="tabular-nums">{hms(updated)}</span>}
            <Button variant="ghost" size="icon" className="size-8" onClick={bump} aria-label="刷新">
              <RefreshCw className="size-4" />
            </Button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-2xl px-3 pt-3 pb-[calc(72px+env(safe-area-inset-bottom))]">
        {view === "overview" && <OverviewView nonce={nonce} onState={onState} />}
        {view === "issues" && <IssuesView nonce={nonce} />}
        {view === "runs" && <RunsView nonce={nonce} onState={onState} />}
        {view === "submit" && <SubmitView />}
        {view === "settings" && <SettingsView onSaved={bump} />}
      </main>

      <BottomTabs view={view} onChange={go} />
      <Toaster />
    </div>
  );
}
