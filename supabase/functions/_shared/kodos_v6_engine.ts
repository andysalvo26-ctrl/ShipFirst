export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export type ErrorLayer = "auth" | "authorization" | "validation" | "schema" | "transient" | "server";

export type SlotKey =
  | "app_type"
  | "primary_user"
  | "primary_outcome"
  | "core_flow"
  | "trust_priority"
  | "monetization_timing"
  | "brand_style"
  | "signature_detail";

export type BriefDocKey = "app_vision_brief" | "mvp_blueprint" | "owner_control_brief";

export type SlotDefinition = {
  key: SlotKey;
  label: string;
  required: boolean;
  prompt: string;
  options: Array<{ id: string; label: string; value: string }>;
};

export type SlotValue = {
  slotKey: SlotKey;
  slotLabel: string;
  value: string;
  status: "captured" | "assumed" | "confirmed";
  confidence: number;
  evidence: string[];
};

export type QuestionOption = {
  id: string;
  label: string;
};

export type NextQuestion = {
  key: SlotKey;
  prompt: string;
  options: QuestionOption[];
  allowFreeText: boolean;
};

export type ReadinessState = {
  state: "not_ready" | "ready";
  reason: string;
  resolvedRequired: number;
  totalRequired: number;
  missingRequired: SlotKey[];
  missingOptional: SlotKey[];
};

export type BriefDoc = {
  key: BriefDocKey;
  title: string;
  body: string;
};

export type GeneratedBrief = {
  docs: BriefDoc[];
  internalBuildContract: Record<string, unknown>;
};

const SLOT_DEFINITIONS: SlotDefinition[] = [
  {
    key: "app_type",
    label: "App type",
    required: true,
    prompt: "What kind of app are you creating?",
    options: [
      { id: "app_type:store", label: "An online store", value: "Online store" },
      { id: "app_type:booking", label: "A booking app", value: "Booking app" },
      { id: "app_type:content", label: "A content/community app", value: "Content and community app" },
      { id: "app_type:service", label: "A service workflow app", value: "Service workflow app" },
    ],
  },
  {
    key: "primary_user",
    label: "Primary user",
    required: true,
    prompt: "Who is the main user for version one?",
    options: [
      { id: "primary_user:consumer", label: "Everyday consumers", value: "Everyday consumers" },
      { id: "primary_user:small_biz", label: "Small business owners", value: "Small business owners" },
      { id: "primary_user:teams", label: "Internal teams", value: "Internal teams" },
      { id: "primary_user:members", label: "Members or subscribers", value: "Members or subscribers" },
    ],
  },
  {
    key: "primary_outcome",
    label: "Primary outcome",
    required: true,
    prompt: "What should users accomplish first in your app?",
    options: [
      { id: "primary_outcome:browse_buy", label: "Find and buy quickly", value: "Find and buy quickly" },
      { id: "primary_outcome:book", label: "Book in a few taps", value: "Book in a few taps" },
      { id: "primary_outcome:publish", label: "Create or publish content", value: "Create or publish content" },
      { id: "primary_outcome:organize", label: "Track and organize work", value: "Track and organize work" },
    ],
  },
  {
    key: "core_flow",
    label: "Core flow",
    required: true,
    prompt: "Which flow matters most for your MVP?",
    options: [
      { id: "core_flow:discover_checkout", label: "Discover -> choose -> checkout", value: "Discover, choose, and checkout" },
      { id: "core_flow:onboard_action", label: "Onboard -> first action", value: "Onboard and complete first action" },
      { id: "core_flow:search_filter", label: "Search -> filter -> select", value: "Search, filter, and select" },
      { id: "core_flow:dashboard_task", label: "Dashboard -> task completion", value: "Dashboard-driven task completion" },
    ],
  },
  {
    key: "trust_priority",
    label: "Trust priority",
    required: true,
    prompt: "What must feel trustworthy on day one?",
    options: [
      { id: "trust_priority:payments", label: "Safe payments", value: "Safe and reliable payments" },
      { id: "trust_priority:privacy", label: "Privacy and account security", value: "Privacy and account security" },
      { id: "trust_priority:fulfillment", label: "Reliable delivery and updates", value: "Reliable delivery and status updates" },
      { id: "trust_priority:support", label: "Clear support and policies", value: "Clear support and policy transparency" },
    ],
  },
  {
    key: "monetization_timing",
    label: "Monetization timing",
    required: true,
    prompt: "Do you want monetization in version one?",
    options: [
      { id: "monetization_timing:launch", label: "Yes, at launch", value: "Monetization included in version one" },
      { id: "monetization_timing:later", label: "Later, after launch", value: "Monetization deferred until post-launch" },
      { id: "monetization_timing:free", label: "No, free product first", value: "Free-first launch without monetization" },
      { id: "monetization_timing:hybrid", label: "Light monetization only", value: "Light monetization with basic checkout" },
    ],
  },
  {
    key: "brand_style",
    label: "Brand style",
    required: false,
    prompt: "How should the app feel to your users?",
    options: [
      { id: "brand_style:clean", label: "Clean and modern", value: "Clean and modern" },
      { id: "brand_style:bold", label: "Bold and energetic", value: "Bold and energetic" },
      { id: "brand_style:warm", label: "Warm and friendly", value: "Warm and friendly" },
      { id: "brand_style:premium", label: "Premium and minimal", value: "Premium and minimal" },
    ],
  },
  {
    key: "signature_detail",
    label: "Signature detail",
    required: false,
    prompt: "What should make users say \"this feels like your app\"?",
    options: [
      { id: "signature_detail:curation", label: "Curated recommendations", value: "Curated recommendations" },
      { id: "signature_detail:story", label: "Strong story and brand voice", value: "Distinct story and brand voice" },
      { id: "signature_detail:speed", label: "Fast and simple actions", value: "Fast and simple core actions" },
      { id: "signature_detail:community", label: "Community feel", value: "Community-driven experience" },
    ],
  },
];

