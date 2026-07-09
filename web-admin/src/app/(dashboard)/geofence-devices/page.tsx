"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useAuth } from "@/lib/auth/auth-context";
import { getFacilities, type HospitalDetail } from "@/lib/facilities/api";
import { type Device, getDevices } from "@/lib/geofence-devices/api";

import { DevicesTable } from "./_components/devices-table";
import { GeofenceForm } from "./_components/geofence-form";

export default function Page() {
  const { user } = useAuth();
  const isSuperAdmin = user?.role === "super_admin";

  const [hospitals, setHospitals] = useState<HospitalDetail[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [devices, setDevices] = useState<Device[]>([]);
  const [isLoadingDevices, setIsLoadingDevices] = useState(true);

  useEffect(() => {
    if (!user) return;
    void getFacilities().then((all) => {
      setHospitals(all);
      setSelectedId((current) => current ?? (isSuperAdmin ? (all[0]?.id ?? null) : user.hospital_id));
    });
  }, [user, isSuperAdmin]);

  const selected = useMemo(() => hospitals.find((h) => h.id === selectedId) ?? null, [hospitals, selectedId]);

  const reloadDevices = useCallback(() => {
    if (!selectedId) return;
    setIsLoadingDevices(true);
    // Admins are server-scoped to their own hospital; the filter only matters for superadmin.
    void getDevices(isSuperAdmin ? selectedId : undefined)
      .then(setDevices)
      .finally(() => setIsLoadingDevices(false));
  }, [selectedId, isSuperAdmin]);

  useEffect(() => {
    reloadDevices();
  }, [reloadDevices]);

  function onSaved(updated: HospitalDetail) {
    setHospitals((prev) => prev.map((h) => (h.id === updated.id ? updated : h)));
  }

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      {isSuperAdmin && (
        <div className="flex justify-end">
          <Select value={selectedId ? String(selectedId) : ""} onValueChange={(v) => setSelectedId(Number(v))}>
            <SelectTrigger size="sm" className="w-56">
              <SelectValue placeholder="Select hospital" />
            </SelectTrigger>
            <SelectContent>
              {hospitals.map((hospital) => (
                <SelectItem key={hospital.id} value={String(hospital.id)}>
                  {hospital.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Geofence</CardTitle>
          <CardDescription>
            {selected
              ? `Where verification is allowed for ${selected.name}. Requests outside these bounds are rejected by the server.`
              : "Loading hospital…"}
          </CardDescription>
        </CardHeader>
        <CardContent>{selected && <GeofenceForm hospital={selected} onSaved={onSaved} />}</CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Devices</CardTitle>
          <CardDescription>
            Devices that have used the API, derived from audit activity — grouped by IP address and client, newest
            first.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <DevicesTable devices={devices} isLoading={isLoadingDevices} showHospital={isSuperAdmin} />
        </CardContent>
      </Card>
    </div>
  );
}
