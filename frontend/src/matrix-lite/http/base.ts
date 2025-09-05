export interface HttpOptions {
  method?: string;
  accessToken?: string;
  body?: any;
}

export async function httpRequest(baseUrl: string, path: string, opts: HttpOptions = {}): Promise<any> {
  const url = baseUrl.replace(/\/$/, '') + path;
  const headers: Record<string, string> = {};
  if (opts.accessToken) headers['Authorization'] = `Bearer ${opts.accessToken}`;
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetch(url, {
    method: opts.method ?? 'GET',
    headers,
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}`);
  }
  if (res.status === 204) return undefined;
  return res.json();
}
