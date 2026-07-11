"use client";

import { useEffect, useState } from "react";

import { LoadError } from "@/components/load-error";
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
  const [error, setError] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    if (isAnyAdmin) {
      void getStaff()
        .then(setStaff)
        .catch(() => undefined);
    }
  }, [isAnyAdmin]);

  // biome-ignore lint/correctness/useExhaustiveDependencies: reloadToken is an intentional retrigger — bumped by the LoadError retry to re-run the fetch.
  useEffect(() => {
    // `cancelled` doubles as the ordering guard: when filters/page change, the
    // previous request's cleanup fires first, so a slow earlier response can
    // never overwrite the current one.
    let cancelled = false;
    setIsLoading(true);
    setError(false);
    void getAuditLogs({
      action: filters.action || undefined,
      staff_id: filters.staffId ? Number(filters.staffId) : undefined,
      from: filters.from || undefined,
      to: filters.to || undefined,
      page,
    })
      .then((result) => {
        if (cancelled) return;
        setEntries(result.data);
        setLastPage(result.last_page);
      })
      .catch(() => {
        if (!cancelled) setError(true);
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [filters, page, reloadToken]);

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
          {error ? (
            <LoadError message="Couldn't load the audit log." onRetry={() => setReloadToken((t) => t + 1)} />
          ) : (
            <AuditLogTable entries={entries} isLoading={isLoading} />
          )}
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
