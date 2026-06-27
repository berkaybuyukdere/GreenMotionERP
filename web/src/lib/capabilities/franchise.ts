import { normalizeRoleKey } from "@/lib/firestore/userAccess";

/** Aggregated office-operation KPI / totals — admin tier and above only. */
export function canViewOfficeOperationTotals(userProfile: { role?: string | null } | null | undefined): boolean {
  const r = String(userProfile?.role || "").toLowerCase().trim();
  return r === "globaladmin" || r === "superadmin" || r === "admin";
}

/** Legacy financial/analytics gate — same tier as office operation totals. */
export function canViewFinancialData(userProfile: { role?: string | null } | null | undefined): boolean {
  return canViewOfficeOperationTotals(userProfile);
}

export function isSabihaFranchiseId(franchiseId: string | null | undefined): boolean {
  const id = String(franchiseId || "").toUpperCase();
  return id.includes("SABIHA") || id.includes("SAW");
}

export function isGermanyFranchiseId(franchiseId: string | null | undefined): boolean {
  return String(franchiseId || "").toUpperCase().startsWith("DE");
}

export function isTurkeyFranchiseId(franchiseId: string | null | undefined): boolean {
  return String(franchiseId || "").toUpperCase().startsWith("TR");
}

export function isSwissFranchiseId(franchiseId: string | null | undefined): boolean {
  return String(franchiseId || "").toUpperCase().startsWith("CH");
}

export function canUseOfficeReturns(franchiseId: string | null | undefined): boolean {
  const id = String(franchiseId || "").toUpperCase();
  return id.startsWith("TR") || id.startsWith("CH");
}

export function swissStyleReportPdfEnabled(franchiseId: string | null | undefined): boolean {
  const id = String(franchiseId || "").trim().toUpperCase();
  return id.startsWith("CH") || id.startsWith("DE");
}

export function canUseParkedCheckout(franchiseId: string | null | undefined): boolean {
  const id = String(franchiseId || "").toUpperCase();
  return id.startsWith("TR") || id.startsWith("CH");
}

export function canUseOperationsHub(franchiseId: string | null | undefined): boolean {
  return isTurkeyFranchiseId(franchiseId);
}

export function canUseFileLibrary(franchiseId: string | null | undefined): boolean {
  return isSwissFranchiseId(franchiseId);
}

export function canUseExcelWorkspace(franchiseId: string | null | undefined): boolean {
  return isSwissFranchiseId(franchiseId);
}

export function canAccessCHOperationsPanel(
  userProfile: { role?: string | null } | null | undefined,
  franchiseId: string | null | undefined,
): boolean {
  if (!isSwissFranchiseId(franchiseId)) return false;
  const r = normalizeRoleKey(userProfile?.role);
  return r === "admin" || r === "superadmin" || r === "globaladmin" || r === "manager";
}

export function bookingCodeLabelForFranchise(franchiseId: string | null | undefined): string {
  if (isTurkeyFranchiseId(franchiseId)) return "NAV Code";
  if (isGermanyFranchiseId(franchiseId)) return "RNT Code";
  return "RES Code";
}

export function isGarageOnlyRole(userProfile: { role?: string | null } | null | undefined): boolean {
  return normalizeRoleKey(userProfile?.role) === "garage";
}

export function canAccessFrontDeskCustomersWeb(userProfile: { role?: string | null } | null | undefined): boolean {
  return !isGarageOnlyRole(userProfile);
}

export function canManageVehicleCategoriesWeb(userProfile: { role?: string | null } | null | undefined): boolean {
  const r = normalizeRoleKey(userProfile?.role);
  return r === "manager" || r === "admin" || r === "superadmin" || r === "globaladmin";
}

export function canViewAnalytics(userProfile: { role?: string | null } | null | undefined): boolean {
  return canViewFinancialData(userProfile);
}

export function canUseStripeFinancial(
  userProfile: { role?: string | null } | null | undefined,
  franchiseId: string | null | undefined,
): boolean {
  return isSwissFranchiseId(franchiseId) && canViewFinancialData(userProfile);
}
