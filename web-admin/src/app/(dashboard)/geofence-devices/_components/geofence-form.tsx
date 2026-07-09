"use client";

import { useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { ApiError } from "@/lib/api";
import { type HospitalDetail, updateFacility } from "@/lib/facilities/api";

export function GeofenceForm({
  hospital,
  onSaved,
}: {
  hospital: HospitalDetail;
  onSaved: (hospital: HospitalDetail) => void;
}) {
  const [wifiSsid, setWifiSsid] = useState("");
  const [latitude, setLatitude] = useState("");
  const [longitude, setLongitude] = useState("");
  const [radius, setRadius] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isLocating, setIsLocating] = useState(false);

  useEffect(() => {
    setError(null);
    setSaved(false);
    setWifiSsid(hospital.wifi_ssid ?? "");
    setLatitude(hospital.gps_latitude ?? "");
    setLongitude(hospital.gps_longitude ?? "");
    setRadius(hospital.gps_radius_meters != null ? String(hospital.gps_radius_meters) : "");
  }, [hospital]);

  function useCurrentLocation() {
    setIsLocating(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLatitude(position.coords.latitude.toFixed(7));
        setLongitude(position.coords.longitude.toFixed(7));
        setIsLocating(false);
      },
      () => {
        setError("Could not read this device's location. Enter coordinates manually.");
        setIsLocating(false);
      },
    );
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSaved(false);
    setIsSubmitting(true);
    try {
      const updated = await updateFacility(hospital.id, {
        wifi_ssid: wifiSsid || null,
        gps_latitude: latitude === "" ? null : Number(latitude),
        gps_longitude: longitude === "" ? null : Number(longitude),
        gps_radius_meters: radius === "" ? null : Number(radius),
      });
      onSaved(updated);
      setSaved(true);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Something went wrong. Please try again.");
    } finally {
      setIsSubmitting(false);
    }
  }

  const gpsConfigured = latitude !== "" && longitude !== "";
  const wifiConfigured = wifiSsid !== "";

  return (
    <form onSubmit={onSubmit}>
      <FieldGroup className="gap-4">
        <Field className="gap-1.5">
          <FieldLabel htmlFor="geofence-wifi">WiFi SSID</FieldLabel>
          <Input
            id="geofence-wifi"
            value={wifiSsid}
            onChange={(e) => setWifiSsid(e.target.value)}
            placeholder="e.g. HOSPITAL-STAFF"
          />
          <FieldDescription>
            Verification requests must come from a device connected to this network. Leave empty to skip the WiFi check.
          </FieldDescription>
        </Field>

        <div className="grid grid-cols-2 gap-4">
          <Field className="gap-1.5">
            <FieldLabel htmlFor="geofence-lat">GPS latitude</FieldLabel>
            <Input
              id="geofence-lat"
              type="number"
              step="any"
              min={-90}
              max={90}
              value={latitude}
              onChange={(e) => setLatitude(e.target.value)}
            />
          </Field>
          <Field className="gap-1.5">
            <FieldLabel htmlFor="geofence-lng">GPS longitude</FieldLabel>
            <Input
              id="geofence-lng"
              type="number"
              step="any"
              min={-180}
              max={180}
              value={longitude}
              onChange={(e) => setLongitude(e.target.value)}
            />
          </Field>
        </div>

        <Field className="gap-1.5">
          <FieldLabel htmlFor="geofence-radius">Allowed radius (meters)</FieldLabel>
          <Input
            id="geofence-radius"
            type="number"
            min={50}
            max={5000}
            value={radius}
            onChange={(e) => setRadius(e.target.value)}
            placeholder="e.g. 300"
          />
          <FieldDescription>
            Devices must be within this distance of the coordinates above (50–5000 m). Both GPS and WiFi checks apply
            when configured; if neither is set, access is governed by the server&apos;s fail-open policy.
          </FieldDescription>
        </Field>

        {error && <FieldError errors={[{ message: error }]} />}
        {saved && <p className="text-sm text-emerald-600">Geofence saved.</p>}

        <div className="flex items-center gap-2">
          <Button type="submit" disabled={isSubmitting}>
            {isSubmitting ? "Saving…" : "Save geofence"}
          </Button>
          <Button type="button" variant="outline" onClick={useCurrentLocation} disabled={isLocating}>
            {isLocating ? "Locating…" : "Use my current location"}
          </Button>
          <span className="text-muted-foreground text-xs">
            {gpsConfigured ? "GPS check on" : "GPS check off"} · {wifiConfigured ? "WiFi check on" : "WiFi check off"}
          </span>
        </div>
      </FieldGroup>
    </form>
  );
}
