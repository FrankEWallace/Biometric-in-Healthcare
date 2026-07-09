"use client";

import { format, parseISO } from "date-fns";
import { Search } from "lucide-react";

import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import type { PatientListItem } from "@/lib/patients/api";
import { cn } from "@/lib/utils";

export function PatientList({
  patients,
  isLoading,
  search,
  onSearchChange,
  selectedId,
  onSelect,
}: {
  patients: PatientListItem[];
  isLoading: boolean;
  search: string;
  onSearchChange: (value: string) => void;
  selectedId: number | null;
  onSelect: (patient: PatientListItem) => void;
}) {
  return (
    <div className="flex h-full flex-col gap-3">
      <div className="relative">
        <Search className="absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          placeholder="Search by name, ID, or NIDA…"
          className="pl-8"
          value={search}
          onChange={(e) => onSearchChange(e.target.value)}
        />
      </div>

      <ScrollArea className="h-[calc(100vh-16rem)]">
        <div className="flex flex-col gap-1 pr-2">
          {isLoading &&
            Array.from({ length: 6 }).map((_, i) => (
              // biome-ignore lint/suspicious/noArrayIndexKey: static loading skeleton rows
              <Skeleton key={i} className="h-14 w-full rounded-lg" />
            ))}
          {!isLoading && patients.length === 0 && (
            <p className="p-4 text-center text-muted-foreground text-sm">
              {search ? "No patients match your search." : "No patients found."}
            </p>
          )}
          {!isLoading &&
            patients.length > 0 &&
            patients.map((patient) => (
              <button
                key={patient.id}
                type="button"
                onClick={() => onSelect(patient)}
                className={cn(
                  "flex flex-col gap-0.5 rounded-lg border p-3 text-left transition-colors hover:bg-muted/50",
                  selectedId === patient.id && "border-primary/40 bg-primary/5",
                )}
              >
                <span className="truncate font-medium text-sm">{patient.full_name}</span>
                <span className="truncate text-muted-foreground text-xs">
                  #{patient.hospital_patient_id ?? "—"} · {patient.gender} ·{" "}
                  {format(parseISO(patient.date_of_birth), "do MMM yyyy")}
                </span>
              </button>
            ))}
        </div>
      </ScrollArea>
    </div>
  );
}
