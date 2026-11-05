import { useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { api } from "@/lib/api";
import { rel } from "@/lib/format";
import type { CardView } from "@/types";

/** 等你拍板的卡片：ask 点选项或写想法，fyi 确认已处理；都能结案。 */
export function AskCard({ card, onDone }: { card: CardView; onDone: () => void }) {
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [resolveOpen, setResolveOpen] = useState(false);
  const [reason, setReason] = useState("");

  const answer = async (body: object) => {
    setBusy(true);
    try {
      await api(`/v1/cards/${card.id}/answer`, { method: "POST", body: JSON.stringify(body) });
      toast.success("已回答");
      onDone();
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const resolve = async () => {
    setBusy(true);
    try {
      await api(`/v1/cards/${card.id}/resolve`, { method: "POST", body: JSON.stringify({ reason }) });
      toast.success("已结案");
      setResolveOpen(false);
      onDone();
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card className="gap-2.5 py-3.5">
      <CardContent className="px-4">
        <div className="mb-0.5 flex items-center justify-between text-xs text-muted-foreground">
          <span>
            {card.kind === "ask" ? "提问" : "通知"} · {card.rule ?? ""}
          </span>
          <span>{rel(card.createdAt)}</span>
        </div>
        <div className="text-[15px] leading-snug font-semibold">{card.title}</div>
        {card.text && <p className="mt-1.5 text-sm whitespace-pre-wrap text-muted-foreground">{card.text}</p>}
        {card.kind === "ask" && card.options.length > 0 && (
          <div className="mt-3 flex flex-wrap gap-2">
            {card.options.map((opt, i) => (
              <Button
                key={i}
                variant="outline"
                size="sm"
                className="rounded-full border-primary/40 px-4 font-semibold text-primary"
                disabled={busy}
                onClick={() => answer({ choice: i })}
              >
                {opt}
              </Button>
            ))}
          </div>
        )}
        {card.kind === "ask" && (
          <div className="mt-2.5 flex gap-2">
            <Input
              value={text}
              placeholder="或写一句想法…"
              onChange={(e) => setText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && text.trim()) answer({ text: text.trim() });
              }}
            />
            <Button
              size="sm"
              className="px-4"
              disabled={busy || !text.trim()}
              onClick={() => answer({ text: text.trim() })}
            >
              发送
            </Button>
          </div>
        )}
        <div className="mt-1.5 flex items-center gap-3">
          {card.kind === "fyi" && (
            <Button variant="secondary" size="sm" disabled={busy} onClick={() => setResolveOpen(true)}>
              已处理
            </Button>
          )}
          <Button variant="ghost" size="sm" className="text-muted-foreground underline" disabled={busy} onClick={() => setResolveOpen(true)}>
            {card.kind === "ask" ? "不用了，结案" : "直接结案"}
          </Button>
        </div>
      </CardContent>

      <Dialog open={resolveOpen} onOpenChange={setResolveOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>结案这张卡片</DialogTitle>
            <DialogDescription>{card.title}</DialogDescription>
          </DialogHeader>
          <Input value={reason} placeholder="理由（可空）" onChange={(e) => setReason(e.target.value)} />
          <DialogFooter>
            <Button variant="ghost" onClick={() => setResolveOpen(false)}>
              取消
            </Button>
            <Button variant="destructive" disabled={busy} onClick={resolve}>
              结案
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
