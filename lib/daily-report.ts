export type JobAudit = {
  jobId: string;
  revenue: number;
  grossProfitPercent: number;
  workedHours: number;
  billedHours: number;
  materialCost: number;
  invoiceComplete: boolean;
};

export function dailyExceptions(jobs: JobAudit[], gpFloor = 50) {
  return jobs.flatMap(job => {
    const issues: string[] = [];
    if (job.grossProfitPercent < gpFloor) issues.push(`GP below ${gpFloor}%`);
    if (job.workedHours > job.billedHours) issues.push("Worked time exceeds billed time");
    if (!job.invoiceComplete) issues.push("Invoice incomplete");
    if (job.revenue <= 0 && (job.workedHours > 0 || job.materialCost > 0)) issues.push("Cost recorded with no revenue");
    return issues.length ? [{ jobId: job.jobId, issues, severity: job.grossProfitPercent < gpFloor ? "high" : "medium" }] : [];
  });
}
