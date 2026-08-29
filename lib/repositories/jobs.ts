import { query } from '../db';

export type JobRow={id:string;customer_name:string|null;technician_name:string|null;status:string;scheduled_start:string|null;scheduled_end:string|null;revenue:number;material_cost:number;labor_hours:number;labor_cost:number;allocated_overhead:number};

export async function listJobs(limit=100){
  const result=await query<JobRow>(`SELECT j.id,c.name AS customer_name,u.name AS technician_name,j.status,j.scheduled_start,j.scheduled_end,j.revenue::float,j.material_cost::float,j.labor_hours::float,j.labor_cost::float,j.allocated_overhead::float FROM jobs j LEFT JOIN customers c ON c.id=j.customer_id LEFT JOIN users u ON u.id=j.technician_id ORDER BY COALESCE(j.scheduled_start,j.created_at) DESC LIMIT $1`,[limit]);
  return result.rows;
}

export async function getJob(id:string){const result=await query<JobRow>(`SELECT j.id,c.name AS customer_name,u.name AS technician_name,j.status,j.scheduled_start,j.scheduled_end,j.revenue::float,j.material_cost::float,j.labor_hours::float,j.labor_cost::float,j.allocated_overhead::float FROM jobs j LEFT JOIN customers c ON c.id=j.customer_id LEFT JOIN users u ON u.id=j.technician_id WHERE j.id=$1`,[id]);return result.rows[0]??null}
