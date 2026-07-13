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
import {
  createFacility,
  detectCurrentIp,
  type HospitalDetail,
  type HospitalFormValues,
  updateFacility,
} from "@/lib/facilities/api";

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
  const [allowedIpRanges, setAllowedIpRanges] = useState("");
  const [gpsLatitude, setGpsLatitude] = useState("");
  const [gpsLongitude, setGpsLongitude] = useState("");
  const [gpsRadiusMeters, setGpsRadiusMeters] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isDetectingIp, setIsDetectingIp] = useState(false);
  const [isDetectingLocation, setIsDetectingLocation] = useState(false);

  useEffect(() => {
    if (!open) return;
    setError(null);
    setName(facility?.name ?? "");
    setCode(facility?.code ?? "");
    setCity(facility?.city ?? "");
    setWifiSsid(facility?.wifi_ssid ?? "");
    setAllowedIpRanges(facility?.allowed_ip_ranges ?? "");
    setGpsLatitude(facility?.gps_latitude ?? "");
    setGpsLongitude(facility?.gps_longitude ?? "");
    setGpsRadiusMeters(facility?.gps_radius_meters != null ? String(facility.gps_radius_meters) : "");
  }, [open, facility]);

  async function onDetectIp() {
    setError(null);
    setIsDetectingIp(true);
    try {
      const ip = await detectCurrentIp();
      setAllowedIpRanges((current) => {
        const existing = current.split(",").map((v) => v.trim()).filter(Boolean);
        return existing.includes(ip) ? current : [...existing, ip].join(", ");
      });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not detect current IP.");
    } finally {
      setIsDetectingIp(false);
    }
  }

  async function onDetectLocation() {
    setError(null);
    if (!("geolocation" in navigator)) {
      setError("This browser does not support location detection.");
      return;
    }
    setIsDetectingLocation(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setGpsLatitude(position.coords.latitude.toFixed(7));
        setGpsLongitude(position.coords.longitude.toFixed(7));
        setIsDetectingLocation(false);
      },
      (geoError) => {
        setError(
          geoError.code === geoError.PERMISSION_DENIED
            ? "Location permission denied. Allow location access and try again."
            : "Could not detect current location.",
        );
        setIsDetectingLocation(false);
      },
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      const values: HospitalFormValues = {
        name,
        code,
        city,
        wifi_ssid: wifiSsid || null,
        allowed_ip_ranges: allowedIpRanges || null,
        gps_latitude: gpsLatitude ? Number(gpsLatitude) : null,
        gps_longitude: gpsLongitude ? Number(gpsLongitude) : null,
        gps_radius_meters: gpsRadiusMeters ? Number(gpsRadiusMeters) : null,
      };
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
            <Field className="gap-1.5">
              <FieldLabel htmlFor="facility-ip-ranges">Allowed IP ranges (network gate)</FieldLabel>
              <div className="flex gap-2">
                <Input
                  id="facility-ip-ranges"
                  placeholder="e.g. 41.222.10.0/24, 196.192.55.10"
                  value={allowedIpRanges}
                  onChange={(e) => setAllowedIpRanges(e.target.value)}
                  className="flex-1"
                />
                <Button
                  type="button"
                  variant="outline"
                  onClick={onDetectIp}
                  disabled={isDetectingIp}
                >
                  {isDetectingIp ? "Detecting…" : "Detect current IP"}
                </Button>
              </div>
            </Field>
            <Field className="gap-1.5">
              <FieldLabel htmlFor="facility-gps-lat">GPS geofence</FieldLabel>
              <div className="grid grid-cols-2 gap-2">
                <Input
                  id="facility-gps-lat"
                  placeholder="Latitude"
                  inputMode="decimal"
                  value={gpsLatitude}
                  onChange={(e) => setGpsLatitude(e.target.value)}
                />
                <Input
                  placeholder="Longitude"
                  inputMode="decimal"
                  value={gpsLongitude}
                  onChange={(e) => setGpsLongitude(e.target.value)}
                />
              </div>
              <div className="flex gap-2">
                <Input
                  placeholder="Radius (metres)"
                  inputMode="numeric"
                  value={gpsRadiusMeters}
                  onChange={(e) => setGpsRadiusMeters(e.target.value)}
                  className="flex-1"
                />
                <Button
                  type="button"
                  variant="outline"
                  onClick={onDetectLocation}
                  disabled={isDetectingLocation}
                >
                  {isDetectingLocation ? "Detecting…" : "Use current location"}
                </Button>
              </div>
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
