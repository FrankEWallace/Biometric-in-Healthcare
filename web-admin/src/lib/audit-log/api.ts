import { api } from "@/lib/api";
import type { Paginated } from "@/lib/dashboard/api";

export const AUDIT_ACTIONS = [
  "ehr_access",
  "insurance_check",
  "fingerprint_match",
  "fingerprint_no_match",
  "fingerprint_enroll",
  "fingerprint_delete",
  "fingerprint_lock",
  "fingerprint_unlock",
  "patient_create",
  "patient_update",
  "patient_delete",
  "manual_override",
  "edit_request_submitted",
  "edit_request_approved",
  "edit_request_rejected",
  "edit_request_cancelled",
  "login_success",
  "login_failed",
  "user_created",
  "user_deactivated",
  "hospital_created",
  "hospital_deactivated",
  "face_enroll",
  "face_match",
  "face_no_match",
  "face_manual_confirm",
  "visit_open",
  "visit_close",
  "visit_reopen",
  "stage_verified",
  "stage_override_requested",
  "stage_override_resolved",
] as const;

export type AuditAction = (typeof AUDIT_ACTIONS)[number];

export interface AuditLogEntry {
  id: number;
  action: string;
  response_status: string | null;
  created_at: string;
  staff: { id: number; name: string; role: string } | null;
  patient: { id: number; full_name: string } | null;
}

export interface AuditLogFilters {
  action?: string;
  staff_id?: number;
  from?: string;
  to?: string;
  page?: number;
}

export async function getAuditLogs(filters: AuditLogFilters): Promise<Paginated<AuditLogEntry>> {
  const params = new URLSearchParams();
  if (filters.action) params.set("action", filters.action);
  if (filters.staff_id) params.set("staff_id", String(filters.staff_id));
  if (filters.from) params.set("from", filters.from);
  if (filters.to) params.set("to", filters.to);
  if (filters.page) params.set("page", String(filters.page));
  params.set("per_page", "25");

  return api.get<Paginated<AuditLogEntry>>(`/audit-logs?${params.toString()}`);
}
