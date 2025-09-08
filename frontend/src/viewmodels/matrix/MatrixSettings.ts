const NOTIFY_COOLDOWN_KEY = 'matrix_notify_cooldown_ms';

function loadNumber(key: string, def: number): number {
  try {
    const v = localStorage.getItem(key);
    if (v == null) return def;
    const n = Number(v);
    return Number.isFinite(n) && n >= 0 ? n : def;
  } catch {
    return def;
  }
}

export const matrixSettings = {
  recoveryKey: '',
  // Per-room notification cooldown in milliseconds; 0 = always notify
  notifyCooldownMs: loadNumber(NOTIFY_COOLDOWN_KEY, 0),
  saveNotifyCooldown(ms: number) {
    const val = Math.max(0, Math.floor(ms));
    this.notifyCooldownMs = val;
    try {
      localStorage.setItem(NOTIFY_COOLDOWN_KEY, String(val));
    } catch {
      // ignore storage errors
    }
  },
};
