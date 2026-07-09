"use client";

import { format, parseISO } from "date-fns";
import { AlertTriangle, Check, Clock } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { STAGE_LABEL, STAGE_ORDER, type VisitDetail, type VisitStage } from "@/lib/patients/api";
import { cn } from "@/lib/utils";

import { StageData } from "./stage-data";

function StageStep({ stage, order }: { stage: VisitStage | undefined; order: number }) {
  const hasOverride = stage?.supervisorOverride && stage.supervisorOverride.status !== "denied";
  const isCompleted = stage?.status === "completed";

  return (
    <div className="flex flex-1 flex-col items-center gap-1.5 text-center">
      <div
        className={cn(
          "flex size-8 items-center justify-center rounded-full border-2 font-medium text-sm",
          isCompleted
            ? "border-primary bg-primary text-primary-foreground"
            : "border-muted-foreground/30 bg-muted text-muted-foreground",
        )}
      >
        {isCompleted ? <Check className="size-4" /> : order}
      </div>
      <span className="text-xs leading-tight">{STAGE_LABEL[STAGE_ORDER[order - 1]]}</span>
      {hasOverride && (
        <Badge variant="outline" className="gap-1 px-1.5 text-amber-600 text-xs dark:text-amber-400">
          <AlertTriangle className="size-3" />
          Override
        </Badge>
      )}
    </div>
  );
}

export function VisitTimeline({ visit }: { visit: VisitDetail }) {
  const stageByName = new Map(visit.stages.map((s) => [s.stage, s]));
  const completedStages = STAGE_ORDER.filter((name) => stageByName.get(name)?.status === "completed");
  const defaultTab = completedStages.at(-1) ?? STAGE_ORDER[0];

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center gap-1">
        {STAGE_ORDER.map((name, i) => (
          <StageStep key={name} stage={stageByName.get(name)} order={i + 1} />
        ))}
      </div>

      <Tabs defaultValue={defaultTab}>
        <TabsList className="w-full">
          {STAGE_ORDER.map((name) => (
            <TabsTrigger key={name} value={name} className="flex-1">
              {STAGE_LABEL[name]}
            </TabsTrigger>
          ))}
        </TabsList>

        {STAGE_ORDER.map((name) => {
          const stage = stageByName.get(name);
          return (
            <TabsContent key={name} value={name} className="flex flex-col gap-4 rounded-lg border p-4">
              {stage ? (
                <>
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <Badge variant={stage.status === "completed" ? "default" : "outline"}>
                      {stage.status === "completed" ? "Completed" : "Pending"}
                    </Badge>
                    {stage.verifiedBy && stage.verified_at && (
                      <span className="text-muted-foreground text-xs">
                        Verified by {stage.verifiedBy.name} ({stage.verifiedBy.role}) on{" "}
                        {format(parseISO(stage.verified_at), "do MMM yyyy, h:mm a")}
                      </span>
                    )}
                  </div>
                  {stage.supervisorOverride && (
                    <div className="flex items-start gap-2 rounded-md border border-amber-500/30 bg-amber-500/5 p-2 text-sm">
                      <AlertTriangle className="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400" />
                      <div>
                        <span className="font-medium">Supervisor override — {stage.supervisorOverride.status}</span>
                        {stage.supervisorOverride.staff_note && (
                          <p className="text-muted-foreground">{stage.supervisorOverride.staff_note}</p>
                        )}
                      </div>
                    </div>
                  )}
                  <StageData stage={name} data={stage.simulated_data} />
                </>
              ) : (
                <p className="flex items-center gap-2 text-muted-foreground text-sm">
                  <Clock className="size-4" />
                  This stage hasn&apos;t started yet.
                </p>
              )}
            </TabsContent>
          );
        })}
      </Tabs>
    </div>
  );
}
