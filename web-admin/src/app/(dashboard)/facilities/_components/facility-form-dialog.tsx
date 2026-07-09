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
import { ApiError } from "@/lib/api";
import { createFacility, type HospitalDetail, type HospitalFormValues, updateFacility } from "@/lib/facilities/api";

function submitLabel(isSubmitting: boolean, isEdit: boolean) {
  if (isSubmitting) return "Saving…";
  return isEdit ? "Save changes" : "Create facility";
}

export function FacilityFormDialog({
  open,
  onOpenChange,
  facility,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  facility: HospitalDetail | null;
  onSaved: (facility: HospitalDetail) => void;
}) {
  const isEdit = !!facility;
  const [name, setName] = useState("");
  const [code, setCode] = useState("");
  const [city, setCity] = useState("");
  const [wifiSsid, setWifiSsid] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!open) return;
    setError(null);
    setName(facility?.name ?? "");
    setCode(facility?.code ?? "");
    setCity(facility?.city ?? "");
    setWifiSsid(facility?.wifi_ssid ?? "");
  }, [open, facility]);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      const values: HospitalFormValues = { name, code, city, wifi_ssid: wifiSsid || null };
      const saved = isEdit ? await updateFacility(facility.id, values) : await createFacility(values);
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
            <DialogTitle>{isEdit ? "Edit facility" : "Add facility"}</DialogTitle>
            <DialogDescription>
              {isEdit
                ? `Update ${facility.name}'s details.`
                : "Create a new hospital. Assign its admin afterwards from the Staff screen."}
            </DialogDescription>
          </DialogHeader>

          <FieldGroup className="gap-4 py-4">
            <Field className="gap-1.5">
              <FieldLabel htmlFor="facility-name">Name</FieldLabel>
              <Input id="facility-name" value={name} onChange={(e) => setName(e.target.value)} required />
            </Field>
            <Field className="gap-1.5">
              <FieldLabel htmlFor="facility-code">Code</FieldLabel>
              <Input id="facility-code" value={code} onChange={(e) => setCode(e.target.value)} required />
            </Field>
            <Field className="gap-1.5">
              <FieldLabel htmlFor="facility-city">City</FieldLabel>
              <Input id="facility-city" value={city} onChange={(e) => setCity(e.target.value)} required />
            </Field>
            <Field className="gap-1.5">
              <FieldLabel htmlFor="facility-wifi">WiFi SSID (geofence allowlist)</FieldLabel>
              <Input id="facility-wifi" value={wifiSsid} onChange={(e) => setWifiSsid(e.target.value)} />
            </Field>
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
