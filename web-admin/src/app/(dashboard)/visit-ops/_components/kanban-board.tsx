"use client";

import { Skeleton } from "@/components/ui/skeleton";
import { STAGE_LABEL, STAGE_ORDER } from "@/lib/patients/api";
import { currentStage, type QueueVisit } from "@/lib/visit-ops/api";

import { VisitCard } from "./visit-card";

function ColumnContent({ visits, isLoading }: { visits: QueueVisit[]; isLoading: boolean }) {
  if (isLoading) {
    return (
      <>
        <Skeleton className="h-16 w-full" />
        <Skeleton className="h-16 w-full" />
      </>
    );
  }

  if (visits.length === 0) {
    return <p className="py-4 text-center text-muted-foreground text-xs">No visits</p>;
  }

  return (
    <>
      {visits.map((visit) => (
        <VisitCard key={visit.id} visit={visit} />
      ))}
    </>
  );
}

export function KanbanBoard({ visits, isLoading }: { visits: QueueVisit[]; isLoading: boolean }) {
  return (
    <div className="grid @2xl/main:grid-cols-3 @6xl/main:grid-cols-6 grid-cols-1 gap-4">
      {STAGE_ORDER.map((stage) => {
        const stageVisits = visits.filter((v) => currentStage(v) === stage);
        return (
          <div key={stage} className="flex flex-col gap-2 rounded-lg border bg-muted/15 p-3">
            <div className="flex items-center justify-between">
              <span className="font-medium text-sm">{STAGE_LABEL[stage]}</span>
              <span className="text-muted-foreground text-xs">{stageVisits.length}</span>
            </div>
            <div className="flex flex-col gap-2">
              <ColumnContent visits={stageVisits} isLoading={isLoading} />
            </div>
          </div>
        );
      })}
    </div>
  );
}
