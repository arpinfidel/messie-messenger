const DEFAULT_API_BASE_URL = 'http://localhost:8080/api/v1';

function normalizeBaseUrl(input: string): string {
  return input.replace(/\/+$/, '');
}

export function getApiBaseUrl(): string {
  const raw = import.meta.env.VITE_API_BASE_URL;
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (trimmed.length > 0) {
      return normalizeBaseUrl(trimmed);
    }
  }
  return normalizeBaseUrl(DEFAULT_API_BASE_URL);
}

export function getEmailApiBaseUrl(): string {
  return normalizeBaseUrl(`${DEFAULT_API_BASE_URL}/email`);
}

export { DEFAULT_API_BASE_URL };
