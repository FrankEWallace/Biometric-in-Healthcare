"use client";

import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { NativeSelect, NativeSelectOption } from "@/components/ui/native-select";
import { AUDIT_ACTIONS } from "@/lib/audit-log/api";
import type { StaffUser } from "@/lib/staff/api";

function actionLabel(action: string) {
  return action
    .split("_")
    .map((w) => w[0].toUpperCase() + w.slice(1))
    .join(" ");
}

export interface AuditLogFilterState {
  action: string;
  staffId: string;
  from: string;
  to: string;
}

export function AuditLogFilters({
  value,
  onChange,
  staff,
  showActorFilter,
}: {
  value: AuditLogFilterState;
  onChange: (value: AuditLogFilterState) => void;
  staff: StaffUser[];
  showActorFilter: boolean;
}) {
  return (
    <div className="grid @2xl/main:grid-cols-4 @sm/main:grid-cols-2 grid-cols-1 gap-3">
      <Field className="gap-1.5">
        <FieldLabel htmlFor="filter-action">Action</FieldLabel>
        <NativeSelect
          id="filter-action"
          value={value.action}
          onChange={(e) => onChange({ ...value, action: e.target.value })}
        >
          <NativeSelectOption value="">All actions</NativeSelectOption>
          {AUDIT_ACTIONS.map((action) => (
            <NativeSelectOption key={action} value={action}>
              {actionLabel(action)}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </Field>

      {showActorFilter && (
        <Field className="gap-1.5">
          <FieldLabel htmlFor="filter-actor">Actor</FieldLabel>
          <NativeSelect
            id="filter-actor"
            value={value.staffId}
            onChange={(e) => onChange({ ...value, staffId: e.target.value })}
          >
            <NativeSelectOption value="">All staff</NativeSelectOption>
            {staff.map((member) => (
              <NativeSelectOption key={member.id} value={member.id}>
                {member.name}
              </NativeSelectOption>
            ))}
          </NativeSelect>
        </Field>
      )}

      <Field className="gap-1.5">
        <FieldLabel htmlFor="filter-from">From</FieldLabel>
        <Input
          id="filter-from"
          type="date"
          value={value.from}
          onChange={(e) => onChange({ ...value, from: e.target.value })}
        />
      </Field>

      <Field className="gap-1.5">
        <FieldLabel htmlFor="filter-to">To</FieldLabel>
        <Input
          id="filter-to"
          type="date"
          value={value.to}
          onChange={(e) => onChange({ ...value, to: e.target.value })}
        />
      </Field>
    </div>
  );
}
