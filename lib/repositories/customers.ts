import { query } from '../db';
export type CustomerRow={id:string;name:string;phone:string|null;email:string|null;service_address:string|null;created_at:string};
export async function listCustomers(limit=100){const result=await query<CustomerRow>('SELECT id,name,phone,email,service_address,created_at FROM customers ORDER BY created_at DESC LIMIT $1',[limit]);return result.rows}
export async function getCustomer(id:string){const result=await query<CustomerRow>('SELECT id,name,phone,email,service_address,created_at FROM customers WHERE id=$1',[id]);return result.rows[0]??null}
