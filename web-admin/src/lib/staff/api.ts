import { api } from "@/lib/api";

export type StaffRole = "admin" | "nurse" | "doctor" | "super_admin";

export interface StaffUser {
  id: number;
  name: string;
  username: string;
  email: string;
  role: StaffRole;
  hospital_id: number | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface StaffFormValues {
  name: string;
  username: string;
  email: string;
  password?: string;
  role: StaffRole;
  hospital_id?: number;
}

export async function getStaff(hospitalId?: number): Promise<StaffUser[]> {
  const query = hospitalId ? `?hospital_id=${hospitalId}` : "";
  const { users } = await api.get<{ users: StaffUser[] }>(`/users${query}`);
  return users;
}

export async function createStaff(values: StaffFormValues): Promise<StaffUser> {
  const { user } = await api.post<{ user: StaffUser }>("/users", values);
  return user;
}

export async function updateStaff(
  id: number,
  values: Partial<StaffFormValues> & { is_active?: boolean },
): Promise<StaffUser> {
  const { user } = await api.put<{ user: StaffUser }>(`/users/${id}`, values);
  return user;
}

export async function deactivateStaff(id: number): Promise<void> {
  await api.delete(`/users/${id}`);
}
