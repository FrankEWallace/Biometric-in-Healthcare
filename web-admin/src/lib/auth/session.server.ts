import "server-only";

import { cookies } from "next/headers";

import { AUTH_TOKEN_COOKIE, AUTH_USER_COOKIE } from "./cookies";
import type { AuthSession, AuthUser } from "./types";

// Used only by server components (the dashboard layout) to gate routes.
// The actual API calls happen client-side against the token cookie directly.
export async function getServerSession(): Promise<AuthSession | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(AUTH_TOKEN_COOKIE)?.value;
  const rawUser = cookieStore.get(AUTH_USER_COOKIE)?.value;

  if (!token || !rawUser) {
    return null;
  }

  try {
    const user = JSON.parse(decodeURIComponent(rawUser)) as AuthUser;
    return { token, user };
  } catch {
    return null;
  }
}
