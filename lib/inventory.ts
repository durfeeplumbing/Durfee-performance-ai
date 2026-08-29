export type InventoryItem={sku:string;description:string;onHand:number;reorderPoint:number;unitCost:number;location:string};
export type PurchaseOrderLine={sku:string;quantity:number;unitCost:number};
export function inventoryAlerts(items:InventoryItem[]){return items.filter(i=>i.onHand<=i.reorderPoint).map(i=>({...i,recommendedOrder:Math.max(i.reorderPoint*2-i.onHand,1)}))}
export function purchaseOrderTotal(lines:PurchaseOrderLine[]){return lines.reduce((sum,l)=>sum+l.quantity*l.unitCost,0)}
export function consumeInventory(item:InventoryItem,quantity:number){if(quantity<=0)throw new Error('Quantity must be positive');if(quantity>item.onHand)throw new Error('Insufficient inventory');return{...item,onHand:item.onHand-quantity}}
