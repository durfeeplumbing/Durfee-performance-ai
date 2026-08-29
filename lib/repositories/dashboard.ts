import { query } from '../db';

export type DashboardMetrics={revenue:number;grossProfitPercent:number;averageTicket:number;completedJobs:number;bookedCalls:number;unbilledRisk:number};

export async function getDashboardMetrics():Promise<DashboardMetrics>{
  const result=await query<DashboardMetrics>(`
    WITH today_jobs AS (
      SELECT * FROM jobs WHERE created_at >= date_trunc('day', NOW())
    ), totals AS (
      SELECT COALESCE(SUM(revenue),0)::float AS revenue,
             COALESCE(SUM(material_cost+labor_cost+allocated_overhead),0)::float AS cost,
             COUNT(*) FILTER (WHERE completed_at IS NOT NULL)::int AS "completedJobs",
             COUNT(*) FILTER (WHERE status IN ('booked','scheduled','dispatched','on_site'))::int AS "bookedCalls"
      FROM today_jobs
    )
    SELECT revenue,
           CASE WHEN revenue>0 THEN ((revenue-cost)/revenue*100) ELSE 0 END::float AS "grossProfitPercent",
           CASE WHEN "completedJobs">0 THEN revenue/"completedJobs" ELSE 0 END::float AS "averageTicket",
           "completedJobs","bookedCalls",0::float AS "unbilledRisk"
    FROM totals`);
  return result.rows[0]??{revenue:0,grossProfitPercent:0,averageTicket:0,completedJobs:0,bookedCalls:0,unbilledRisk:0};
}
