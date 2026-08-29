export type DispatchCandidate = {
  technicianId: string;
  skillMatch: number;
  travelMinutes: number;
  availableInMinutes: number;
  conversionRate: number;
  revenuePerHour: number;
};

export function dispatchScore(c: DispatchCandidate) {
  const skill = Math.max(0, Math.min(c.skillMatch, 100)) * 0.35;
  const travel = Math.max(0, 100 - c.travelMinutes * 2) * 0.20;
  const availability = Math.max(0, 100 - c.availableInMinutes) * 0.15;
  const conversion = Math.max(0, Math.min(c.conversionRate, 100)) * 0.20;
  const productivity = Math.min(c.revenuePerHour / 10, 100) * 0.10;
  return skill + travel + availability + conversion + productivity;
}

export function rankTechnicians(candidates: DispatchCandidate[]) {
  return candidates
    .map(candidate => ({ ...candidate, score: dispatchScore(candidate) }))
    .sort((a, b) => b.score - a.score);
}
