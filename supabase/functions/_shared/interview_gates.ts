export type DecisionGateRecord = {
  decision_key?: string | null;
  status?: string | null;
  lock_state?: string | null;
  confirmed_by_turn_id?: string | null;
};

export function isExplicitlyConfirmedBusinessType(decision: DecisionGateRecord): boolean {
  return String(decision.decision_key ?? "") === "business_type" &&
    String(decision.status ?? "") === "USER_SAID" &&
    String(decision.lock_state ?? "") === "locked" &&
    String(decision.confirmed_by_turn_id ?? "").trim().length > 0;
}

export function hasExplicitlyConfirmedBusinessType(decisions: Array<DecisionGateRecord>): boolean {
  return decisions.some((decision) => isExplicitlyConfirmedBusinessType(decision));
}
