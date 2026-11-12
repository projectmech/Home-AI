export type Role = 'admin' | 'standard' | 'restricted';
export type DeviceKind = 'light' | 'thermostat' | 'speaker' | 'lock' | 'temperature_sensor';

export interface User {
  username: string;
  role: Role;
}

export interface Device {
  id: string;
  connector: string;
  name: string;
  kind: DeviceKind;
  room: string;
  simulated: boolean;
  state: Record<string, unknown>;
  updated_at: number;
}

export interface Disk {
  name: string;
  mount: string;
  file_system: string;
  kind: 'ssd' | 'hdd' | 'unknown';
  total_bytes: number;
  available_bytes: number;
}

export interface Metrics {
  ts: number;
  uptime_s: number;
  cpu_usage_percent: number | null;
  per_core_percent: number[] | null;
  load_average: [number, number, number] | null;
  mem_total_bytes: number;
  mem_used_bytes: number;
  mem_available_bytes: number;
  swap_total_bytes: number;
  swap_used_bytes: number;
  process_rss_bytes: number | null;
  disks: Disk[];
  cpu_model: string;
  logical_cores: number;
  physical_cores: number | null;
  os_name: string | null;
  os_version: string | null;
  kernel_version: string | null;
  host_name: string | null;
  app_version: string;
}

export interface Hardware {
  note: string;
  arch: string;
  boot_mode: string;
  cpu: { model: string | null; logical_cores: number | null; physical_cores: number | null; flags: string[] };
  block_devices: { name: string; model: string | null; size_bytes: number | null; rotational: boolean | null }[];
  network: { name: string; mac: string; addresses: string[] }[];
  smart: string;
  binary_baseline: string;
  warnings: string[];
}

export interface AuditEntry {
  id: number;
  ts: number;
  username: string | null;
  action: string;
  target: string | null;
  outcome: string;
  detail: string | null;
}

export type Action =
  | { action: 'set_power'; on: boolean }
  | { action: 'set_brightness'; percent: number }
  | { action: 'set_target_temperature'; celsius: number }
  | { action: 'set_playing'; playing: boolean }
  | { action: 'set_volume'; percent: number }
  | { action: 'lock' }
  | { action: 'unlock'; confirm_password?: string };

export interface ActionResult {
  outcome: 'confirmed' | 'failed';
  reason?: string;
  device: Device;
}

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`/api${path}`, {
      method,
      credentials: 'same-origin',
      headers: body === undefined ? undefined : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, 'network', 'Cannot reach the server.');
  }
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    throw new ApiError(res.status, data?.error ?? 'error', data?.message ?? `Request failed (${res.status}).`);
  }
  return data as T;
}

export const api = {
  health: () => request<{ setup_required: boolean; version: string }>('GET', '/health'),
  setup: (setup_token: string, username: string, password: string) =>
    request<{ ok: true }>('POST', '/setup', { setup_token, username, password }),
  login: (username: string, password: string) => request<User>('POST', '/login', { username, password }),
  logout: () => request<{ ok: true }>('POST', '/logout'),
  me: () => request<User>('GET', '/me'),
  act: (id: string, action: Action) =>
    request<ActionResult>('POST', `/devices/${encodeURIComponent(id)}/actions`, action),
  metrics: () => request<{ metrics: Metrics }>('GET', '/server/metrics'),
  hardware: () => request<{ hardware: Hardware }>('GET', '/server/hardware'),
  audit: () => request<{ entries: AuditEntry[] }>('GET', '/audit'),
};

export function bytes(n: number | null | undefined): string {
  if (n == null) return 'Not available';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v >= 100 || i === 0 ? v.toFixed(0) : v.toFixed(1)} ${units[i]}`;
}

export function duration(seconds: number): string {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}
