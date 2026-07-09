"use client";

import { useCallback, useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { deactivateFacility, getFacilities, type HospitalDetail, updateFacility } from "@/lib/facilities/api";
import { getStaff, type StaffUser } from "@/lib/staff/api";

import { FacilitiesTable } from "./_components/facilities-table";
import { FacilityFormDialog } from "./_components/facility-form-dialog";

export default function Page() {
  const [facilities, setFacilities] = useState<HospitalDetail[]>([]);
  const [staff, setStaff] = useState<StaffUser[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editing, setEditing] = useState<HospitalDetail | null>(null);

  const reload = useCallback(() => {
    setIsLoading(true);
    void Promise.all([getFacilities(), getStaff()])
      .then(([f, s]) => {
        setFacilities(f);
        setStaff(s);
      })
      .finally(() => setIsLoading(false));
  }, []);

  useEffect(() => {
    reload();
  }, [reload]);

  function openCreate() {
    setEditing(null);
    setDialogOpen(true);
  }

  function openEdit(facility: HospitalDetail) {
    setEditing(facility);
    setDialogOpen(true);
  }

  function onSaved(saved: HospitalDetail) {
    setFacilities((prev) => {
      const exists = prev.some((f) => f.id === saved.id);
      return exists ? prev.map((f) => (f.id === saved.id ? saved : f)) : [saved, ...prev];
    });
  }

  async function onDeactivate(facility: HospitalDetail) {
    await deactivateFacility(facility.id);
    setFacilities((prev) => prev.map((f) => (f.id === facility.id ? { ...f, is_active: false } : f)));
  }

  async function onActivate(facility: HospitalDetail) {
    const updated = await updateFacility(facility.id, { is_active: true });
    setFacilities((prev) => prev.map((f) => (f.id === facility.id ? updated : f)));
  }

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div>
            <CardTitle>Facilities</CardTitle>
            <CardDescription>Manage hospitals. Assign an admin from the Staff screen after onboarding.</CardDescription>
          </div>
          <Button size="sm" onClick={openCreate}>
            Add facility
          </Button>
        </CardHeader>
        <CardContent>
          <FacilitiesTable
            facilities={facilities}
            staff={staff}
            isLoading={isLoading}
            onEdit={openEdit}
            onDeactivate={onDeactivate}
            onActivate={onActivate}
          />
        </CardContent>
      </Card>

      <FacilityFormDialog open={dialogOpen} onOpenChange={setDialogOpen} facility={editing} onSaved={onSaved} />
    </div>
  );
}
