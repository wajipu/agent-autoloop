import { useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { api, appKey } from "@/lib/api";

const pad = (n: number) => String(n).padStart(2, "0");

/** 直发 hub 事件（type task.submitted），不经过 Linear；路由给 Mac 上的 claude。 */
export function SubmitView() {
  const [title, setTitle] = useState("");
  const [detail, setDetail] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    if (!title.trim() || busy) return;
    if (!appKey()) {
      toast.error("先到「设置」填 app 事件源密钥");
      return;
    }
    setBusy(true);
    const d = new Date();
    const stamp = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
    const rand = Math.random().toString(36).slice(2, 6);
    try {
      const res = await api<{ duplicate: boolean; routed: string[] }>(
        "/v1/events",
        {
          method: "POST",
          body: JSON.stringify({
            id: crypto.randomUUID(),
            type: "task.submitted",
            subject: `app-${stamp}-${rand}`,
            summary: title.trim(),
            detail: detail.trim(),
          }),
        },
        appKey(),
      );
      if (res.duplicate) toast.error("中台说这个事件已经有了（重复）");
      else toast.success(res.routed?.length ? `已进中台，路由到「${res.routed.join("、")}」` : "已进中台（没有规则接住它）");
      setDetail("");
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-[15px]">提一件事给 Agent</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="sub-title">标题（必填）</Label>
          <Input
            id="sub-title"
            value={title}
            placeholder="比如：查一下昨天 beta 部署为什么失败"
            onChange={(e) => setTitle(e.target.value)}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="sub-detail">详情</Label>
          <Textarea
            id="sub-detail"
            value={detail}
            placeholder="背景、要查什么、期望产出…"
            onChange={(e) => setDetail(e.target.value)}
          />
        </div>
        <Button className="w-full text-base" size="lg" disabled={busy || !title.trim()} onClick={submit}>
          {busy ? "提交中…" : "提交到中台"}
        </Button>
        <p className="text-xs leading-relaxed text-muted-foreground">
          会立刻变成事件路由给 Claude（在 Mac 上跑），过程和结果在「轮次」里看，要拍板时你会收到卡片。
          {!appKey() && " 还没填 app 密钥：去「设置」。"}
        </p>
      </CardContent>
    </Card>
  );
}
