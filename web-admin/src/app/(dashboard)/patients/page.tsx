"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { format, parseISO } from "date-fns";

import { LoadError } from "@/components/load-error";
import { Button } from "@/components/ui/button";
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
  const [page, setPage] = useState(1);
  const [lastPage, setLastPage] = useState(1);
  const [patients, setPatients] = useState<PatientListItem[]>([]);
  const [isLoadingList, setIsLoadingList] = useState(true);
  const [listError, setListError] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const [selected, setSelected] = useState<PatientListItem | null>(null);
  const [visit, setVisit] = useState<VisitDetail | null>(null);
  const [visitState, setVisitState] = useState<"idle" | "loading" | "none" | "loaded" | "error">("idle");
  // Incremented on every selection so a slow earlier response can't render
  // patient A's timeline under patient B (stale-data race guard).
  const selectionRef = useRef(0);

  // Reset to page 1 whenever the search term changes.
  // biome-ignore lint/correctness/useExhaustiveDependencies: search is the intentional trigger; the body only resets the page.
  useEffect(() => {
    setPage(1);
  }, [search]);

  // biome-ignore lint/correctness/useExhaustiveDependencies: reloadToken is an intentional retrigger — bumped by the LoadError retry to re-run the fetch.
  useEffect(() => {
    let cancelled = false;
    setIsLoadingList(true);
    setListError(false);
    const handle = setTimeout(() => {
      void getPatients(search, page)
        .then((res) => {
          if (cancelled) return;
          setPatients(res.data);
          setLastPage(res.lastPage);
        })
        .catch(() => {
          if (!cancelled) setListError(true);
        })
        .finally(() => {
          if (!cancelled) setIsLoadingList(false);
        });
    }, 250);
    return () => {
      cancelled = true;
      clearTimeout(handle);
    };
  }, [search, page, reloadToken]);

  const selectPatient = useCallback((patient: PatientListItem) => {
    const selectionId = ++selectionRef.current;
    setSelected(patient);
    setVisit(null);
    setVisitState("loading");
    void findVisitForPatient(patient.id)
      .then((summary) => {
        if (selectionId !== selectionRef.current) return; // a newer selection won
        if (!summary) {
          setVisitState("none");
          return;
        }
        void getVisitDetail(summary.id)
          .then((detail) => {
            if (selectionId !== selectionRef.current) return;
            setVisit(detail);
            setVisitState("loaded");
          })
          .catch(() => {
            if (selectionId === selectionRef.current) setVisitState("error");
          });
      })
      .catch(() => {
        if (selectionId === selectionRef.current) setVisitState("error");
      });
  }, []);

  return (
    <div className="@container/main grid grid-cols-1 gap-4 md:grid-cols-[320px_1fr] md:gap-6">
      <Card className="md:h-[calc(100vh-8rem)]">
        <CardHeader>
          <CardTitle>Patients</CardTitle>
          <CardDescription>Search and select a patient to view their visit.</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          {listError ? (
            <LoadError message="Couldn't load patients." onRetry={() => setReloadToken((t) => t + 1)} />
          ) : (
            <>
              <PatientList
                patients={patients}
                isLoading={isLoadingList}
                search={search}
                onSearchChange={setSearch}
                selectedId={selected?.id ?? null}
                onSelect={selectPatient}
              />
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground text-sm">
                  Page {page} of {lastPage}
                </span>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
                    Previous
                  </Button>
                  <Button variant="outline" size="sm" disabled={page >= lastPage} onClick={() => setPage((p) => p + 1)}>
                    Next
                  </Button>
                </div>
              </div>
            </>
          )}
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
          {visitState === "error" && selected && (
            <LoadError message="Couldn't load this patient's visit." onRetry={() => selectPatient(selected)} />
          )}
          {visitState === "idle" && (
            <p className="text-muted-foreground text-sm">Select a patient to see their visit timeline.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
