"use client";

import { useState } from "react";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { HospitalDetail } from "@/lib/facilities/api";
import type { StaffUser } from "@/lib/staff/api";

function TableRows({
  facilities,
  staff,
  isLoading,
  activatingId,
  onEdit,
  onDeactivateClick,
  onActivate,
}: {
  facilities: HospitalDetail[];
  staff: StaffUser[];
  isLoading: boolean;
  activatingId: number | null;
  onEdit: (facility: HospitalDetail) => void;
  onDeactivateClick: (facility: HospitalDetail) => void;
  onActivate: (facility: HospitalDetail) => void;
}) {
  if (isLoading) {
    return (
      <>
        {Array.from({ length: 5 }).map((_, i) => (
          // biome-ignore lint/suspicious/noArrayIndexKey: static loading skeleton rows
          <TableRow key={i}>
            <TableCell colSpan={5} className="p-3">
              <Skeleton className="h-6 w-full" />
            </TableCell>
          </TableRow>
        ))}
      </>
    );
  }

  if (facilities.length === 0) {
    return (
      <TableRow>
        <TableCell colSpan={5} className="h-24 text-center text-muted-foreground">
          No facilities found.
        </TableCell>
      </TableRow>
    );
  }

  return (
    <>
      {facilities.map((facility) => {
        const hospitalStaff = staff.filter((s) => s.hospital_id === facility.id);
        const admins = hospitalStaff.filter((s) => s.role === "admin" && s.is_active);
        const activeStaffCount = hospitalStaff.filter((s) => s.is_active).length;

        return (
          <TableRow key={facility.id}>
            <TableCell className="p-3 align-middle">
              <div className="grid gap-0.5">
                <span className="font-medium text-sm">{facility.name}</span>
                <span className="text-muted-foreground text-xs">
                  {facility.code} · {facility.city}
                </span>
              </div>
            </TableCell>
            <TableCell className="p-3 align-middle text-sm">
              {admins.length > 0 ? admins.map((a) => a.name).join(", ") : "—"}
            </TableCell>
            <TableCell className="p-3 align-middle text-sm">{activeStaffCount}</TableCell>
            <TableCell className="p-3 align-middle">
              <Badge variant={facility.is_active ? "default" : "outline"} className="px-1.5">
                {facility.is_active ? "Active" : "Deactivated"}
              </Badge>
            </TableCell>
            <TableCell className="p-3 text-right align-middle">
              <div className="flex justify-end gap-2">
                <Button variant="outline" size="sm" onClick={() => onEdit(facility)}>
                  Edit
                </Button>
                {facility.is_active ? (
                  <Button variant="outline" size="sm" onClick={() => onDeactivateClick(facility)}>
                    Deactivate
                  </Button>
                ) : (
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={activatingId === facility.id}
                    onClick={() => onActivate(facility)}
                  >
                    {activatingId === facility.id ? "Activating…" : "Activate"}
                  </Button>
                )}
              </div>
            </TableCell>
          </TableRow>
        );
      })}
    </>
  );
}

export function FacilitiesTable({
  facilities,
  staff,
  isLoading,
  onEdit,
  onDeactivate,
  onActivate,
}: {
  facilities: HospitalDetail[];
  staff: StaffUser[];
  isLoading: boolean;
  onEdit: (facility: HospitalDetail) => void;
  onDeactivate: (facility: HospitalDetail) => Promise<void>;
  onActivate: (facility: HospitalDetail) => Promise<void>;
}) {
  const [pendingDeactivate, setPendingDeactivate] = useState<HospitalDetail | null>(null);
  const [isDeactivating, setIsDeactivating] = useState(false);
  const [activatingId, setActivatingId] = useState<number | null>(null);

  async function confirmDeactivate() {
    if (!pendingDeactivate) return;
    setIsDeactivating(true);
    try {
      await onDeactivate(pendingDeactivate);
      setPendingDeactivate(null);
    } finally {
      setIsDeactivating(false);
    }
  }

  async function handleActivate(facility: HospitalDetail) {
    setActivatingId(facility.id);
    try {
      await onActivate(facility);
    } finally {
      setActivatingId(null);
    }
  }

  return (
    <>
      <div className="overflow-hidden rounded-lg border bg-card">
        <Table>
          <TableHeader className="bg-muted/15">
            <TableRow>
              <TableHead className="h-11 p-3 font-medium">Facility</TableHead>
              <TableHead className="h-11 p-3 font-medium">Admin</TableHead>
              <TableHead className="h-11 p-3 font-medium">Active staff</TableHead>
              <TableHead className="h-11 p-3 font-medium">Status</TableHead>
              <TableHead className="h-11 p-3 text-right font-medium">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRows
              facilities={facilities}
              staff={staff}
              isLoading={isLoading}
              activatingId={activatingId}
              onEdit={onEdit}
              onDeactivateClick={setPendingDeactivate}
              onActivate={handleActivate}
            />
          </TableBody>
        </Table>
      </div>

      <AlertDialog open={!!pendingDeactivate} onOpenChange={(open) => !open && setPendingDeactivate(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Deactivate {pendingDeactivate?.name}?</AlertDialogTitle>
            <AlertDialogDescription>
              Staff at this facility will no longer be able to sign in through it. You can reactivate this facility any
              time from this list.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction disabled={isDeactivating} onClick={confirmDeactivate}>
              {isDeactivating ? "Deactivating…" : "Deactivate"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
