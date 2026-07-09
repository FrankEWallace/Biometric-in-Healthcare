"use client";

import { useCallback, useEffect, useState } from "react";

import { RefreshCw } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getQueue, type QueueVisit } from "@/lib/visit-ops/api";

import { KanbanBoard } from "./_components/kanban-board";

const POLL_INTERVAL_MS = 15_000;

export default function Page() {
  const [visits, setVisits] = useState<QueueVisit[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  const reload = useCallback(() => {
    void getQueue()
      .then(setVisits)
      .finally(() => setIsLoading(false));
  }, []);

  useEffect(() => {
    reload();
    const interval = setInterval(reload, POLL_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [reload]);

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div>
            <CardTitle>Visit ops</CardTitle>
            <CardDescription>In-progress visits by stage, refreshed every 15 seconds.</CardDescription>
          </div>
          <Button variant="outline" size="sm" onClick={reload}>
            <RefreshCw className="size-4" />
            Refresh
          </Button>
        </CardHeader>
        <CardContent>
          <KanbanBoard visits={visits} isLoading={isLoading} />
        </CardContent>
      </Card>
    </div>
  );
}
