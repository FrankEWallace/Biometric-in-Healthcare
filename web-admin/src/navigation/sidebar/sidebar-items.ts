import {
  Fingerprint,
  Gauge,
  KanbanSquare,
  type LucideIcon,
  MapPin,
  ScrollText,
  ShieldCheck,
  SlidersHorizontal,
  Users,
} from "lucide-react";

import type { StaffRole } from "@/lib/auth/types";

export interface NavItem {
  id: string;
  title: string;
  url: string;
  icon: LucideIcon;
  roles: readonly StaffRole[];
}

export interface NavGroup {
  id: number;
  label?: string;
  items: NavItem[];
}

const ADMIN_AND_UP: readonly StaffRole[] = ["admin", "super_admin"];
const SUPER_ADMIN_ONLY: readonly StaffRole[] = ["super_admin"];

export const sidebarItems: NavGroup[] = [
  {
    id: 1,
    label: "Overview",
    items: [{ id: "dashboard", title: "Dashboard", url: "/dashboard", icon: Gauge, roles: ADMIN_AND_UP }],
  },
  {
    id: 2,
    label: "Patients & visits",
    items: [
      { id: "patients", title: "Patients", url: "/patients", icon: Fingerprint, roles: ADMIN_AND_UP },
      { id: "visit-ops", title: "Visit ops board", url: "/visit-ops", icon: KanbanSquare, roles: ADMIN_AND_UP },
    ],
  },
  {
    id: 3,
    label: "Staff & access",
    items: [
      { id: "staff", title: "Staff", url: "/staff", icon: Users, roles: ADMIN_AND_UP },
      { id: "roles", title: "Roles", url: "/roles", icon: ShieldCheck, roles: SUPER_ADMIN_ONLY },
    ],
  },
  {
    id: 4,
    label: "Security & audit",
    items: [
      { id: "audit-log", title: "Audit log", url: "/audit-log", icon: ScrollText, roles: ADMIN_AND_UP },
      {
        id: "geofence-devices",
        title: "Geofence & devices",
        url: "/geofence-devices",
        icon: MapPin,
        roles: ADMIN_AND_UP,
      },
    ],
  },
  {
    id: 5,
    label: "National",
    items: [
      { id: "facilities", title: "Facilities", url: "/facilities", icon: ShieldCheck, roles: SUPER_ADMIN_ONLY },
      {
        id: "matcher-config",
        title: "Matcher config",
        url: "/matcher-config",
        icon: SlidersHorizontal,
        roles: SUPER_ADMIN_ONLY,
      },
    ],
  },
];

export function filterSidebarByRole(groups: NavGroup[], role: StaffRole): NavGroup[] {
  return groups
    .map((group) => ({ ...group, items: group.items.filter((item) => item.roles.includes(role)) }))
    .filter((group) => group.items.length > 0);
}
