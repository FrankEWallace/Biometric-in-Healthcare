import { AlertCircleIcon } from "lucide-react";

import { Button } from "@/components/ui/button";

/**
 * A distinct "something went wrong loading" panel — visually different from an
 * empty state so an operator can tell a failed fetch apart from genuinely-empty
 * data (the audit log especially must never read "No entries" on error).
 */
export function LoadError({
  message = "Couldn't load this data.",
  onRetry,
}: {
  message?: string;
  onRetry?: () => void;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 p-8 text-center">
      <AlertCircleIcon className="size-6 text-destructive" />
      <p className="text-destructive text-sm font-medium">{message}</p>
      {onRetry && (
        <Button variant="outline" size="sm" onClick={onRetry}>
          Retry
        </Button>
      )}
    </div>
  );
}
