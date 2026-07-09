"use client";

import { format, parseISO } from "date-fns";

import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { Device } from "@/lib/geofence-devices/api";

function deviceLabel(userAgent: string | null): string {
  if (!userAgent) return "Unknown device";
  if (userAgent.includes("Dart") || userAgent.includes("Dalvik") || userAgent.includes("okhttp")) {
    return "Mobile app";
  }
  if (userAgent.includes("Mozilla")) return "Web browser";
  return userAgent.slice(0, 40);
}

export function DevicesTable({
  devices,
  isLoading,
  showHospital,
}: {
  devices: Device[];
  isLoading: boolean;
  showHospital: boolean;
}) {
  const columnCount = showHospital ? 6 : 5;

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>IP address</TableHead>
          <TableHead>Device</TableHead>
          <TableHead>Last used by</TableHead>
          {showHospital && <TableHead>Hospital</TableHead>}
          <TableHead>Requests</TableHead>
          <TableHead>Last seen</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {isLoading &&
          Array.from({ length: 5 }).map((_, i) => (
            // biome-ignore lint/suspicious/noArrayIndexKey: static loading skeleton rows
            <TableRow key={i}>
              <TableCell colSpan={columnCount} className="p-3">
                <Skeleton className="h-6 w-full" />
              </TableCell>
            </TableRow>
          ))}

        {!isLoading && devices.length === 0 && (
          <TableRow>
            <TableCell colSpan={columnCount} className="h-24 text-center text-muted-foreground">
              No device activity recorded yet.
            </TableCell>
          </TableRow>
        )}

        {!isLoading &&
          devices.map((device) => (
            <TableRow key={`${device.ip_address}-${device.user_agent}`}>
              <TableCell className="font-mono text-sm">{device.ip_address}</TableCell>
              <TableCell>
                <div className="flex flex-col">
                  <span className="text-sm">{deviceLabel(device.user_agent)}</span>
                  {device.user_agent && (
                    <span className="text-muted-foreground max-w-64 truncate text-xs" title={device.user_agent}>
                      {device.user_agent}
                    </span>
                  )}
                </div>
              </TableCell>
              <TableCell>
                {device.last_staff ? (
                  <div className="flex items-center gap-2">
                    <span className="text-sm">{device.last_staff.name}</span>
                    <Badge variant="outline">{device.last_staff.role}</Badge>
                  </div>
                ) : (
                  <span className="text-muted-foreground text-sm">—</span>
                )}
              </TableCell>
              {showHospital && <TableCell className="text-sm">{device.hospital?.name ?? "—"}</TableCell>}
              <TableCell className="text-sm tabular-nums">{device.request_count}</TableCell>
              <TableCell>
                <div className="flex flex-col">
                  <span className="text-sm">{format(parseISO(device.last_seen_at), "do MMM yyyy")}</span>
                  <span className="text-muted-foreground text-xs">
                    {format(parseISO(device.last_seen_at), "h:mm a")}
                  </span>
                </div>
              </TableCell>
            </TableRow>
          ))}
      </TableBody>
    </Table>
  );
}
