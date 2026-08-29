import { query } from '../db';
export type PriceBookRow={id:string;code:string;category:string;name:string;description:string|null;material_cost:number;labor_hours:number;overhead:number;target_gp:number;active:boolean};
export async function listPriceBookItems(activeOnly=true){const result=await query<PriceBookRow>(`SELECT id,code,category,name,description,material_cost::float,labor_hours::float,overhead::float,target_gp::float,active FROM price_book_items WHERE ($1::boolean=false OR active=true) ORDER BY category,name`,[activeOnly]);return result.rows}
