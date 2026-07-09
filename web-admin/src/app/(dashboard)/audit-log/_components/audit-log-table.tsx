"use client";

import { format, parseISO } from "date-fns";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { AuditLogEntry } from "@/lib/audit-log/api";

function actionLabel(action: string) {
  return action
    .split("_")
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(" ");
}

function TableRows({ entries, isLoading }: { entries: AuditLogEntry[]; isLoading: boolean }) {
  if (isLoading) {
    return (
      <>
        {Array.from({ length: 8 }).map((_, i) => (
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

  if (entries.length === 0) {
    return (
      <TableRow>
        <TableCell colSpan={5} className="h-24 text-center text-muted-foreground">
          No audit log entries match these filters.
        </TableCell>
      </TableRow>
    );
  }

  return (
    <>
      {entries.map((entry) => (
        <TableRow key={entry.id}>
          <TableCell className="p-3 align-middle">
            <div className="grid gap-0.5">
              <span className="text-sm">{format(parseISO(entry.created_at), "do MMM yyyy")}</span>
              <span className="text-muted-foreground text-xs">{format(parseISO(entry.created_at), "h:mm:ss a")}</span>
            </div>
          </TableCell>
          <TableCell className="p-3 align-middle text-sm">
            {entry.staff ? `${entry.staff.name} (${entry.staff.role})` : "System"}
          </TableCell>
          <TableCell className="p-3 align-middle">
            <Badge variant="outline" className="px-1.5 text-muted-foreground">
              {actionLabel(entry.action)}
            </Badge>
          </TableCell>
          <TableCell className="p-3 align-middle text-sm">{entry.patient?.full_name ?? "—"}</TableCell>
          <TableCell className="p-3 align-middle text-muted-foreground text-sm">
            {entry.response_status ?? "—"}
          </TableCell>
        </TableRow>
      ))}
    </>
  );
}

export function AuditLogTable({ entries, isLoading }: { entries: AuditLogEntry[]; isLoading: boolean }) {
  return (
    <div className="overflow-hidden rounded-lg border bg-card">
      <Table>
        <TableHeader className="bg-muted/15">
          <TableRow>
            <TableHead className="h-11 p-3 font-medium">Timestamp</TableHead>
            <TableHead className="h-11 p-3 font-medium">Actor</TableHead>
            <TableHead className="h-11 p-3 font-medium">Action</TableHead>
            <TableHead className="h-11 p-3 font-medium">Target</TableHead>
            <TableHead className="h-11 p-3 font-medium">Result</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRows entries={entries} isLoading={isLoading} />
        </TableBody>
      </Table>
    </div>
  );
}
