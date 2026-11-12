// Home preferences that change how the dashboard displays things.

import { api, type HomeSettings } from './api';

export const prefs = $state({
  home: null as HomeSettings | null,
});

export async function loadPrefs() {
  try {
    prefs.home = (await api.getHome()).home;
  } catch {
    // Keep defaults; the dashboard still works in Celsius.
  }
}

/** Format a Celsius reading in the unit the home is configured for. */
export function temperature(celsius: unknown, digits = 1): string {
  if (typeof celsius !== 'number') return 'Not available';
  if (prefs.home?.temperature_unit === 'fahrenheit') {
    return `${((celsius * 9) / 5 + 32).toFixed(digits)} °F`;
  }
  return `${celsius.toFixed(digits)} °C`;
}
