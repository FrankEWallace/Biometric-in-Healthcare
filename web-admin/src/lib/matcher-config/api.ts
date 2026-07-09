import { api } from "@/lib/api";

export interface MatcherConfig {
  fingerprint: {
    match_threshold: number;
    contactless_match_threshold: number | null;
    service_url: string;
  };
  face: {
    match_threshold: number;
    identify_threshold: number;
  };
  geofence: {
    fail_open: boolean;
  };
  source: string;
}

export async function getMatcherConfig(): Promise<MatcherConfig> {
  return api.get<MatcherConfig>("/matcher-config");
}
