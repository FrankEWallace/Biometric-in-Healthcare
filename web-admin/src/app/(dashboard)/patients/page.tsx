"use client";

import { useCallback, useEffect, useState } from "react";

import { format, parseISO } from "date-fns";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import {
  findVisitForPatient,
  getPatients,
  getVisitDetail,
  type PatientListItem,
  type VisitDetail,
} from "@/lib/patients/api";

import { PatientList } from "./_components/patient-list";
import { VisitTimeline } from "./_components/visit-timeline";

export default function Page() {
  const [search, setSearch] = useState("");
  const [patients, setPatients] = useState<PatientListItem[]>([]);
  const [isLoadingList, setIsLoadingList] = useState(true);
  const [selected, setSelected] = useState<PatientListItem | null>(null);
  const [visit, setVisit] = useState<VisitDetail | null>(null);
  const [visitState, setVisitState] = useState<"idle" | "loading" | "none" | "loaded">("idle");

  useEffect(() => {
    setIsLoadingList(true);
    const handle = setTimeout(() => {
      void getPatients(search)
        .then(setPatients)
        .finally(() => setIsLoadingList(false));
    }, 250);
    return () => clearTimeout(handle);
  }, [search]);

  const selectPatient = useCallback((patient: PatientListItem) => {
    setSelected(patient);
    setVisit(null);
    setVisitState("loading");
    void findVisitForPatient(patient.id).then((summary) => {
      if (!summary) {
        setVisitState("none");
        return;
      }
      void getVisitDetail(summary.id).then((detail) => {
        setVisit(detail);
        setVisitState("loaded");
      });
    });
  }, []);

  return (
    <div className="@container/main grid grid-cols-1 gap-4 md:grid-cols-[320px_1fr] md:gap-6">
      <Card className="md:h-[calc(100vh-8rem)]">
        <CardHeader>
          <CardTitle>Patients</CardTitle>
          <CardDescription>Search and select a patient to view their visit.</CardDescription>
        </CardHeader>
        <CardContent>
          <PatientList
            patients={patients}
            isLoading={isLoadingList}
            search={search}
            onSearchChange={setSearch}
            selectedId={selected?.id ?? null}
            onSelect={selectPatient}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{selected ? selected.full_name : "Visit detail"}</CardTitle>
          <CardDescription>
            {selected
              ? `#${selected.hospital_patient_id ?? "—"} · ${selected.gender} · ${format(parseISO(selected.date_of_birth), "do MMM yyyy")}`
              : "Select a patient from the list."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {visitState === "loading" && (
            <div className="flex flex-col gap-4">
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-48 w-full" />
            </div>
          )}
          {visitState === "none" && (
            <p className="text-muted-foreground text-sm">
              No visit found for this patient today. Only today&apos;s open or closed visits are shown here.
            </p>
          )}
          {visitState === "loaded" && visit && <VisitTimeline visit={visit} />}
          {visitState === "idle" && (
            <p className="text-muted-foreground text-sm">Select a patient to see their visit timeline.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
