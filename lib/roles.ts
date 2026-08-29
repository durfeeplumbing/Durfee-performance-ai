export const roles = ["owner", "manager", "csr_dispatch", "technician", "marketing", "accounting"] as const;
export type Role = (typeof roles)[number];

export const permissions: Record<Role, string[]> = {
  owner: ["*"],
  manager: ["dashboard.read", "jobs.read", "dispatch.manage", "team.read", "reports.read"],
  csr_dispatch: ["customers.manage", "jobs.manage", "dispatch.manage", "csr.self.read"],
  technician: ["jobs.assigned.read", "jobs.assigned.update", "tech.self.read", "pricebook.read"],
  marketing: ["marketing.manage", "marketing.reports.read", "revenue.summary.read"],
  accounting: ["accounting.manage", "payroll.manage", "financial.reports.read"]
};

export function can(role: Role, permission: string) {
  return permissions[role].includes("*") || permissions[role].includes(permission);
}
