export const jobStatuses=['lead','booked','scheduled','dispatched','on_site','estimate_sent','approved','work_in_progress','completed','invoiced','paid','closed','cancelled'] as const;
export type JobStatus=(typeof jobStatuses)[number];
const transitions:Record<JobStatus,JobStatus[]>={lead:['booked','cancelled'],booked:['scheduled','cancelled'],scheduled:['dispatched','cancelled'],dispatched:['on_site','scheduled'],on_site:['estimate_sent','work_in_progress'],estimate_sent:['approved','cancelled'],approved:['work_in_progress','scheduled'],work_in_progress:['completed'],completed:['invoiced'],invoiced:['paid'],paid:['closed'],closed:[],cancelled:[]};
export function canTransition(from:JobStatus,to:JobStatus){return transitions[from].includes(to)}
export function transitionJob(from:JobStatus,to:JobStatus){if(!canTransition(from,to))throw new Error(`Invalid job transition: ${from} -> ${to}`);return{from,to,changedAt:new Date().toISOString()}}
