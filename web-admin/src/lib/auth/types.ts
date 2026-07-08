export type StaffRole = "clerk" | "nurse" | "doctor" | "lab_technician" | "pharmacist" | "admin" | "super_admin";

export interface AuthUser {
  id: number;
  name: string;
  username: string;
  email: string;
  role: StaffRole;
  hospital_id: number | null;
  hospital: { id: number; name: string; face_recognition_enabled: boolean } | null;
}

export interface AuthSession {
  token: string;
  user: AuthUser;
}
