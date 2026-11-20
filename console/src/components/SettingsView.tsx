import { useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api, appKey, ownerKey } from "@/lib/api";
import type { HubState } from "@/types";

/** 两个密钥只存本机 localStorage；泄露了在服务器 agent-autoloop key remove 作废重发。 */
export function SettingsView({ onSaved }: { onSaved: () => void }) {
  const [owner, setOwner] = useState(ownerKey());
  const [app, setApp] = useState(appKey());
  const [busy, setBusy] = useState(false);

  const save = () => {
    localStorage.setItem("al.owner", owner.trim());
    localStorage.setItem("al.app", app.trim());
    toast.success("已保存");
    onSaved();
  };

  const test = async () => {
    setBusy(true);
    try {
      const st = await api<HubState>("/v1/state");
      toast.success(`通了：${st.agents.length} 个 Agent · 在跑 ${st.totals.running}`);
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-2.5">
      <Card>
        <CardHeader>
          <CardTitle className="text-[15px]">密钥</CardTitle>
          <CardDescription>只存在这台手机的 localStorage 里</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="k-owner">owner 密钥（看板、回答、停轮次）</Label>
            <Input
              id="k-owner"
              type="password"
              value={owner}
              placeholder="服务器 config.json 的 owner"
              onChange={(e) => setOwner(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="k-app">app 事件源密钥（提交任务用）</Label>
            <Input
              id="k-app"
              type="password"
              value={app}
              placeholder="agent-autoloop key new source app"
              onChange={(e) => setApp(e.target.value)}
            />
          </div>
          <Button className="w-full" onClick={save}>
            保存
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-[15px]">连接</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <Button variant="outline" className="w-full" disabled={busy} onClick={test}>
            {busy ? "测试中…" : "测试连接"}
          </Button>
          <p className="text-xs leading-relaxed text-muted-foreground">
            打不开页面或报 401：先确认 NAT 面板放行了 28090 端口，再核对 owner 密钥。
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
