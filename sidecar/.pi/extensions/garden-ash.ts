import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";
import { appendFileSync } from "node:fs";
import { join } from "node:path";

const RPC_URL = process.env.ASH_RPC_URL ?? "http://localhost:4000/api/pi/run";
const TOKEN = process.env.PI_SERVICE_TOKEN ?? "dev-pi-token";

// Sidecar root is the cwd when pi runs (set by PiRunner).
const FAILED_IMPORTS_PATH = join(process.cwd(), "_failed_imports.jsonl");

type RpcError = { type: string; field?: string | null; message: string };
type RpcResult = { success: boolean; data?: { id?: string }; errors?: RpcError[] };

async function call(action: string, input: Record<string, unknown>): Promise<RpcResult> {
  let result: RpcResult;

  try {
    const res = await fetch(RPC_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${TOKEN}`,
      },
      body: JSON.stringify({ action, input }),
    });
    result = (await res.json()) as RpcResult;
  } catch (err) {
    result = {
      success: false,
      errors: [{ type: "network_error", message: String(err) }],
    };
  }

  if (!result.success) {
    deadLetter(action, input, result.errors ?? []);
  }

  return result;
}

function deadLetter(action: string, input: Record<string, unknown>, errors: RpcError[]) {
  try {
    const line = JSON.stringify({
      action,
      input,
      errors,
      attempted_at: new Date().toISOString(),
    });
    appendFileSync(FAILED_IMPORTS_PATH, line + "\n");
  } catch (err) {
    // Best-effort — never let dead-letter writes crash the agent.
    console.error("dead-letter append failed:", err);
  }
}

function reply(text: string, details: unknown) {
  return { content: [{ type: "text" as const, text }], details };
}

function summarizeErrors(errors?: RpcError[]): string {
  if (!errors || errors.length === 0) return "(no detail)";
  return errors
    .map((e) => (e.field ? `${e.field}: ${e.message}` : e.message))
    .join("; ");
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "save_bid",
    label: "Save Bid",
    description:
      "Persist a procurement bid finding to the Gnome database. Upserts on URL — safe to retry. " +
      "Pass a `documents` array to queue document download/storage.",
    parameters: Type.Object({
      title: Type.String(),
      url: Type.String({ description: "Unique bid listing URL" }),
      agency: Type.Optional(Type.String()),
      description: Type.Optional(Type.String()),
      location: Type.Optional(Type.String()),
      region: Type.Optional(
        Type.String({ description: "oc | la | ie | sd | socal | norcal | ca | national" }),
      ),
      bid_type: Type.Optional(
        Type.String({ description: "rfi | rfp | rfq | ifb | soq | other" }),
      ),
      estimated_value: Type.Optional(Type.Number()),
      posted_at: Type.Optional(Type.String({ description: "ISO 8601" })),
      due_at: Type.Optional(Type.String({ description: "ISO 8601" })),
      score_total: Type.Optional(Type.Number()),
      score_tier: Type.Optional(Type.String({ description: "hot | warm | prospect" })),
      score_recommendation: Type.Optional(Type.String()),
      keywords_matched: Type.Optional(Type.Array(Type.String())),
      documents: Type.Optional(
        Type.Array(
          Type.Object({
            url: Type.String(),
            filename: Type.Optional(Type.String()),
            document_type: Type.Optional(
              Type.String({
                description: "solicitation | scope | pricing | addendum | other",
              }),
            ),
          }),
        ),
      ),
      metadata: Type.Optional(Type.Any()),
    }),
    async execute(_id, params) {
      const r = await call("save_bid", params as Record<string, unknown>);
      return reply(
        r.success
          ? `✓ Saved bid "${params.title}"${params.score_tier ? ` (${params.score_tier})` : ""}`
          : `✗ save_bid failed: ${summarizeErrors(r.errors)} — queued for retry`,
        r,
      );
    },
  });

  pi.registerTool({
    name: "save_source",
    label: "Save Source",
    description:
      "Persist a procurement source URL to the Gnome database. Upserts on URL — safe to retry.",
    parameters: Type.Object({
      name: Type.String(),
      url: Type.String(),
      source_type: Type.String({
        description:
          "planetbids | opengov | bidnet | sam_gov | cal_eprocure | utility | school | port | custom | company_site | job_board | directory",
      }),
      region: Type.Optional(Type.String()),
      portal_id: Type.Optional(Type.String()),
      notes: Type.Optional(Type.String()),
    }),
    async execute(_id, params) {
      const r = await call("save_source", {
        ...params,
        added_by: "agent",
        status: "approved",
        enabled: true,
      });
      return reply(
        r.success
          ? `✓ Saved source "${params.name}" (${params.source_type})`
          : `✗ save_source failed: ${summarizeErrors(r.errors)} — queued for retry`,
        r,
      );
    },
  });

  pi.registerTool({
    name: "save_prospect",
    label: "Save Prospect",
    description:
      "Persist a prospect — company hiring controls/automation talent or otherwise signaling demand. " +
      "Creates Organization + DiscoveryRecord transactionally. Idempotent on website domain.",
    parameters: Type.Object({
      name: Type.String(),
      website: Type.Optional(Type.String()),
      location: Type.Optional(Type.String()),
      region: Type.Optional(Type.String()),
      industry: Type.Optional(Type.String()),
      size_bucket: Type.Optional(
        Type.String({ description: "small | medium | large | enterprise" }),
      ),
      fit_score: Type.Optional(Type.Number()),
      intent_score: Type.Optional(Type.Number()),
      notes: Type.Optional(Type.String()),
      metadata: Type.Optional(Type.Any()),
    }),
    async execute(_id, params) {
      const r = await call("save_prospect", {
        name: params.name,
        website: params.website,
        location: params.location,
        region: params.region,
        industry: params.industry,
        size_bucket: params.size_bucket,
        fit_score: params.fit_score ?? 50,
        intent_score: params.intent_score ?? 50,
        notes: params.notes,
        metadata: params.metadata ?? {},
        organization_name: params.name,
        organization_website: params.website,
        organization_primary_region: params.region,
      });

      return reply(
        r.success
          ? `✓ Saved prospect "${params.name}" (fit:${params.fit_score ?? 50} intent:${params.intent_score ?? 50})`
          : `✗ save_prospect failed: ${summarizeErrors(r.errors)} — queued for retry`,
        r,
      );
    },
  });

  pi.registerTool({
    name: "save_opportunity",
    label: "Save Opportunity",
    description:
      "Persist an opportunity — a company actively posting for an outside integrator/contractor. " +
      "Rare and high-value: bar is much higher than save_prospect. Creates Organization + DiscoveryRecord " +
      "transactionally with record_type=opportunity. Idempotent on website domain.",
    parameters: Type.Object({
      name: Type.String(),
      website: Type.Optional(Type.String()),
      location: Type.Optional(Type.String()),
      region: Type.Optional(Type.String()),
      industry: Type.Optional(Type.String()),
      size_bucket: Type.Optional(Type.String()),
      fit_score: Type.Optional(Type.Number()),
      intent_score: Type.Optional(Type.Number()),
      notes: Type.Optional(
        Type.String({
          description: "Include the integrator-request signal (RFP link, contact form, etc.)",
        }),
      ),
      metadata: Type.Optional(Type.Any()),
    }),
    async execute(_id, params) {
      const r = await call("save_opportunity", {
        name: params.name,
        website: params.website,
        location: params.location,
        region: params.region,
        industry: params.industry,
        size_bucket: params.size_bucket,
        fit_score: params.fit_score ?? 70,
        intent_score: params.intent_score ?? 80,
        notes: params.notes,
        metadata: params.metadata ?? {},
        organization_name: params.name,
        organization_website: params.website,
        organization_primary_region: params.region,
      });

      return reply(
        r.success
          ? `✓ Saved OPPORTUNITY "${params.name}" (fit:${params.fit_score ?? 70} intent:${params.intent_score ?? 80})`
          : `✗ save_opportunity failed: ${summarizeErrors(r.errors)} — queued for retry`,
        r,
      );
    },
  });
}
