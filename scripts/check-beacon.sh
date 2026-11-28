#!/usr/bin/env bash
# Guard: every Beacon view must use the SHARED BeaconFreshness cluster (the "Checked" stamp + circular
# refresh button), never hand-roll a header. `arrow.clockwise` belongs to BeaconFreshness.swift only.
# The four original cards use BeaconFreshness directly; the two-panel widgets get it through
# BeaconPanelHeader (via BeaconPanelBody). Run in CI / before handing back. Exits non-zero on a violation.
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
for f in Shared/Panels/*.swift; do
  if grep -q "arrow.clockwise" "$f"; then
    echo "✗ $f hand-rolls the refresh glyph — use BeaconPanelHeader / BeaconFreshness." >&2
    fail=1
  fi
done
if ! grep -q "BeaconFreshness(" Shared/Panels/BeaconPanelHeader.swift; then
  echo "✗ Shared/Panels/BeaconPanelHeader.swift does not use the shared BeaconFreshness cluster." >&2
  fail=1
fi
for v in BeaconTilePanelView BatteriesPanelView ActivityPanelView; do
  if ! grep -q "BeaconPanelBody(" "Shared/Panels/$v.swift"; then
    echo "✗ Shared/Panels/$v.swift does not use BeaconPanelBody (the shared header)." >&2
    fail=1
  fi
done
if [ $fail -eq 0 ]; then echo "✓ Beacon shared-freshness guard passed (four cards and five two-panel widgets use BeaconFreshness)"; fi
exit $fail
