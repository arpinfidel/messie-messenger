// Minimal canonical JSON for Matrix signing:
// - Sort object keys lexicographically (code-point order)
// - No whitespace
// - Preserve array order
// - Exclude properties not in the input
// - Values encoded with standard JSON rules

function isPlainObject(v: any): v is Record<string, any> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

export function canonicalize(value: any): string {
  return _canon(value);
}

function _canon(v: any): string {
  if (v === null) return 'null';
  const t = typeof v;
  if (t === 'number') {
    if (!Number.isFinite(v)) throw new Error('Non-finite number in canonical JSON');
    return JSON.stringify(v);
  }
  if (t === 'boolean' || t === 'string') return JSON.stringify(v);
  if (Array.isArray(v)) {
    const items = v.map((it) => _canon(it)).join(',');
    return `[${items}]`;
  }
  if (isPlainObject(v)) {
    const keys = Object.keys(v).sort();
    const parts: string[] = [];
    for (const k of keys) {
      parts.push(JSON.stringify(k) + ':' + _canon(v[k]));
    }
    return `{${parts.join(',')}}`;
  }
  // Unsupported types
  throw new Error('Unsupported type in canonical JSON');
}

