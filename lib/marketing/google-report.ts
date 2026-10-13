import 'server-only';
export type AnalyticsTable={rows:Record<string,string|number>[];error?:string;truncated?:boolean;thresholded?:boolean;sampled?:boolean;otherRow?:boolean};
export type WebsiteAnalytics={days:number;timeZone?:string;fetchedAt:string;totals:AnalyticsTable;pages:AnalyticsTable;events:AnalyticsTable;sources:AnalyticsTable;error?:string};
export async function websiteAnalytics(days:number):Promise<WebsiteAnalytics|null>{
 if(process.env.GOOGLE_REPORT_ENABLED!=='true')return null;
 const secret=process.env.PERFORMANCE_REPORT_SECRET;if(!secret)return null;
 try{const r=await fetch(`https://durfee-google-direct.fishhappens.chatgpt.site/api/performance-report?days=${days}`,{headers:{Authorization:'Bearer '+secret,'OAI-Sites-Authorization':'Bearer '+(process.env.GOOGLE_REPORT_SITE_TOKEN||'')},cache:'no-store',signal:AbortSignal.timeout(45000)});if(!r.ok)return null;return await r.json() as WebsiteAnalytics;}catch{return null;}
}
