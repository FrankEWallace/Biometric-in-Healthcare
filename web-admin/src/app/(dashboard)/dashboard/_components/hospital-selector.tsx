"use client";

import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { Hospital } from "@/lib/dashboard/api";

export function HospitalSelector({
  hospitals,
  value,
  onChange,
}: {
  hospitals: Hospital[];
  value: number | "all";
  onChange: (value: number | "all") => void;
}) {
  return (
    <Select value={String(value)} onValueChange={(v) => onChange(v === "all" ? "all" : Number(v))}>
      <SelectTrigger size="sm" className="w-56">
        <SelectValue placeholder="All hospitals" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="all">All hospitals (verification only)</SelectItem>
        {hospitals.map((hospital) => (
          <SelectItem key={hospital.id} value={String(hospital.id)}>
            {hospital.name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
