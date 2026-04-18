export function resolveApiUrl(apiUrl: string | undefined): string | undefined {
  if (!apiUrl) return apiUrl;

  if (/^https?:\/\//i.test(apiUrl)) {
    return apiUrl;
  }

  if (typeof window === "undefined") {
    return apiUrl;
  }

  return new URL(apiUrl, window.location.origin).toString();
}
