import { api } from "@/lib/api";

export interface Paginated<T> {
  data: T[];
  total: number;
  per_page: number;
  current_page: number;
  last_page: number;
}

export interface Hospital {
  id: number;
  name: string;
  city: string;
  is_active: boolean;
}

export interface VisitListItem {
  id: number;
  visit_type: "pending" | "opd" | "ipd";
  status: "open" | "closed";
  opened_at: string;
  closed_at: string | null;
  patient: { id: number; full_name: string; hospital_patient_id: string } | null;
  openedBy: { id: number; name: string; role: string } | null;
}

export async function getHospitals(): Promise<Hospital[]> {
  const { hospitals } = await api.get<{ hospitals: Hospital[] }>("/hospitals");
  return hospitals;
}

export async function getPatientCount(): Promise<number> {
  const page = await api.get<Paginated<unknown>>("/patients?per_page=1");
  return page.total;
}

export async function getVerificationSummary(hospitalId?: number): Promise<{ total: number; matched: number }> {
  const scope = hospitalId ? `&hospital_id=${hospitalId}` : "";
  const [totalPage, matchedPage] = await Promise.all([
    api.get<Paginated<unknown>>(`/verify/logs?per_page=1${scope}`),
    api.get<Paginated<unknown>>(`/verify/logs?per_page=1&status=matched${scope}`),
  ]);
  return { total: totalPage.total, matched: matchedPage.total };
}

export async function getRecentVisits(): Promise<VisitListItem[]> {
  const page = await api.get<Paginated<VisitListItem>>("/visits?per_page=20");
  return page.data;
}

export async function getOpenVisitCount(): Promise<number> {
  const page = await api.get<Paginated<unknown>>("/visits?per_page=1&status=open");
  return page.total;
}
