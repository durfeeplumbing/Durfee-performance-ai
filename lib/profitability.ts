export type ProfitabilityInput = {
  revenue: number;
  materialCost: number;
  laborHours: number;
  laborCostPerHour: number;
  allocatedOverhead?: number;
};

export function calculateProfitability(input: ProfitabilityInput) {
  const laborCost = input.laborHours * input.laborCostPerHour;
  const directCost = input.materialCost + laborCost + (input.allocatedOverhead ?? 0);
  const grossProfit = input.revenue - directCost;
  const grossProfitPercent = input.revenue > 0 ? (grossProfit / input.revenue) * 100 : 0;
  return { laborCost, directCost, grossProfit, grossProfitPercent };
}

export function requiredRevenueForGrossProfit(cost: number, targetGrossProfitPercent = 50) {
  if (targetGrossProfitPercent >= 100 || targetGrossProfitPercent < 0) throw new Error("Gross profit target must be between 0 and 100.");
  return cost / (1 - targetGrossProfitPercent / 100);
}

export function marginGuard(grossProfitPercent: number, floor = 50) {
  if (grossProfitPercent < floor) return { status: "alert" as const, message: `Projected GP ${grossProfitPercent.toFixed(1)}% is below the ${floor}% floor.` };
  return { status: "healthy" as const, message: `Projected GP ${grossProfitPercent.toFixed(1)}% meets the ${floor}% floor.` };
}
