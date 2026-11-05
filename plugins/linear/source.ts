// Linear webhooks, checked against the webhook's signing key and turned into events: only `Issue create`, the
// issue's uuid as the event id, so the poller's `issue.opened` for the same issue dedupes into one round. Updates
// are ignored on purpose — the handling agent leaves a comment when done, and an update trigger would loop that.
// In rules.json: "sources": { "linear": { "name": "Linear", "adapter": "linear" } }, and AGENT_AUTOLOOP_SECRET_LINEAR
// in secrets.env. LINEAR_TRIGGER_LABEL (optional, secrets.env too): when set, only issues carrying that label are
// emitted; Linear's own webhook filters narrow it server-side just as well.
import { createHmac, timingSafeEqual } from "node:crypto";

type Input = { headers: Record<string, string | string[]>; body: string; secret: string };

export default function linear({ headers, body, secret }: Input) {
  // Linear signs the raw body with the webhook's signing key: HMAC-SHA256, base64, in the Linear-Signature header.
  const given = String(headers["linear-signature"] ?? "");
  const sign = createHmac("sha256", secret).update(body).digest("base64");
  const signed = secret && given.length === sign.length && timingSafeEqual(Buffer.from(given), Buffer.from(sign));
  if (!signed) throw new Error("signature");
  const payload = JSON.parse(body);
  if (payload.type !== "Issue" || payload.action !== "create") return [];
  const issue = payload.data ?? {};
  const wanted = process.env.LINEAR_TRIGGER_LABEL?.toLowerCase();
  const labels = (issue.labels?.nodes ?? issue.labels ?? []) as { name?: string }[];
  if (wanted && !labels.some((label) => String(label.name ?? "").toLowerCase() === wanted)) return [];
  return [
    {
      id: String(issue.id ?? ""),
      type: "issue.create",
      subject: String(issue.identifier ?? "").replace(/[^A-Za-z0-9#._:/@-]/g, "-").slice(0, 100),
      summary: String(issue.title ?? "").slice(0, 200),
      detail: String(issue.description ?? "").slice(0, 4000),
      link: encodeURI(String(issue.url ?? "")).slice(0, 500),
    },
  ];
}
