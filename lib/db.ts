import { Pool, type PoolClient, type QueryResultRow } from 'pg';

declare global { var durfeeDbPool: Pool | undefined }

function createPool(){
  const connectionString=process.env.DATABASE_URL;
  if(!connectionString)throw new Error('DATABASE_URL is not configured');
  return new Pool({connectionString,ssl:process.env.DATABASE_SSL==='true'?{rejectUnauthorized:false}:undefined,max:10});
}

export function db(){
  if(!global.durfeeDbPool)global.durfeeDbPool=createPool();
  return global.durfeeDbPool;
}

export async function query<T extends QueryResultRow>(text:string,values:unknown[]=[]){
  return db().query<T>(text,values);
}

export async function transaction<T>(work:(client:PoolClient)=>Promise<T>){
  const client=await db().connect();
  try{await client.query('BEGIN');const result=await work(client);await client.query('COMMIT');return result}catch(error){await client.query('ROLLBACK');throw error}finally{client.release()}
}
