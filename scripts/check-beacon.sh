#!/usr/bin/env bash
# Guard: the four Beacon views must use the SHARED BeaconFreshness cluster (the "Checked" stamp + circular
# refresh button), never hand-roll a header. `arrow.clockwise` belongs to BeaconFreshness.swift only.
# Run in CI / before handing back. Exits non-zero on a violation.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for v in AlarmBeaconView CarBeaconView ThermostatBeaconView CpBeaconView; do
  if grep -q "arrow.clockwise" "Shared/$v.swift"; then
    echo "✗ Shared/$v.swift hand-rolls the refresh glyph — use BeaconFreshness(checkedAt:, kind:, ink:)." >&2
    fail=1
  fi
  if ! grep -q "BeaconFreshness(" "Shared/$v.swift"; then
    echo "✗ Shared/$v.swift does not use the shared BeaconFreshness cluster." >&2
    fail=1
  fi
done
if [ $fail -eq 0 ]; then echo "✓ Beacon shared-freshness guard passed (all four views use BeaconFreshness)"; fi
exit $fail
