import { api } from "@/lib/api";

export interface Device {
  ip_address: string;
  user_agent: string | null;
  request_count: number;
  last_seen_at: string;
  last_staff: { id: number; name: string; role: string } | null;
  hospital: { id: number; name: string } | null;
  last_action: string | null;
}

export async function getDevices(hospitalId?: number): Promise<Device[]> {
  const query = hospitalId ? `?hospital_id=${hospitalId}` : "";
  const { devices } = await api.get<{ devices: Device[] }>(`/devices${query}`);
  return devices;
}
