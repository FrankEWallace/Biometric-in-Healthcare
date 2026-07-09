"use client";

import { useEffect, useState } from "react";

import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useAuth } from "@/lib/auth/auth-context";
import {
  getHospitals,
  getOpenVisitCount,
  getPatientCount,
  getRecentVisits,
  getVerificationSummary,
  type Hospital,
  type VisitListItem,
} from "@/lib/dashboard/api";

import { HospitalSelector } from "./_components/hospital-selector";
import { type DashboardMetrics, MetricCards } from "./_components/metric-cards";
import { RecentVisitsTable } from "./_components/recent-visits-table";

export default function Page() {
  const { user } = useAuth();
  const isSuperAdmin = user?.role === "super_admin";

  const [hospitals, setHospitals] = useState<Hospital[]>([]);
  const [hospitalId, setHospitalId] = useState<number | "all">("all");
  const [metrics, setMetrics] = useState<DashboardMetrics | null>(null);
  const [visits, setVisits] = useState<VisitListItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    if (isSuperAdmin) {
      getHospitals()
        .then(setHospitals)
        .catch(() => undefined);
    }
  }, [isSuperAdmin]);

  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    setIsLoading(true);

    const scopedHospitalId = isSuperAdmin && hospitalId !== "all" ? hospitalId : undefined;

    void Promise.all([
      getVerificationSummary(scopedHospitalId),
      isSuperAdmin ? Promise.resolve(null) : getPatientCount(),
      isSuperAdmin ? Promise.resolve(0) : getOpenVisitCount(),
      isSuperAdmin ? Promise.resolve([]) : getRecentVisits(),
    ])
      .then(([verification, enrollmentCount, openVisitCount, recentVisits]) => {
        if (cancelled) return;
        setMetrics({
          verificationTotal: verification.total,
          verificationMatched: verification.matched,
          enrollmentCount,
          openVisitCount,
        });
        setVisits(recentVisits);
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [user, isSuperAdmin, hospitalId]);

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      {isSuperAdmin && (
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-muted-foreground text-sm">
            Patient and visit counts require a hospital-scoped account and aren&apos;t available cross-hospital yet —
            only verification stats below reflect the selected scope.
          </p>
          <HospitalSelector hospitals={hospitals} value={hospitalId} onChange={setHospitalId} />
        </div>
      )}

      <MetricCards metrics={metrics} isLoading={isLoading} />

      {isSuperAdmin ? (
        <Card>
          <CardHeader>
            <CardTitle>Recent visits</CardTitle>
            <CardDescription>
              Not available cross-hospital — sign in with a hospital-scoped admin account to see visit detail.
            </CardDescription>
          </CardHeader>
        </Card>
      ) : (
        <RecentVisitsTable visits={visits} isLoading={isLoading} />
      )}
    </div>
  );
}
