export function resolveApiUrl(apiUrl: string | undefined): string | undefined {
  const value = apiUrl?.trim();
  if (!value) return undefined;

  if (typeof window === "undefined") return value;

  const currentOrigin = window.location.origin;
  const parsed = new URL(value, currentOrigin);
  const pathname = parsed.pathname.replace(/\/$/, "");

  if (pathname === "/api") {
    return `${currentOrigin}${parsed.pathname}${parsed.search}${parsed.hash}`;
  }

  return parsed.toString();
}
