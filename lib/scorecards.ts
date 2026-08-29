export type TechnicianMetrics = {
  revenue: number;
  workedHours: number;
  billedHours: number;
  opportunities: number;
  soldJobs: number;
  callbacks: number;
  reviews: number;
  grossProfitPercent: number;
};

export function technicianScorecard(m: TechnicianMetrics) {
  const closeRate = m.opportunities ? (m.soldJobs / m.opportunities) * 100 : 0;
  const revenuePerWorkedHour = m.workedHours ? m.revenue / m.workedHours : 0;
  const billableEfficiency = m.workedHours ? (m.billedHours / m.workedHours) * 100 : 0;
  const callbackPenalty = Math.min(m.callbacks * 5, 25);
  const score = Math.max(0, Math.min(100,
    m.grossProfitPercent * 0.35 +
    closeRate * 0.25 +
    Math.min(billableEfficiency, 100) * 0.25 +
    Math.min(m.reviews * 5, 15) - callbackPenalty
  ));
  return { closeRate, revenuePerWorkedHour, billableEfficiency, score };
}

export type CsrMetrics = { inboundCalls: number; bookedCalls: number; missedCalls: number; revenueBooked: number };
export function csrScorecard(m: CsrMetrics) {
  const bookingRate = m.inboundCalls ? (m.bookedCalls / m.inboundCalls) * 100 : 0;
  const revenuePerBookedCall = m.bookedCalls ? m.revenueBooked / m.bookedCalls : 0;
  return { bookingRate, revenuePerBookedCall, missedCallRate: m.inboundCalls ? (m.missedCalls / m.inboundCalls) * 100 : 0 };
}
