"use client";

import { Activity, Fingerprint, ShieldAlert, UserPlus } from "lucide-react";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export interface DashboardMetrics {
  verificationTotal: number;
  verificationMatched: number;
  enrollmentCount: number | null;
  openVisitCount: number;
}

function formatPercent(matched: number, total: number): string {
  if (total === 0) return "—";
  const failedRate = ((total - matched) / total) * 100;
  return `${failedRate.toFixed(1)}%`;
}

export function MetricCards({ metrics, isLoading }: { metrics: DashboardMetrics | null; isLoading: boolean }) {
  const cards = [
    {
      icon: Fingerprint,
      label: "Verification volume",
      value: metrics ? metrics.verificationTotal.toLocaleString() : null,
      caption: "All-time verification attempts",
    },
    {
      icon: UserPlus,
      label: "Enrollments",
      value:
        metrics?.enrollmentCount !== null && metrics?.enrollmentCount !== undefined
          ? metrics.enrollmentCount.toLocaleString()
          : "—",
      caption: "Active enrolled patients",
    },
    {
      icon: ShieldAlert,
      label: "Failed-match rate",
      value: metrics ? formatPercent(metrics.verificationMatched, metrics.verificationTotal) : null,
      caption: "Non-matched or errored attempts",
    },
    {
      icon: Activity,
      label: "Open visits today",
      value: metrics ? metrics.openVisitCount.toLocaleString() : null,
      caption: "Currently in-progress visits",
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-4 *:data-[slot=card]:bg-linear-to-t *:data-[slot=card]:from-primary/5 *:data-[slot=card]:to-card *:data-[slot=card]:shadow-xs xl:grid-cols-4 dark:*:data-[slot=card]:bg-card">
      {cards.map((card) => (
        <Card key={card.label}>
          <CardHeader>
            <CardTitle>
              <div className="flex size-7 items-center justify-center rounded-lg border bg-muted text-muted-foreground">
                <card.icon className="size-4" />
              </div>
            </CardTitle>
            <CardDescription>{card.label}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-1">
            {isLoading ? (
              <Skeleton className="h-9 w-24" />
            ) : (
              <div className="font-medium text-3xl tabular-nums leading-none tracking-tight">{card.value ?? "—"}</div>
            )}
            <p className="text-muted-foreground text-sm">{card.caption}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
