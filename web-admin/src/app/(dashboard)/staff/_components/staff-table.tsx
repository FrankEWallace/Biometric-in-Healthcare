"use client";

import { useState } from "react";

import { format, parseISO } from "date-fns";

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
import type { Hospital } from "@/lib/dashboard/api";
import type { StaffRole, StaffUser } from "@/lib/staff/api";

const ROLE_LABEL: Record<StaffRole, string> = {
  admin: "Admin",
  nurse: "Nurse",
  doctor: "Doctor",
  super_admin: "Super admin",
};

function TableRows({
  staff,
  hospitals,
  isSuperAdmin,
  isLoading,
  activatingId,
  onEdit,
  onDeactivateClick,
  onActivate,
}: {
  staff: StaffUser[];
  hospitals: Hospital[];
  isSuperAdmin: boolean;
  isLoading: boolean;
  activatingId: number | null;
  onEdit: (staff: StaffUser) => void;
  onDeactivateClick: (staff: StaffUser) => void;
  onActivate: (staff: StaffUser) => void;
}) {
  const colSpan = isSuperAdmin ? 6 : 5;

  if (isLoading) {
    return (
      <>
        {Array.from({ length: 5 }).map((_, i) => (
          // biome-ignore lint/suspicious/noArrayIndexKey: static loading skeleton rows
          <TableRow key={i}>
            <TableCell colSpan={colSpan} className="p-3">
              <Skeleton className="h-6 w-full" />
            </TableCell>
          </TableRow>
        ))}
      </>
    );
  }

  if (staff.length === 0) {
    return (
      <TableRow>
        <TableCell colSpan={colSpan} className="h-24 text-center text-muted-foreground">
          No staff accounts found.
        </TableCell>
      </TableRow>
    );
  }

  const hospitalName = (id: number | null) => hospitals.find((h) => h.id === id)?.name ?? "—";

  return (
    <>
      {staff.map((member) => (
        <TableRow key={member.id}>
          <TableCell className="p-3 align-middle">
            <div className="grid gap-0.5">
              <span className="font-medium text-sm">{member.name}</span>
              <span className="text-muted-foreground text-xs">{member.email}</span>
            </div>
          </TableCell>
          <TableCell className="p-3 align-middle">
            <Badge variant="outline" className="px-1.5 text-muted-foreground">
              {ROLE_LABEL[member.role]}
            </Badge>
          </TableCell>
          {isSuperAdmin && (
            <TableCell className="p-3 align-middle text-sm">{hospitalName(member.hospital_id)}</TableCell>
          )}
          <TableCell className="p-3 align-middle">
            <Badge variant={member.is_active ? "default" : "outline"} className="px-1.5">
              {member.is_active ? "Active" : "Deactivated"}
            </Badge>
          </TableCell>
          <TableCell className="p-3 align-middle text-muted-foreground text-sm">
            {format(parseISO(member.updated_at), "do MMM yyyy")}
          </TableCell>
          <TableCell className="p-3 text-right align-middle">
            <div className="flex justify-end gap-2">
              <Button variant="outline" size="sm" onClick={() => onEdit(member)}>
                Edit
              </Button>
              {member.is_active ? (
                <Button variant="outline" size="sm" onClick={() => onDeactivateClick(member)}>
                  Deactivate
                </Button>
              ) : (
                <Button
                  variant="outline"
                  size="sm"
                  disabled={activatingId === member.id}
                  onClick={() => onActivate(member)}
                >
                  {activatingId === member.id ? "Activating…" : "Activate"}
                </Button>
              )}
            </div>
          </TableCell>
        </TableRow>
      ))}
    </>
  );
}

export function StaffTable({
  staff,
  hospitals,
  isSuperAdmin,
  isLoading,
  onEdit,
  onDeactivate,
  onActivate,
}: {
  staff: StaffUser[];
  hospitals: Hospital[];
  isSuperAdmin: boolean;
  isLoading: boolean;
  onEdit: (staff: StaffUser) => void;
  onDeactivate: (staff: StaffUser) => Promise<void>;
  onActivate: (staff: StaffUser) => Promise<void>;
}) {
  const [pendingDeactivate, setPendingDeactivate] = useState<StaffUser | null>(null);
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

  async function handleActivate(member: StaffUser) {
    setActivatingId(member.id);
    try {
      await onActivate(member);
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
              <TableHead className="h-11 p-3 font-medium">Name</TableHead>
              <TableHead className="h-11 p-3 font-medium">Role</TableHead>
              {isSuperAdmin && <TableHead className="h-11 p-3 font-medium">Hospital</TableHead>}
              <TableHead className="h-11 p-3 font-medium">Status</TableHead>
              <TableHead className="h-11 p-3 font-medium">Last updated</TableHead>
              <TableHead className="h-11 p-3 text-right font-medium">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRows
              staff={staff}
              hospitals={hospitals}
              isSuperAdmin={isSuperAdmin}
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
              They will no longer be able to sign in. You can reactivate this account any time from this list.
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
