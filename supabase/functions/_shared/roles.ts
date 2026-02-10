export const ROLE_IDS = [1,2,3,4,5,6,7,8,9,10] as const;

export const ROLE_META: Record<number, { key: string; title: string }> = {
  1: { key: "NORTH_STAR", title: "North Star" },
  2: { key: "USER_STORY_MAP", title: "User Story Map" },
  3: { key: "SCOPE_BOUNDARY", title: "Scope Boundary" },
  4: { key: "FEATURES_PRIORITIZED", title: "Features Prioritized" },
  5: { key: "DATA_MODEL", title: "Data Model" },
  6: { key: "INTEGRATIONS", title: "Integrations" },
  7: { key: "UX_NOTES", title: "UX Notes" },
  8: { key: "RISKS_OPEN_QUESTIONS", title: "Risks & Open Questions" },
  9: { key: "BUILD_PLAN", title: "Build Plan" },
  10: { key: "ACCEPTANCE_TESTS", title: "Acceptance Tests" },
};

export type TrustLabel = "USER_SAID" | "ASSUMED" | "UNKNOWN";

export function isTrustLabel(value: string): value is TrustLabel {
  return value === "USER_SAID" || value === "ASSUMED" || value === "UNKNOWN";
}
