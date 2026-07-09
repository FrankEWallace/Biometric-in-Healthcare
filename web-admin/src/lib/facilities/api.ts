import { api } from "@/lib/api";

export interface HospitalDetail {
  id: number;
  name: string;
  code: string;
  city: string;
  wifi_ssid: string | null;
  gps_latitude: string | null;
  gps_longitude: string | null;
  gps_radius_meters: number | null;
  is_active: boolean;
}

export interface HospitalFormValues {
  name?: string;
  code?: string;
  city?: string;
  wifi_ssid?: string | null;
  gps_latitude?: number | null;
  gps_longitude?: number | null;
  gps_radius_meters?: number | null;
  is_active?: boolean;
}

export async function getFacilities(): Promise<HospitalDetail[]> {
  const { hospitals } = await api.get<{ hospitals: HospitalDetail[] }>("/hospitals");
  return hospitals;
}

export async function createFacility(values: HospitalFormValues): Promise<HospitalDetail> {
  const { hospital } = await api.post<{ hospital: HospitalDetail }>("/hospitals", values);
  return hospital;
}

export async function updateFacility(id: number, values: HospitalFormValues): Promise<HospitalDetail> {
  const { hospital } = await api.put<{ hospital: HospitalDetail }>(`/hospitals/${id}`, values);
  return hospital;
}

export async function deactivateFacility(id: number): Promise<void> {
  await api.delete(`/hospitals/${id}`);
}
