// Live state over the authenticated WebSocket. Every (re)connect starts with a
// full snapshot from the server, so state is correct after any interruption.

import type { Device, Metrics } from './api';

export const live = $state({
  connected: false,
  devices: [] as Device[],
  metrics: null as Metrics | null,
  seq: 0,
});

let socket: WebSocket | null = null;
let wanted = false;
let attempt = 0;
let timer: ReturnType<typeof setTimeout> | undefined;
let onUnauthorized: (() => void) | undefined;

export function connect(unauthorized: () => void) {
  onUnauthorized = unauthorized;
  wanted = true;
  open();
}

export function disconnect() {
  wanted = false;
  clearTimeout(timer);
  socket?.close();
  socket = null;
  live.connected = false;
  live.devices = [];
  live.metrics = null;
}

function open() {
  if (!wanted || socket) return;
  const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  const ws = new WebSocket(`${scheme}://${location.host}/api/ws`);
  socket = ws;

  ws.onopen = () => {
    attempt = 0;
    live.connected = true;
  };

  ws.onmessage = (e) => {
    let msg: any;
    try {
      msg = JSON.parse(e.data);
    } catch {
      return;
    }
    if (msg.type === 'snapshot') {
      live.devices = msg.devices;
      if (msg.metrics) live.metrics = msg.metrics;
      live.seq = msg.seq;
    } else if (msg.type === 'device_state') {
      applyDevice(msg.device);
      live.seq = msg.seq;
    } else if (msg.type === 'metrics') {
      live.metrics = msg.metrics;
      live.seq = msg.seq;
    }
  };

  ws.onclose = async () => {
    if (socket === ws) socket = null;
    live.connected = false;
    if (!wanted) return;
    // A closed socket does not say why. Ask the API whether we are still
    // signed in before retrying.
    try {
      const res = await fetch('/api/me', { credentials: 'same-origin' });
      if (res.status === 401) {
        wanted = false;
        onUnauthorized?.();
        return;
      }
    } catch {
      // server unreachable: fall through to retry
    }
    attempt += 1;
    timer = setTimeout(open, Math.min(15000, 500 * 2 ** Math.min(attempt, 5)));
  };
}

export function applyDevice(device: Device) {
  const i = live.devices.findIndex((d) => d.id === device.id);
  if (i >= 0) live.devices[i] = device;
  else live.devices.push(device);
}