export const REQUIRED_SLOT_KEYS = SLOT_DEFINITIONS.filter((slot) => slot.required).map((slot) => slot.key);
export const OPTIONAL_SLOT_KEYS = SLOT_DEFINITIONS.filter((slot) => !slot.required).map((slot) => slot.key);

export function slotDefinition(slotKey: SlotKey): SlotDefinition {
  return SLOT_DEFINITIONS.find((item) => item.key === slotKey) ?? SLOT_DEFINITIONS[0];
}

export function inferSlotsFromIdea(ideaSentence: string): Partial<Record<SlotKey, SlotValue>> {
  const text = normalize(ideaSentence);
  const updates: Partial<Record<SlotKey, SlotValue>> = {};

  const appType = detectAppType(text);
  if (appType) {
    updates.app_type = {
      slotKey: "app_type",
      slotLabel: slotDefinition("app_type").label,
      value: appType,
      status: "captured",
      confidence: 0.58,
      evidence: [ideaSentence.slice(0, 240)],
    };
  }

  const primaryOutcome = detectPrimaryOutcome(text);
  if (primaryOutcome) {
    updates.primary_outcome = {
      slotKey: "primary_outcome",
      slotLabel: slotDefinition("primary_outcome").label,
      value: primaryOutcome,
      status: "captured",
      confidence: 0.56,
      evidence: [ideaSentence.slice(0, 240)],
    };
  }

  const monetization = detectMonetization(text);
  if (monetization) {
    updates.monetization_timing = {
      slotKey: "monetization_timing",
      slotLabel: slotDefinition("monetization_timing").label,
      value: monetization,
      status: "captured",
      confidence: 0.54,
      evidence: [ideaSentence.slice(0, 240)],
    };
  }

  return updates;
}

