"use client";

import { useEffect, useState } from "react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { type AuditLogEntry, getAuditLogs } from "@/lib/audit-log/api";
import { useAuth } from "@/lib/auth/auth-context";
import { getStaff, type StaffUser } from "@/lib/staff/api";

import { type AuditLogFilterState, AuditLogFilters } from "./_components/audit-log-filters";
import { AuditLogTable } from "./_components/audit-log-table";

const EMPTY_FILTERS: AuditLogFilterState = { action: "", staffId: "", from: "", to: "" };

export default function Page() {
  const { user } = useAuth();
  const isAnyAdmin = user?.role === "admin" || user?.role === "super_admin";

  const [filters, setFilters] = useState<AuditLogFilterState>(EMPTY_FILTERS);
  const [page, setPage] = useState(1);
  const [staff, setStaff] = useState<StaffUser[]>([]);
  const [entries, setEntries] = useState<AuditLogEntry[]>([]);
  const [lastPage, setLastPage] = useState(1);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    if (isAnyAdmin) {
      void getStaff().then(setStaff);
    }
  }, [isAnyAdmin]);

  useEffect(() => {
    setIsLoading(true);
    void getAuditLogs({
      action: filters.action || undefined,
      staff_id: filters.staffId ? Number(filters.staffId) : undefined,
      from: filters.from || undefined,
      to: filters.to || undefined,
      page,
    })
      .then((result) => {
        setEntries(result.data);
        setLastPage(result.last_page);
      })
      .finally(() => setIsLoading(false));
  }, [filters, page]);

  function onFiltersChange(next: AuditLogFilterState) {
    setFilters(next);
    setPage(1);
  }

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <Card>
        <CardHeader>
          <CardTitle>Audit log</CardTitle>
          <CardDescription>Every recorded staff action, filterable by action, actor, and date range.</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <AuditLogFilters value={filters} onChange={onFiltersChange} staff={staff} showActorFilter={isAnyAdmin} />
          <AuditLogTable entries={entries} isLoading={isLoading} />
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
        </CardContent>
      </Card>
    </div>
  );
}
