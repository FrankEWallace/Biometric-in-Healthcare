import { deleteClientCookie, getClientCookie } from "@/lib/cookie.client";

import { AUTH_TOKEN_COOKIE, AUTH_USER_COOKIE } from "./auth/cookies";

export const API_BASE_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000/api";

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = typeof document !== "undefined" ? getClientCookie(AUTH_TOKEN_COOKIE) : undefined;

  const headers = new Headers(options.headers);
  headers.set("Accept", "application/json");
  if (options.body && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }

  const res = await fetch(`${API_BASE_URL}${path}`, { ...options, headers });
  const contentType = res.headers.get("content-type") ?? "";
  const data = contentType.includes("application/json") ? await res.json().catch(() => null) : null;

  if (!res.ok) {
    // An expired/revoked Sanctum token must route the operator back to login
    // rather than surface as a blank screen. Clear the session and redirect,
    // then still throw so the calling loader stops.
    if (res.status === 401 && typeof window !== "undefined") {
      deleteClientCookie(AUTH_TOKEN_COOKIE);
      deleteClientCookie(AUTH_USER_COOKIE);
      if (window.location.pathname !== "/login") {
        window.location.href = "/login";
      }
    }
    const message = (data && typeof data === "object" && "message" in data && String(data.message)) || res.statusText;
    throw new ApiError(message, res.status, data);
  }

  return data as T;
}

export const api = {
  get: <T>(path: string) => request<T>(path, { method: "GET" }),
  post: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "POST", body: body ? JSON.stringify(body) : undefined }),
  put: <T>(path: string, body?: unknown) =>
    request<T>(path, { method: "PUT", body: body ? JSON.stringify(body) : undefined }),
  delete: <T>(path: string) => request<T>(path, { method: "DELETE" }),
};