export function updateFromAnswer(input: {
  questionKey?: string;
  selectedOptionId?: string;
  freeText?: string;
  fallbackMessage?: string;
}): Partial<Record<SlotKey, SlotValue>> {
  const updates: Partial<Record<SlotKey, SlotValue>> = {};
  const qKey = normalize(input.questionKey ?? "");
  const selected = normalize(input.selectedOptionId ?? "");
  const freeText = trim(input.freeText ?? "");

  const slot = SLOT_DEFINITIONS.find((item) => item.key === qKey);
  if (slot) {
    const option = slot.options.find((item) => item.id === selected);
    if (option) {
      updates[slot.key] = {
        slotKey: slot.key,
        slotLabel: slot.label,
        value: option.value,
        status: "confirmed",
        confidence: 0.82,
        evidence: [option.label],
      };
      return updates;
    }
    if (freeText.length > 0) {
      updates[slot.key] = {
        slotKey: slot.key,
        slotLabel: slot.label,
        value: freeText,
        status: "confirmed",
        confidence: 0.76,
        evidence: [freeText.slice(0, 280)],
      };
      return updates;
    }
  }

  if (freeText.length > 0) {
    const detected = inferSlotsFromIdea(freeText);
    for (const [k, value] of Object.entries(detected)) {
      updates[k as SlotKey] = {
        ...value,
        status: "confirmed",
        confidence: Math.max(value?.confidence ?? 0.45, 0.7),
      };
    }
  } else if (input.fallbackMessage) {
    const detected = inferSlotsFromIdea(input.fallbackMessage);
    for (const [k, value] of Object.entries(detected)) {
      updates[k as SlotKey] = value;
    }
  }

  return updates;
}

export function evaluateReadiness(slotMap: Partial<Record<SlotKey, SlotValue>>): ReadinessState {
  const missingRequired = REQUIRED_SLOT_KEYS.filter((key) => !slotMap[key]);
  const missingOptional = OPTIONAL_SLOT_KEYS.filter((key) => !slotMap[key]);
  const resolvedRequired = REQUIRED_SLOT_KEYS.length - missingRequired.length;
  const totalRequired = REQUIRED_SLOT_KEYS.length;

  if (missingRequired.length > 0) {
    const nextLabel = slotDefinition(missingRequired[0]).label.toLowerCase();
    return {
      state: "not_ready",
      reason: `We need a few more basics. Next: ${nextLabel}.`,
      resolvedRequired,
      totalRequired,
      missingRequired,
      missingOptional,
    };
  }

  if (missingOptional.length > 0) {
    return {
      state: "ready",
      reason: "Ready to generate. You can add one more detail if you want.",
      resolvedRequired,
      totalRequired,
      missingRequired,
      missingOptional,
    };
  }

  return {
    state: "ready",
    reason: "Ready to generate your plan.",
    resolvedRequired,
    totalRequired,
    missingRequired,
    missingOptional,
  };
}

export function chooseNextQuestion(
  slotMap: Partial<Record<SlotKey, SlotValue>>,
  includeOptional: boolean,
): NextQuestion | null {
  const readiness = evaluateReadiness(slotMap);
  const targetKey = readiness.missingRequired[0] ?? (includeOptional ? readiness.missingOptional[0] : undefined);
  if (!targetKey) return null;

  const slot = slotDefinition(targetKey);
  return {
    key: slot.key,
    prompt: slot.prompt,
    options: [
      ...slot.options.map((item) => ({ id: item.id, label: item.label })),
      { id: `${slot.key}:none_fit`, label: "None fit, I'll describe it" },
    ],
    allowFreeText: true,
  };
}

