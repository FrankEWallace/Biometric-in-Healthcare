import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

// Roles are a fixed enum on users.role (see laravel/database/migrations/
// 2026_05_17_000003_add_lifecycle_roles_to_users_table.php), not a manageable
// table — this screen is a read-only reference, not CRUD.
const ROLES = [
  {
    role: "super_admin",
    label: "Super admin",
    description:
      "Cross-hospital management: onboards facilities, assigns hospital admins, configures matcher thresholds.",
    dashboardAccess: true,
  },
  {
    role: "admin",
    label: "Admin",
    description:
      "Own-hospital management: staff accounts, patients, visit ops, audit log, geofence & device settings, emergency enrollment.",
    dashboardAccess: true,
  },
  {
    role: "clerk",
    label: "Clerk",
    description: "Patient check-in and check-out (mobile app). Registers new patients and opens/closes visits.",
    dashboardAccess: false,
  },
  {
    role: "nurse",
    label: "Nurse",
    description: "Triage stage (mobile app): vitals capture, fingerprint/face verification at check-in.",
    dashboardAccess: false,
  },
  {
    role: "doctor",
    label: "Doctor",
    description:
      "Consultation stage (mobile app): diagnosis, lab orders, prescriptions. Read-only access to EHR/insurance records.",
    dashboardAccess: false,
  },
  {
    role: "lab_technician",
    label: "Lab technician",
    description: "Laboratory stage (mobile app): records test results against a doctor's orders.",
    dashboardAccess: false,
  },
  {
    role: "pharmacist",
    label: "Pharmacist",
    description: "Pharmacy stage (mobile app): dispenses prescribed medication.",
    dashboardAccess: false,
  },
] as const;

export default function Page() {
  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <Card>
        <CardHeader>
          <CardTitle>Roles</CardTitle>
          <CardDescription>
            Roles are fixed in this system, not user-editable — this is a reference, not a management screen.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="overflow-hidden rounded-lg border bg-card">
            <Table>
              <TableHeader className="bg-muted/15">
                <TableRow>
                  <TableHead className="h-11 p-3 font-medium">Role</TableHead>
                  <TableHead className="h-11 p-3 font-medium">Access</TableHead>
                  <TableHead className="h-11 p-3 font-medium">Web dashboard</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {ROLES.map((r) => (
                  <TableRow key={r.role}>
                    <TableCell className="p-3 align-middle font-medium text-sm">{r.label}</TableCell>
                    <TableCell className="p-3 align-middle text-muted-foreground text-sm">{r.description}</TableCell>
                    <TableCell className="p-3 align-middle">
                      <Badge variant={r.dashboardAccess ? "default" : "outline"} className="px-1.5">
                        {r.dashboardAccess ? "Yes" : "Mobile app only"}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
