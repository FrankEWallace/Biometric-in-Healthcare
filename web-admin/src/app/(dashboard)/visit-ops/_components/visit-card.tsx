"use client";

import { formatDistanceToNow, parseISO } from "date-fns";

import { Badge } from "@/components/ui/badge";
import { enteredStageAt, type QueueVisit } from "@/lib/visit-ops/api";

export function VisitCard({ visit }: { visit: QueueVisit }) {
  const enteredAt = enteredStageAt(visit);

  return (
    <div className="flex flex-col gap-1.5 rounded-lg border bg-card p-3">
      <div className="flex items-start justify-between gap-2">
        <span className="truncate font-medium text-sm">{visit.patient?.full_name ?? "Unknown patient"}</span>
        <Badge variant="outline" className="shrink-0 px-1.5 text-muted-foreground">
          #{visit.patient?.hospital_patient_id ?? visit.id}
        </Badge>
      </div>
      <span className="text-muted-foreground text-xs">In stage for {formatDistanceToNow(parseISO(enteredAt))}</span>
    </div>
  );
}