export async function maybePersonalizeQuestion(input: {
  openAIKey: string;
  model: string;
  question: NextQuestion;
  ideaSentence: string;
  memoryHighlights: string[];
}): Promise<NextQuestion> {
  if (!input.openAIKey.trim()) return input.question;

  const context = input.memoryHighlights.slice(0, 4).join("\n- ");
  const prompt = [
    "You are rewriting one product intake question.",
    "Keep this plain language and short.",
    "Do not change the meaning of the question key.",
    "Return strict JSON with keys: prompt, options.",
    "options must be an array of 4 concise user-friendly labels.",
    `Question key: ${input.question.key}`,
    `Base prompt: ${input.question.prompt}`,
    `Idea sentence: ${input.ideaSentence}`,
    `Memory highlights:\n- ${context || "none"}`,
  ].join("\n\n");

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${input.openAIKey}`,
      },
      body: JSON.stringify({
        model: input.model,
        temperature: 0.2,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: "Rewrite product intake copy in plain language." },
          { role: "user", content: prompt },
        ],
      }),
    });

    if (!response.ok) return input.question;
    const json = await response.json();
    const content = String(json.choices?.[0]?.message?.content ?? "").trim();
    if (!content) return input.question;

    const parsed = JSON.parse(content) as { prompt?: string; options?: string[] };
    const rewrittenPrompt = trim(parsed.prompt ?? "");
    const optionLabels = Array.isArray(parsed.options)
      ? parsed.options.map((item) => trim(String(item))).filter((item) => item.length > 0)
      : [];

    if (!rewrittenPrompt) return input.question;

    const existingIds = input.question.options.map((option) => option.id).filter((id) => !id.endsWith(":none_fit"));
    const safeOptions = optionLabels.length >= 3
      ? optionLabels.slice(0, existingIds.length).map((label, index) => ({ id: existingIds[index] ?? `${input.question.key}:opt_${index + 1}`, label }))
      : input.question.options.filter((option) => !option.id.endsWith(":none_fit"));

    return {
      key: input.question.key,
      prompt: rewrittenPrompt,
      options: [...safeOptions, { id: `${input.question.key}:none_fit`, label: "None fit, I'll describe it" }],
      allowFreeText: true,
    };
  } catch {
    return input.question;
  }
}

export async function createEmbedding(openAIKey: string, text: string): Promise<number[] | null> {
  if (!openAIKey.trim()) return null;
  const trimmed = trim(text);
  if (!trimmed) return null;

  try {
    const response = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openAIKey}`,
      },
      body: JSON.stringify({
        model: "text-embedding-3-small",
        input: trimmed,
      }),
    });

    if (!response.ok) return null;
    const json = await response.json();
    const vector = json.data?.[0]?.embedding;
    if (!Array.isArray(vector)) return null;
    return vector.map((v: unknown) => Number(v)).filter((v: number) => Number.isFinite(v));
  } catch {
    return null;
  }
}

export function hashSource(text: string): string {
  const input = trim(text);
  let hash = 2166136261;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  return `fnv1a_${(hash >>> 0).toString(16)}`;
}

