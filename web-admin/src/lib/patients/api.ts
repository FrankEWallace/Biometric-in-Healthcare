import { api } from "@/lib/api";
import type { Paginated } from "@/lib/dashboard/api";

export interface PatientListItem {
  id: number;
  full_name: string;
  hospital_patient_id: string;
  date_of_birth: string;
  gender: string;
  phone: string | null;
}

export interface PatientDetail extends PatientListItem {
  nida: string | null;
  notes: string | null;
  is_active: boolean;
}

export const STAGE_ORDER = [
  "clerk_checkin",
  "triage",
  "consultation",
  "laboratory",
  "pharmacy",
  "clerk_checkout",
] as const;
export type StageName = (typeof STAGE_ORDER)[number];

export const STAGE_LABEL: Record<StageName, string> = {
  clerk_checkin: "Check-in",
  triage: "Triage",
  consultation: "Consultation",
  laboratory: "Laboratory",
  pharmacy: "Pharmacy",
  clerk_checkout: "Check-out",
};

export interface VisitStage {
  id: number;
  visit_id: number;
  stage: StageName;
  status: "pending" | "completed";
  verified_at: string | null;
  simulated_data: Record<string, unknown> | null;
  verifiedBy: { id: number; name: string; role: string } | null;
  supervisorOverride: { id: number; status: "pending" | "approved" | "denied"; staff_note: string | null } | null;
}

export interface VisitDetail {
  id: number;
  visit_type: "pending" | "opd" | "ipd";
  status: "open" | "closed";
  opened_at: string;
  closed_at: string | null;
  reopen_count: number;
  patient: PatientDetail;
  openedBy: { id: number; name: string; role: string } | null;
  closedBy: { id: number; name: string; role: string } | null;
  stages: VisitStage[];
}

export interface VisitSummary {
  id: number;
  status: "open" | "closed";
  patient: { id: number } | null;
}

export async function getPatients(search?: string): Promise<PatientListItem[]> {
  const query = search ? `?search=${encodeURIComponent(search)}` : "";
  const page = await api.get<Paginated<PatientListItem>>(`/patients${query}`);
  return page.data;
}

export async function getVisitDetail(visitId: number): Promise<VisitDetail> {
  const { visit } = await api.get<{ visit: VisitDetail }>(`/visits/${visitId}`);
  return visit;
}

// No endpoint returns "visits for patient X" directly, so this checks today's
// open queue first (covers the common in-progress case), then today's full
// visit list (covers a visit already closed today). Visits from prior days
// aren't reachable this way — that's a real gap, not a bug.
export async function findVisitForPatient(patientId: number): Promise<VisitSummary | null> {
  const { queue } = await api.get<{ queue: VisitSummary[] }>("/queue");
  const openMatch = queue.find((v) => v.patient?.id === patientId);
  if (openMatch) return openMatch;

  const page = await api.get<Paginated<VisitSummary>>("/visits?per_page=100");
  return page.data.find((v) => v.patient?.id === patientId) ?? null;
}
