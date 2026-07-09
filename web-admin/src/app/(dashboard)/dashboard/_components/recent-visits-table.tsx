"use client";

import { format, parseISO } from "date-fns";
import { UserRound } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { VisitListItem } from "@/lib/dashboard/api";

const visitTypeLabel: Record<VisitListItem["visit_type"], string> = {
  pending: "Pending",
  opd: "OPD",
  ipd: "IPD",
};

function TableRows({ visits, isLoading }: { visits: VisitListItem[]; isLoading: boolean }) {
  if (isLoading) {
    return (
      <>
        {Array.from({ length: 5 }).map((_, i) => (
          // biome-ignore lint/suspicious/noArrayIndexKey: static loading skeleton rows
          <TableRow key={i}>
            <TableCell colSpan={5} className="p-3">
              <Skeleton className="h-6 w-full" />
            </TableCell>
          </TableRow>
        ))}
      </>
    );
  }

  if (visits.length === 0) {
    return (
      <TableRow>
        <TableCell colSpan={5} className="h-24 text-center text-muted-foreground">
          No visits opened today.
        </TableCell>
      </TableRow>
    );
  }

  return (
    <>
      {visits.map((visit) => (
        <TableRow key={visit.id}>
          <TableCell className="p-3 align-middle">
            <div className="flex items-center gap-2">
              <span className="flex size-8 items-center justify-center rounded-md border bg-muted">
                <UserRound className="size-4 text-muted-foreground" />
              </span>
              <div className="grid min-w-0 gap-0.5">
                <span className="truncate font-medium text-sm leading-none">
                  {visit.patient?.full_name ?? "Unknown"}
                </span>
                <span className="truncate text-muted-foreground text-xs leading-none">
                  #{visit.patient?.hospital_patient_id ?? "—"}
                </span>
              </div>
            </div>
          </TableCell>
          <TableCell className="p-3 align-middle">
            <Badge variant="outline" className="px-1.5 text-muted-foreground">
              {visitTypeLabel[visit.visit_type]}
            </Badge>
          </TableCell>
          <TableCell className="p-3 align-middle">
            <Badge variant={visit.status === "open" ? "default" : "outline"} className="px-1.5">
              {visit.status === "open" ? "Open" : "Closed"}
            </Badge>
          </TableCell>
          <TableCell className="p-3 align-middle text-sm">{visit.openedBy?.name ?? "—"}</TableCell>
          <TableCell className="p-3 align-middle">
            <div className="grid gap-0.5">
              <span className="text-sm">{format(parseISO(visit.opened_at), "do MMM yyyy")}</span>
              <span className="text-muted-foreground text-xs">{format(parseISO(visit.opened_at), "h:mm a")}</span>
            </div>
          </TableCell>
        </TableRow>
      ))}
    </>
  );
}

export function RecentVisitsTable({ visits, isLoading }: { visits: VisitListItem[]; isLoading: boolean }) {
  return (
    <div className="overflow-hidden rounded-lg border bg-card">
      <Table>
        <TableHeader className="bg-muted/15">
          <TableRow>
            <TableHead className="h-11 p-3 font-medium">Patient</TableHead>
            <TableHead className="h-11 p-3 font-medium">Type</TableHead>
            <TableHead className="h-11 p-3 font-medium">Status</TableHead>
            <TableHead className="h-11 p-3 font-medium">Opened by</TableHead>
            <TableHead className="h-11 p-3 font-medium">Opened at</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRows visits={visits} isLoading={isLoading} />
        </TableBody>
      </Table>
    </div>
  );
}
