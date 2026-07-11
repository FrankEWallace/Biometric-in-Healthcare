"use client";

import { useCallback, useEffect, useState } from "react";

import { LoadError } from "@/components/load-error";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { getMatcherConfig, type MatcherConfig } from "@/lib/matcher-config/api";

function ConfigRow({ label, hint, children }: { label: string; hint: string; children: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4 border-b py-3 last:border-b-0">
      <div>
        <p className="text-sm font-medium">{label}</p>
        <p className="text-muted-foreground text-xs">{hint}</p>
      </div>
      <div className="shrink-0 text-right">{children}</div>
    </div>
  );
}

export default function Page() {
  const [config, setConfig] = useState<MatcherConfig | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  // biome-ignore lint/correctness/useExhaustiveDependencies: reloadToken is an intentional retrigger — bumped by the LoadError retry to re-run the fetch.
  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setError(false);
    void getMatcherConfig()
      .then((c) => {
        if (!cancelled) setConfig(c);
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
  }, [reloadToken]);

  return (
    <div className="@container/main flex flex-col gap-4 md:gap-6">
      <Card>
        <CardHeader>
          <CardTitle>Matcher configuration</CardTitle>
          <CardDescription>
            Read-only view of the operating points the backend is using right now. These values are set through server
            environment variables and calibration tooling, not editable from the dashboard — changing them requires a
            recalibration and redeploy.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading && <Skeleton className="h-48 w-full" />}

          {!isLoading && error && <LoadError message="Couldn't load matcher configuration." onRetry={reload} />}

          {config && (
            <div className="flex flex-col">
              <ConfigRow
                label="Fingerprint match threshold"
                hint="Contact-based minutiae score required to accept a 1:1 match (FINGERPRINT_MATCH_THRESHOLD)."
              >
                <span className="font-mono text-sm tabular-nums">{config.fingerprint.match_threshold}</span>
              </ConfigRow>

              <ConfigRow
                label="Contactless (four-finger) threshold"
                hint="Fused hand-score threshold for contactless capture. Unset means contactless never auto-accepts — results go to review."
              >
                {config.fingerprint.contactless_match_threshold != null ? (
                  <span className="font-mono text-sm tabular-nums">
                    {config.fingerprint.contactless_match_threshold}
                  </span>
                ) : (
                  <Badge variant="secondary">Not set — review only</Badge>
                )}
              </ConfigRow>

              <ConfigRow
                label="Face match threshold (1:1)"
                hint="Cosine similarity required to confirm a face against a known patient (code constant)."
              >
                <span className="font-mono text-sm tabular-nums">{config.face.match_threshold}</span>
              </ConfigRow>

              <ConfigRow
                label="Face identify threshold (1:N)"
                hint="Minimum similarity for a gallery candidate to appear in identification shortlists (code constant)."
              >
                <span className="font-mono text-sm tabular-nums">{config.face.identify_threshold}</span>
              </ConfigRow>

              <ConfigRow
                label="Geofence fail-open policy"
                hint="What happens at hospitals with no GPS or WiFi geofence configured (GEOFENCE_FAIL_OPEN)."
              >
                {config.geofence.fail_open ? (
                  <Badge variant="destructive">Fail open — access allowed</Badge>
                ) : (
                  <Badge variant="secondary">Fail closed — access denied</Badge>
                )}
              </ConfigRow>

              <ConfigRow label="Matcher service" hint="Python biometric service the backend forwards captures to.">
                <span className="font-mono text-sm">{config.fingerprint.service_url}</span>
              </ConfigRow>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