export async function generateBrief(input: {
  openAIKey: string;
  model: string;
  title: string;
  ideaSentence: string;
  websiteUrl?: string | null;
  slotMap: Partial<Record<SlotKey, SlotValue>>;
  memoryHighlights: string[];
  generationMode: "fast" | "improve";
}): Promise<GeneratedBrief> {
  const fallback = buildFallbackBrief(input);
  if (!input.openAIKey.trim()) return fallback;

  const slotSummary = Object.values(input.slotMap)
    .map((slot) => `- ${slot.slotLabel}: ${slot.value} (${slot.status})`)
    .join("\n");

  const prompt = [
    "Create 3 concise customer-facing planning documents for an app intake.",
    "Output JSON only with keys docs and internal_build_contract.",
    "docs must include exactly these doc_key values: app_vision_brief, mvp_blueprint, owner_control_brief.",
    "Each doc body must be plain language and between 140 and 260 words.",
    "Do not include implementation stack or code details.",
    "Use assumptions when details are missing.",
    `Project title: ${input.title}`,
    `Idea sentence: ${input.ideaSentence}`,
    `Website url: ${input.websiteUrl ?? "none"}`,
    `Generation mode: ${input.generationMode}`,
    `Slot summary:\n${slotSummary || "none"}`,
    `Memory highlights:\n- ${input.memoryHighlights.slice(0, 6).join("\n- ") || "none"}`,
  ].join("\n\n");

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${input.openAIKey}`,
      },
      body: JSON.stringify({
        model: input.model,
        temperature: 0.4,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: "You create customer-facing app planning briefs that are clear, practical, and non-technical.",
          },
          { role: "user", content: prompt },
        ],
      }),
    });

    if (!response.ok) return fallback;
    const json = await response.json();
    const content = String(json.choices?.[0]?.message?.content ?? "").trim();
    if (!content) return fallback;
    const parsed = JSON.parse(content) as {
      docs?: Array<{ doc_key?: string; title?: string; body?: string }>;
      internal_build_contract?: Record<string, unknown>;
    };

    const docs = normalizeDocs(parsed.docs);
    if (docs.length !== 3) return fallback;

    return {
      docs,
      internalBuildContract: parsed.internal_build_contract ?? fallback.internalBuildContract,
    };
  } catch {
    return fallback;
  }
}

export function wordCount(text: string): number {
  return trim(text).split(/\s+/).filter(Boolean).length;
}

export function jsonResponse(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...CORS_HEADERS,
    },
  });
}

export function fail(status: number, code: string, message: string, layer: ErrorLayer, details?: Record<string, unknown>): Response {
  return jsonResponse({ error: { code, message, layer, ...(details ?? {}) } }, status);
}

function normalizeDocs(rawDocs: Array<{ doc_key?: string; title?: string; body?: string }> | undefined): BriefDoc[] {
  const byKey = new Map<string, { title: string; body: string }>();
  for (const raw of rawDocs ?? []) {
    const key = trim(raw.doc_key ?? "");
    const title = trim(raw.title ?? "");
    const body = trim(raw.body ?? "");
    if (!key || !title || !body) continue;
    byKey.set(key, { title, body });
  }

  const keys: BriefDocKey[] = ["app_vision_brief", "mvp_blueprint", "owner_control_brief"];
  return keys
    .map((key) => {
      const entry = byKey.get(key);
      if (!entry) return null;
      return { key, title: entry.title, body: entry.body } satisfies BriefDoc;
    })
    .filter((item): item is BriefDoc => item !== null);
}

function buildFallbackBrief(input: {
  title: string;
  ideaSentence: string;
  websiteUrl?: string | null;
  slotMap: Partial<Record<SlotKey, SlotValue>>;
  memoryHighlights: string[];
  generationMode: "fast" | "improve";
}): GeneratedBrief {
  const slot = (key: SlotKey, fallbackText: string) => input.slotMap[key]?.value ?? fallbackText;
  const assumptions: string[] = [];
  for (const requiredKey of REQUIRED_SLOT_KEYS) {
    if (!input.slotMap[requiredKey]) {
      assumptions.push(slotDefinition(requiredKey).label);
    }
  }

  const highlights = input.memoryHighlights.slice(0, 3);
  const highlightText = highlights.length > 0
    ? highlights.map((line) => `- ${line}`).join("\n")
    : "- The plan is based on your current answers and can be improved with more detail.";

  const appVision = [
    `${input.title} is planned as a ${slot("app_type", "focused MVP app")} for ${slot("primary_user", "its main audience")}.`,
    `The first promise is clear: users can ${slot("primary_outcome", "complete a meaningful first action quickly")}.`,
    `The product experience should feel ${slot("brand_style", "clean, clear, and reliable")} while staying simple to launch.`,
    input.websiteUrl ? `Website context is included from ${input.websiteUrl}.` : "No website context was provided, so branding assumptions are light.",
    `Signature direction: ${slot("signature_detail", "make the first experience fast and memorable")}.`,
    "\nCurrent intent highlights:\n" + highlightText,
  ].join(" ");

  const mvpBlueprint = [
    `Version one is scoped around one core flow: ${slot("core_flow", "onboard and complete the primary outcome")}.`,
    `Trust priority for launch: ${slot("trust_priority", "clear expectations and dependable behavior")}.`,
    `Monetization path: ${slot("monetization_timing", "to be finalized after launch")}.
`,
    "In scope for MVP:",
    "- The primary user flow from entry to value.",
    "- A focused set of actions that support the first outcome.",
    "- Clear messaging and confidence-building UX.",
    "Out of scope for MVP:",
    "- Broad feature expansion that slows delivery.",
    "- Advanced operational controls that belong in the owner console phase.",
    input.generationMode === "improve"
      ? "This version is in improve mode and includes stronger alignment detail."
      : "This version is optimized for a fast first draft.",
  ].join(" ");

  const ownerControl = [
    "ShipFirst will deliver the hard build and runtime foundation.",
    "The owner will control dynamic business settings in the console after delivery.",
    "Owner-editable controls include:",
    "- Catalog/content data",
    "- Pricing and offers",
    "- On-brand copy and media",
    "- Day-to-day operational toggles",
    "Assumptions still open:",
    assumptions.length > 0 ? `- ${assumptions.join(", ")}` : "- None. Core launch assumptions are sufficiently covered.",
    "These assumptions are explicit so the next pass can tighten details without blocking momentum.",
  ].join(" ");

  const docs: BriefDoc[] = [
    { key: "app_vision_brief", title: "App Vision Brief", body: appVision },
    { key: "mvp_blueprint", title: "MVP Blueprint", body: mvpBlueprint },
    { key: "owner_control_brief", title: "Owner Control Brief", body: ownerControl },
  ];

  const internalBuildContract = {
    version: "kodos-v6",
    project_title: input.title,
    required_slots: REQUIRED_SLOT_KEYS,
    resolved_slots: Object.values(input.slotMap).map((item) => ({
      key: item.slotKey,
      value: item.value,
      status: item.status,
      confidence: item.confidence,
    })),
    open_assumptions: assumptions,
    buildability_posture: assumptions.length <= 2 ? "fast_mvp" : "needs_more_alignment",
    memory_highlights: highlights,
  };

  return { docs, internalBuildContract };
}

function detectAppType(text: string): string | null {
  if (!text) return null;
  if (/(book|store|shop|commerce|checkout|catalog)/i.test(text)) return "Online store";
  if (/(bookings?|appointments?|schedule|calendar)/i.test(text)) return "Booking app";
  if (/(community|social|creator|content|media|course)/i.test(text)) return "Content and community app";
  if (/(workflow|crm|internal|ops|team|dashboard)/i.test(text)) return "Service workflow app";
  return null;
}

function detectPrimaryOutcome(text: string): string | null {
  if (!text) return null;
  if (/(buy|purchase|checkout|order)/i.test(text)) return "Find and buy quickly";
  if (/(book|reserve|appointment)/i.test(text)) return "Book in a few taps";
  if (/(post|publish|create|share)/i.test(text)) return "Create or publish content";
  if (/(track|manage|organize|monitor)/i.test(text)) return "Track and organize work";
  return null;
}

function detectMonetization(text: string): string | null {
  if (!text) return null;
  if (/(subscription|subscribe|membership|paid plan)/i.test(text)) return "Monetization included in version one";
  if (/(checkout|payment|stripe|purchase|sell)/i.test(text)) return "Monetization included in version one";
  if (/(free|no payment|later)/i.test(text)) return "Monetization deferred until post-launch";
  return null;
}

function normalize(value: string): string {
  return trim(value).toLowerCase();
}

function trim(value: string): string {
  return value.trim();
}
