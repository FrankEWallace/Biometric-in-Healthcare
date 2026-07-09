import { api } from "@/lib/api";
import { STAGE_ORDER, type StageName } from "@/lib/patients/api";

export interface QueueStage {
  id: number;
  visit_id: number;
  stage: StageName;
  status: "pending" | "completed";
  verified_at: string | null;
}

export interface QueueVisit {
  id: number;
  patient: { id: number; full_name: string; hospital_patient_id: string | null } | null;
  stages: QueueStage[];
  opened_at: string;
}

export async function getQueue(): Promise<QueueVisit[]> {
  const { queue } = await api.get<{ queue: QueueVisit[] }>("/queue");
  return queue;
}

// The board column a visit belongs to: the first stage not yet completed.
// An open visit with every stage completed shouldn't normally occur (it
// would be closed), but falls back to the last stage rather than vanishing.
export function currentStage(visit: QueueVisit): StageName {
  const byName = new Map(visit.stages.map((s) => [s.stage, s]));
  const pending = STAGE_ORDER.find((name) => byName.get(name)?.status !== "completed");
  return pending ?? STAGE_ORDER[STAGE_ORDER.length - 1];
}

// When the visit entered its current stage: the previous stage's
// verification time, or the visit's open time for the first stage.
export function enteredStageAt(visit: QueueVisit): string {
  const stage = currentStage(visit);
  const index = STAGE_ORDER.indexOf(stage);
  if (index === 0) return visit.opened_at;

  const byName = new Map(visit.stages.map((s) => [s.stage, s]));
  const previous = byName.get(STAGE_ORDER[index - 1]);
  return previous?.verified_at ?? visit.opened_at;
}
