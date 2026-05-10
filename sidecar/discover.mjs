#!/usr/bin/env node
/**
 * Pi-powered target discovery — standalone experiment.
 *
 * No Phoenix integration. Searches the web, evaluates companies against
 * Gnome's ICP, scores them, and prints structured findings to stdout.
 *
 * Usage:
 *   ANTHROPIC_API_KEY=sk-... node discover.mjs "breweries in Orange County CA"
 *   OPENAI_API_KEY=sk-... node discover.mjs --provider openai "biotech San Diego"
 *   node discover.mjs --provider openai --model gpt-4.1 "water treatment Inland Empire"
 */

import { Agent } from "@mariozechner/pi-agent-core";
import {
  registerBuiltInApiProviders,
  getModel,
  streamSimple,
  getEnvApiKey,
} from "@mariozechner/pi-ai";
import { Type } from "@mariozechner/pi-ai";
import { writeFileSync, readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

registerBuiltInApiProviders();

const args = process.argv.slice(2);
let providerName = "anthropic";
let modelId = "claude-sonnet-4-5";

const providerIdx = args.indexOf("--provider");
if (providerIdx !== -1) {
  providerName = args[providerIdx + 1];
  args.splice(providerIdx, 2);
  if (providerName === "openai" && modelId === "claude-sonnet-4-5")
    modelId = "gpt-4o";
}

const modelIdx = args.indexOf("--model");
if (modelIdx !== -1) {
  modelId = args[modelIdx + 1];
  args.splice(modelIdx, 2);
}

const query =
  args.join(" ") || "breweries and food manufacturers in Orange County CA";

const model = getModel(providerName, modelId);
if (!model) {
  console.error(`Unknown model: ${providerName}/${modelId}`);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

/** @type {import("@mariozechner/pi-agent-core").AgentTool} */
const webSearch = {
  name: "web_search",
  label: "Web Search",
  description:
    "Search the web using Brave Search API. Use this to find companies, job postings, expansion news, and industry activity in target regions.",
  parameters: Type.Object({
    query: Type.String({ description: "Search query" }),
    count: Type.Optional(
      Type.Number({ description: "Number of results (max 20)", default: 10 })
    ),
  }),
  execute: async (_toolCallId, { query, count = 10 }) => {
    const apiKey = process.env.BRAVE_API_KEY;
    if (!apiKey) {
      return {
        content: [
          {
            type: "text",
            text: "BRAVE_API_KEY not set. Reason from your existing knowledge instead.",
          },
        ],
        details: {},
      };
    }

    const url = new URL("https://api.search.brave.com/res/v1/web/search");
    url.searchParams.set("q", query);
    url.searchParams.set("count", String(Math.min(count, 20)));

    const res = await fetch(url.toString(), {
      headers: {
        "X-Subscription-Token": apiKey,
        Accept: "application/json",
      },
    });

    if (!res.ok) {
      throw new Error(`Brave search failed: ${res.status} ${res.statusText}`);
    }

    const data = await res.json();
    const results = (data.web?.results || [])
      .map(
        (r, i) =>
          `${i + 1}. ${r.title}\n   ${r.url}\n   ${r.description || ""}`
      )
      .join("\n\n");

    return {
      content: [{ type: "text", text: results || "No results found." }],
      details: { resultCount: data.web?.results?.length || 0 },
    };
  },
};

/** @type {import("@mariozechner/pi-agent-core").AgentTool} */
const reportFinding = {
  name: "report_finding",
  label: "Report Finding",
  description:
    "Report a discovered company as a potential target. Call this for every company that passes your evaluation. Include your AI-assessed scores and reasoning.",
  parameters: Type.Object({
    company_name: Type.String({ description: "Company name" }),
    company_description: Type.String({
      description: "2-3 sentences about what they do",
    }),
    signal: Type.String({
      description:
        "Specific signal: 'Hiring automation engineer per Indeed 4/2026' not 'might need automation'",
    }),
    industry: Type.String({
      description:
        "Category: brewery, food_bev, packaging, water, biotech, pharma, warehouse, logistics, manufacturing, plastics, aerospace, chemical, cosmetic",
    }),
    location: Type.String({ description: "City, State" }),
    website: Type.Optional(Type.String({ description: "Company website URL" })),
    source_url: Type.Optional(
      Type.String({ description: "URL where you found the signal" })
    ),
    employee_count: Type.Optional(
      Type.Number({ description: "Estimated employees (20-500 sweet spot)" })
    ),
    fit_score: Type.Number({
      description:
        "0-100. Industry(40) + Service(30) + Geography(15) + Size(15)",
    }),
    intent_score: Type.Number({
      description:
        "0-100. Base 35 + buying(30) + expansion(18) + pain(16) + ops software(10) - staff aug(15) - excluded(20)",
    }),
    rationale: Type.String({
      description: "2-3 sentences explaining your scoring",
    }),
    icp_matches: Type.Array(Type.String(), {
      description:
        "Matched: controller-facing integration, operations software/web, target industry, core geography",
    }),
    risk_flags: Type.Array(Type.String(), {
      description:
        "Concerns: staff augmentation, generic marketing website, enterprise IT, low-priority industry",
    }),
  }),
  execute: async (_toolCallId, finding) => {
    const avgScore = Math.round(
      (finding.fit_score + finding.intent_score) / 2
    );
    const tier =
      avgScore >= 75 ? "HOT" : avgScore >= 50 ? "WARM" : "PROSPECT";

    const output = {
      ...finding,
      tier,
      avg_score: avgScore,
      discovered_at: new Date().toISOString(),
    };

    // Print to stderr for live visibility
    console.error("\n" + "=".repeat(70));
    console.error(
      `FINDING: ${output.company_name} — ${tier} (fit:${output.fit_score} intent:${output.intent_score})`
    );
    console.error("-".repeat(70));
    console.error(`Industry:    ${output.industry}`);
    console.error(`Location:    ${output.location}`);
    console.error(`Employees:   ${output.employee_count || "unknown"}`);
    console.error(`Website:     ${output.website || "unknown"}`);
    console.error(`Signal:      ${output.signal}`);
    console.error(`Source:      ${output.source_url || "unknown"}`);
    console.error(
      `ICP match:   ${output.icp_matches.join(", ") || "none"}`
    );
    console.error(
      `Risk flags:  ${output.risk_flags.length ? output.risk_flags.join(", ") : "none"}`
    );
    console.error(`Rationale:   ${output.rationale}`);
    console.error("=".repeat(70) + "\n");

    // Append to findings.json for later review
    const findingsPath = join(__dirname, "findings.json");
    let findings = [];
    try {
      findings = JSON.parse(readFileSync(findingsPath, "utf-8"));
    } catch {}
    findings.push(output);
    writeFileSync(findingsPath, JSON.stringify(findings, null, 2));

    return {
      content: [
        {
          type: "text",
          text: `Recorded ${output.company_name} as ${tier} (fit:${output.fit_score}, intent:${output.intent_score}). Keep searching.`,
        },
      ],
      details: output,
    };
  },
};

// ---------------------------------------------------------------------------
// System prompt
// ---------------------------------------------------------------------------

const SYSTEM_PROMPT = `You are a target discovery agent for Gnome Automation.

COMPANY PROFILE
- Name: Gnome
- Legal name: Gnome Automation
- Positioning: Industrial integration and custom software group specializing in controller-connected systems and modern web environments for operations.
- Specialty: Strongest where plant-floor systems, PLC/SCADA integration, operations data, and operator-facing software meet.
- Core capabilities: PLC/controller integration, SCADA/HMI, industrial networking, controls modernization, startup/commissioning, historian/SQL/reporting, custom Phoenix/Ash applications
- Adjacent capabilities: Internal portals, dashboards, OEE, MES-lite, maintenance tooling, AI analytics, general software delivery
- Target industries: Food & beverage, packaging, water/wastewater, biotech/pharma, warehousing/logistics, manufacturing
- Preferred engagements: Controller/SCADA upgrades, operations software, integration-heavy modernization, visibility systems, support retainers
- Disqualifiers: Staff augmentation, commodity public works, generic marketing websites, enterprise IT-only, prime electrical contracting
- Voice: Pragmatic, technically grounded, concise, direct.

ACTIVE PROFILE MODE: industrial_plus_software
Mode includes: operations portal, production reporting, historian, sql, api integration, dashboard, traceability, maintenance workflow, custom software, workflow software
Mode excludes: generic marketing website, enterprise IT only, staff augmentation

YOUR MISSION
Search for companies that would be good prospects for Gnome. Look for SPECIFIC, VERIFIABLE signals:
- Hiring signals: job postings for controls engineers, automation techs, PLC programmers
- Expansion signals: new facility, new production line, capacity increase, capital improvement
- Legacy/pain signals: old equipment mentions, manual processes, compliance gaps, downtime issues
- Active buying: RFPs, solicitations, project announcements

SCORING RUBRIC — assess each company yourself:

FIT SCORE (0-100):
- Industry alignment (40 points max):
  * brewery/beverage/food/packaging/water/biotech/pharma/warehouse/logistics = 40
  * general manufacturing = 34
  * plastics/cosmetic/aerospace/chemical = 30
  * machine shop/metal fab/cannabis/medical device = 10 (avoid)
  * other = 18
- Service match (30 points max):
  * Controller terms (PLC, SCADA, HMI, controls, automation) found = 30
  * Operations software + industrial context = 28
  * Operations software + broad software mode = 24
  * Operations context only = 20
  * Operations software alone = 10
  * other = 8
- Geography (15 points max):
  * Orange County, Los Angeles, Inland Empire (Riverside, San Bernardino, Corona, Fontana, Ontario, Rancho Cucamonga) = 15
  * San Diego = 12
  * Other SoCal = 12
  * Rest of California = 8
  * National = 4
- Company size (15 points max):
  * 50-500 employees = 15 (sweet spot)
  * 20-50 or 500-1000 = 10
  * >1000 = 6
  * <20 = 5
  * unknown = 8

INTENT SCORE (0-100):
- Baseline: 35
- +30 if active buying (RFP, RFQ, bid, solicitation) OR controller-specific mentions
- +18 if expansion signals (new line, new facility, capital project, commissioning, retrofit)
- +16 if pain/legacy signals (obsolete equipment, manual processes, compliance pressure, downtime)
- +10 if operations software fit
- -15 if staff augmentation
- -20 if excluded keywords present

HARD REJECTS — skip entirely:
- HVAC, plumbing, roofing, janitorial, landscaping, paving, painting, food service, demolition
- Staff augmentation firms
- Pure marketing/SEO agencies
- Enterprise IT-only (help desk, Office 365, managed IT)
- Companies outside manufacturing/process/operations

QUALITY RULES:
1. Verify: website still active, actually in the target region, actually makes/processes something
2. Right size: 20-500 employees preferred. Skip Fortune 500 and 1-2 person shops.
3. SPECIFIC signals: "Hiring PLC programmer per Indeed posting 4/2026" — not "might need automation"
4. 3 well-researched targets > 10 vague ones
5. Use web_search to find companies, then search deeper for signals on promising ones
6. Call report_finding for every qualifying company

SEARCH STRATEGY:
- Start broad: "[industry] companies [region]", "[industry] manufacturers [city]"
- Then go deep on promising hits: "[company name] hiring", "[company name] expansion", "[company name] jobs Indeed"
- Look at job boards, news, industry directories, company websites
- Cross-reference: if a company looks good, verify with a second search`;

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

async function main() {
  console.error(`\nPi Target Discovery — ${providerName}/${modelId}`);
  console.error(`Query: "${query}"`);
  console.error(
    `Brave search: ${process.env.BRAVE_API_KEY ? "enabled" : "DISABLED (no BRAVE_API_KEY)"}`
  );
  console.error("".padEnd(70, "\u2014") + "\n");

  const agent = new Agent({
    initialState: {
      systemPrompt: SYSTEM_PROMPT,
      model,
      tools: [webSearch, reportFinding],
      thinkingLevel: "medium",
    },
    streamFn: streamSimple,
    getApiKey: (provider) => getEnvApiKey(provider),
    convertToLlm: (messages) => messages,
  });

  // Subscribe to events for live output
  agent.subscribe((event) => {
    switch (event.type) {
      case "tool_execution_start":
        if (event.toolName === "web_search") {
          console.error(`\u{1F50D} Searching: ${event.args?.query || "..."}`);
        }
        break;
      case "turn_end":
        // Show assistant text between tool calls
        if (event.message?.content) {
          for (const block of event.message.content) {
            if (block.type === "text" && block.text) {
              console.error(`\n\u{1F916} ${block.text}\n`);
            }
          }
        }
        break;
      case "agent_end":
        console.error("\nDiscovery complete.");
        break;
    }
  });

  const task = `Discover companies matching Gnome's ICP for: ${query}

Search the web, evaluate each company against the scoring rubric, and call report_finding for every qualifying target. Go deep — verify signals with follow-up searches. Quality over quantity.`;

  console.error("Starting discovery...\n");

  try {
    await agent.prompt(task);
    await agent.waitForIdle();
  } catch (err) {
    console.error(`\nAgent error: ${err.message}`);
  }

  // Check for API/model errors
  if (agent.state.errorMessage) {
    console.error(`\nModel error: ${agent.state.errorMessage}`);
    if (agent.state.errorMessage.includes("401") || agent.state.errorMessage.includes("authentication")) {
      console.error(`\nSet your API key: export ${providerName.toUpperCase()}_API_KEY=sk-...`);
    }
    process.exit(1);
  }

  // Print findings summary
  try {
    const findingsPath = join(__dirname, "findings.json");
    const findings = JSON.parse(readFileSync(findingsPath, "utf-8"));
    const thisRun = findings.filter(
      (f) => Date.now() - new Date(f.discovered_at).getTime() < 600_000
    );
    if (thisRun.length) {
      console.error(`\n${"=".repeat(70)}`);
      console.error(
        `DISCOVERY COMPLETE — ${thisRun.length} findings this run`
      );
      console.error("=".repeat(70));
      for (const f of thisRun) {
        console.error(
          `  ${f.tier.padEnd(8)} ${String(f.fit_score).padStart(3)}/fit ${String(f.intent_score).padStart(3)}/intent  ${f.company_name} (${f.location || "?"})`
        );
      }
    }
  } catch {}
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
