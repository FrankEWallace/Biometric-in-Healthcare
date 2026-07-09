"use client";

import { useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Field, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select";
import { ApiError } from "@/lib/api";
import type { Hospital } from "@/lib/dashboard/api";
import { createStaff, type StaffFormValues, type StaffRole, type StaffUser, updateStaff } from "@/lib/staff/api";

const ROLE_LABEL: Record<StaffRole, string> = {
  admin: "Admin",
  nurse: "Nurse",
  doctor: "Doctor",
  super_admin: "Super admin",
};

function submitLabel(isSubmitting: boolean, isEdit: boolean) {
  if (isSubmitting) return "Saving…";
  return isEdit ? "Save changes" : "Create account";
}

export function StaffFormDialog({
  open,
  onOpenChange,
  staff,
  allowedRoles,
  hospitals,
  isSuperAdmin,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  staff: StaffUser | null;
  allowedRoles: StaffRole[];
  hospitals: Hospital[];
  isSuperAdmin: boolean;
  onSaved: (staff: StaffUser) => void;
}) {
  const isEdit = !!staff;
  const [name, setName] = useState("");
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] = useState<StaffRole>(allowedRoles[0]);
  const [hospitalId, setHospitalId] = useState<number | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!open) return;
    setError(null);
    setName(staff?.name ?? "");
    setUsername(staff?.username ?? "");
    setEmail(staff?.email ?? "");
    setPassword("");
    setRole(staff?.role ?? allowedRoles[0]);
    setHospitalId(staff?.hospital_id ?? hospitals[0]?.id);
  }, [open, staff, allowedRoles, hospitals]);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      const values: StaffFormValues = {
        name,
        username,
        email,
        role,
        ...(isSuperAdmin ? { hospital_id: hospitalId } : {}),
        ...(password ? { password } : {}),
      };
      const saved = isEdit ? await updateStaff(staff.id, values) : await createStaff(values);
      onSaved(saved);
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Something went wrong. Please try again.");
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <form onSubmit={onSubmit}>
          <DialogHeader>
            <DialogTitle>{isEdit ? "Edit staff account" : "Add staff account"}</DialogTitle>
            <DialogDescription>
              {isEdit ? `Update ${staff.name}'s account details.` : "Create a new staff account for this hospital."}
            </DialogDescription>
          </DialogHeader>

          <FieldGroup className="gap-4 py-4">
            <Field className="gap-1.5">
              <FieldLabel htmlFor="staff-name">Full name</FieldLabel>
              <Input id="staff-name" value={name} onChange={(e) => setName(e.target.value)} required />
            </Field>
            <Field className="gap-1.5">
              <FieldLabel htmlFor="staff-username">Username</FieldLabel>
              <Input id="staff-username" value={username} onChange={(e) => setUsername(e.target.value)} required />
            </Field>
            <Field className="gap-1.5">
              <FieldLabel htmlFor="staff-email">Email</FieldLabel>
              <Input id="staff-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </Field>
            <Field className="gap-1.5">
              <FieldLabel htmlFor="staff-password">{isEdit ? "New password (optional)" : "Password"}</FieldLabel>
              <Input
                id="staff-password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required={!isEdit}
                minLength={8}
              />
            </Field>
            <Field className="gap-1.5">
              <FieldLabel htmlFor="staff-role">Role</FieldLabel>
              <NativeSelect id="staff-role" value={role} onChange={(e) => setRole(e.target.value as StaffRole)}>
                {allowedRoles.map((r) => (
                  <NativeSelectOption key={r} value={r}>
                    {ROLE_LABEL[r]}
                  </NativeSelectOption>
                ))}
              </NativeSelect>
            </Field>
            {isSuperAdmin && (
              <Field className="gap-1.5">
                <FieldLabel htmlFor="staff-hospital">Hospital</FieldLabel>
                <NativeSelect
                  id="staff-hospital"
                  value={hospitalId ?? ""}
                  onChange={(e) => setHospitalId(Number(e.target.value))}
                >
                  {hospitals.map((h) => (
                    <NativeSelectOption key={h.id} value={h.id}>
                      {h.name}
                    </NativeSelectOption>
                  ))}
                </NativeSelect>
              </Field>
            )}
            {error && <FieldError errors={[{ message: error }]} />}
          </FieldGroup>

          <DialogFooter>
            <Button type="submit" disabled={isSubmitting}>
              {submitLabel(isSubmitting, isEdit)}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
