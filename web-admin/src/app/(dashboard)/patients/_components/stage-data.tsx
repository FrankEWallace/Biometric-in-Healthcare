import type { StageName } from "@/lib/patients/api";

interface Prescription {
  name: string;
  dosage: string;
}

interface LabTest {
  name: string;
  result: string;
  value: string;
}

interface Medication {
  name: string;
  dosage: string;
  dispensed: boolean;
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="grid gap-0.5">
      <span className="text-muted-foreground text-xs">{label}</span>
      <span className="text-sm">{value}</span>
    </div>
  );
}

function TriageData({ data }: { data: Record<string, unknown> }) {
  return (
    <div className="grid @sm:grid-cols-4 grid-cols-2 gap-3">
      <Field label="Blood pressure" value={String(data.bp ?? "—")} />
      <Field label="Pulse" value={data.pulse ? `${data.pulse} bpm` : "—"} />
      <Field label="Temperature" value={data.temp ? `${data.temp}°C` : "—"} />
      <Field label="Weight" value={data.weight ? `${data.weight} kg` : "—"} />
    </div>
  );
}

function ConsultationData({ data }: { data: Record<string, unknown> }) {
  const prescriptions = (data.prescriptions as Prescription[] | undefined) ?? [];
  const labOrders = (data.lab_orders as string[] | undefined) ?? [];
  return (
    <div className="flex flex-col gap-3">
      <Field label="Diagnosis" value={String(data.diagnosis ?? "—")} />
      <Field label="Notes" value={String(data.notes ?? "—")} />
      {labOrders.length > 0 && <Field label="Lab orders" value={labOrders.join(", ")} />}
      {prescriptions.length > 0 && (
        <div className="grid gap-1">
          <span className="text-muted-foreground text-xs">Prescriptions</span>
          <ul className="list-inside list-disc text-sm">
            {prescriptions.map((p) => (
              <li key={p.name}>
                {p.name} — {p.dosage}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function LaboratoryData({ data }: { data: Record<string, unknown> }) {
  const tests = (data.tests as LabTest[] | undefined) ?? [];
  return (
    <div className="grid gap-1">
      {tests.map((t) => (
        <div key={t.name} className="flex items-center justify-between border-b py-1 text-sm last:border-0">
          <span>{t.name}</span>
          <span className={t.result === "elevated" ? "text-amber-600 dark:text-amber-400" : "text-muted-foreground"}>
            {t.value} ({t.result})
          </span>
        </div>
      ))}
    </div>
  );
}

function PharmacyData({ data }: { data: Record<string, unknown> }) {
  const medications = (data.medications as Medication[] | undefined) ?? [];
  return (
    <div className="grid gap-1">
      {medications.map((m) => (
        <div key={m.name} className="flex items-center justify-between border-b py-1 text-sm last:border-0">
          <span>
            {m.name} — {m.dosage}
          </span>
          <span className="text-muted-foreground text-xs">{m.dispensed ? "Dispensed" : "Not dispensed"}</span>
        </div>
      ))}
    </div>
  );
}

export function StageData({ stage, data }: { stage: StageName; data: Record<string, unknown> | null }) {
  if (!data) return <p className="text-muted-foreground text-sm">No data recorded for this stage.</p>;

  switch (stage) {
    case "triage":
      return <TriageData data={data} />;
    case "consultation":
      return <ConsultationData data={data} />;
    case "laboratory":
      return <LaboratoryData data={data} />;
    case "pharmacy":
      return <PharmacyData data={data} />;
    default:
      return <p className="text-muted-foreground text-sm">No structured data for this stage.</p>;
  }
}
