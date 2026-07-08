"use client";

import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";

import { useRouter } from "next/navigation";

import { api, ApiError } from "@/lib/api";
import { deleteClientCookie, getClientCookie, setClientCookie } from "@/lib/cookie.client";

import { AUTH_TOKEN_COOKIE, AUTH_USER_COOKIE } from "./cookies";
import type { AuthSession, AuthUser } from "./types";

// Only these roles get into the admin/superadmin web dashboard. Clinical
// staff (clerk/nurse/doctor/lab_technician/pharmacist) authenticate through
// the Flutter app instead — this login rejects them here, not on the API.
const DASHBOARD_ROLES = new Set(["admin", "super_admin"]);

interface AuthContextValue {
  user: AuthUser | null;
  isLoading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function readSessionFromCookies(): AuthSession | null {
  const token = getClientCookie(AUTH_TOKEN_COOKIE);
  const rawUser = getClientCookie(AUTH_USER_COOKIE);
  if (!token || !rawUser) return null;
  try {
    return { token, user: JSON.parse(decodeURIComponent(rawUser)) as AuthUser };
  } catch {
    return null;
  }
}

function writeSessionToCookies(session: AuthSession) {
  setClientCookie(AUTH_TOKEN_COOKIE, session.token);
  setClientCookie(AUTH_USER_COOKIE, encodeURIComponent(JSON.stringify(session.user)));
}

function clearSessionCookies() {
  deleteClientCookie(AUTH_TOKEN_COOKIE);
  deleteClientCookie(AUTH_USER_COOKIE);
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    setUser(readSessionFromCookies()?.user ?? null);
    setIsLoading(false);
  }, []);

  const login = useCallback(
    async (username: string, password: string) => {
      const { token, user: loggedInUser } = await api.post<{ token: string; user: AuthUser }>("/auth/login", {
        username,
        password,
      });

      if (!DASHBOARD_ROLES.has(loggedInUser.role)) {
        throw new ApiError("This account does not have access to the admin dashboard.", 403, null);
      }

      writeSessionToCookies({ token, user: loggedInUser });
      setUser(loggedInUser);
      router.push("/dashboard");
    },
    [router],
  );

  const logout = useCallback(async () => {
    try {
      await api.post("/auth/logout");
    } catch {
      // token may already be invalid/expired — still clear local state
    }
    clearSessionCookies();
    setUser(null);
    router.push("/login");
  }, [router]);

  return <AuthContext.Provider value={{ user, isLoading, login, logout }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return ctx;
}
