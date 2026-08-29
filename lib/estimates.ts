export type EstimateOption={name:'Good'|'Better'|'Best';description:string;price:number;cost:number};
export function estimateOption(name:EstimateOption['name'],description:string,cost:number,targetGp:number):EstimateOption{if(targetGp<0||targetGp>=100)throw new Error('targetGp must be >= 0 and < 100');return{name,description,cost,price:cost/(1-targetGp/100)}}
export function estimateGp(option:EstimateOption){return option.price?((option.price-option.cost)/option.price)*100:0}
export type Approval={estimateId:string;optionName:string;customerName:string;approvedAt:string;signatureReference?:string};
export function approveEstimate(estimateId:string,optionName:string,customerName:string,signatureReference?:string):Approval{if(!estimateId||!optionName||!customerName)throw new Error('Estimate, option and customer are required');return{estimateId,optionName,customerName,approvedAt:new Date().toISOString(),signatureReference}}
