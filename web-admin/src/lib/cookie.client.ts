// Client-side cookie utilities.
// These functions manage cookies in the browser only.
// Server actions handle cookie updates on the server side.

function writeClientCookie(serializedCookie: string) {
  // biome-ignore lint/suspicious/noDocumentCookie: This project still uses document.cookie for broad browser support.
  document.cookie = serializedCookie;
}

export function setClientCookie(key: string, value: string, days = 7) {
  const expires = new Date(Date.now() + days * 864e5).toUTCString();
  // `Secure` is required in any non-dev deployment: the dashboard AND the API
  // must be served over TLS. It is dropped over plaintext HTTP, so we gate it
  // on the page protocol — the LAN/HTTP setup (NEXT_PUBLIC_API_URL=http://…) is
  // development-only. SameSite=Strict blocks the cookie on cross-site requests.
  const secure = typeof location !== "undefined" && location.protocol === "https:" ? "; Secure" : "";
  writeClientCookie(`${key}=${value}; expires=${expires}; path=/; SameSite=Strict${secure}`);
}

export function getClientCookie(key: string) {
  return document.cookie
    .split("; ")
    .find((row) => row.startsWith(`${key}=`))
    ?.split("=")[1];
}

export function deleteClientCookie(key: string) {
  writeClientCookie(`${key}=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/`);
}
