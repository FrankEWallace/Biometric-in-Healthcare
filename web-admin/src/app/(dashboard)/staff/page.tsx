"use client";

import { useCallback, useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useAuth } from "@/lib/auth/auth-context";
import { getHospitals, type Hospital } from "@/lib/dashboard/api";
import { deactivateStaff, getStaff, type StaffRole, type StaffUser, updateStaff } from "@/lib/staff/api";

import { StaffFormDialog } from "./_components/staff-form-dialog";
import { StaffTable } from "./_components/staff-table";

export default function Page() {
  const { user } = useAuth();
  const isSuperAdmin = user?.role === "super_admin";
  const allowedRoles: StaffRole[] = isSuperAdmin
    ? ["admin", "nurse", "doctor", "super_admin"]
    : ["admin", "nurse", "doctor"];

  const [staff, setStaff] = useState<StaffUser[]>([]);
  const [hospitals, setHospitals] = useState<Hospital[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<StaffUser | null>(null);

  const reload = useCallback(() => {
    setIsLoading(true);
    void getStaff()
      .then(setStaff)
      .finally(() => setIsLoading(false));
  }, []);

  useEffect(() => {
    if (!user) return;
    reload();
    if (isSuperAdmin) {
      void getHospitals().then(setHospitals);
    } else if (user.hospital) {
      setHospitals([{ id: user.hospital.id, name: user.hospital.name, city: "", is_active: true }]);
    }
  }, [user, isSuperAdmin, reload]);

  function openCreate() {
    setEditing(null);
    setDialogOpen(true);
  }

  function openEdit(member: StaffUser) {
    setEditing(member);
    setDialogOpen(true);
  }

  function onSaved(saved: StaffUser) {
    setStaff((prev) => {
      const exists = prev.some((m) => m.id === saved.id);
      return exists ? prev.map((m) => (m.id === saved.id ? saved : m)) : [saved, ...prev];
    });
  }

  async function onDeactivate(member: StaffUser) {
    await deactivateStaff(member.id);
    setStaff((prev) => prev.map((m) => (m.id === member.id ? { ...m, is_active: false } : m)));
  }

  async function onActivate(member: StaffUser) {
    const updated = await updateStaff(member.id, { is_active: true });
    setStaff((prev) => prev.map((m) => (m.id === member.id ? updated : m)));
  }

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div>
            <CardTitle>Staff</CardTitle>
            <CardDescription>
              Manage staff accounts for {isSuperAdmin ? "all hospitals" : "your hospital"}.
            </CardDescription>
          </div>
          <Button size="sm" onClick={openCreate}>
            Add staff
          </Button>
        </CardHeader>
        <CardContent>
          <StaffTable
            staff={staff}
            hospitals={hospitals}
            isSuperAdmin={isSuperAdmin}
            isLoading={isLoading}
            onEdit={openEdit}
            onDeactivate={onDeactivate}
            onActivate={onActivate}
          />
        </CardContent>
      </Card>

      <StaffFormDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        staff={editing}
        allowedRoles={allowedRoles}
        hospitals={hospitals}
        isSuperAdmin={isSuperAdmin}
        onSaved={onSaved}
      />
    </div>
  );
}
