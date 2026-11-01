# Medium Thermostat: readable observed fan activity

Product and UX approved one bounded outcome: show whole `Fan only` in the ordinary Medium status row when a typed, current, settled range-mode observation reports fan activity and both targets are present. The repeated range yields because the right panel already displays the actionable targets.

The actual Medium host is 378 × 176.667 points. The baseline native caption truncates `Fan only · set 64–…`; current temperature, humidity, Heat 64/Cool 70 and Mode Auto/Fan On remain readable. A saved entry reached by tapping the colored rail confirms fan activity, configured `heat_cool`, 67, 50%, targets 64/70, no selected sensors, no operation and no recovery. Its temperature unit is not reported; no Fahrenheit/Celsius assumption is authorized.

Implementation is restricted to a pure typed display projection in `ThermostatPresentation.swift`, its existing tests, and the ordinary Medium visible Text call site in `ThermostatBeaconView.swift`.

- Admit only ready, current, available, settled range + observed fan activity with complete finite applicable targets and no error or feedback.
- Preserve the exact existing visible fallback for unknown, snapshot-only, pending/failed, stale, missing reading/target, unavailable and recovery cases.
- Preserve the canonical full status, accessibility priority, typed Readings/Controls details, target controls and their authority.
- Preserve fonts, geometry, padding, colors, sensors, freshness, routes, Small and focused Medium branches, canonical mapping and existing fixtures.

Verification is meaningful admission/fallback tests with a behavioral RED first, one independent source review, a full package test run, signed Simulator Debug/Release builds, and native UX acceptance. The finite WidgetKit matrix uses existing typed fan, auto, pending_mode, offline and unknown_targets fixtures at matched Medium/Large dimensions, followed by cleared fixture mode and the actual saved/live Home entry. Only eligible visible fan-caption pixels may change.

Native screenshots and installed executable/debug-dylib hashes bind the candidate separately from the older installed baseline. Existing outer fixture receipts establish family/category/frame, not a Text leaf's resolved font. The earlier focused Medium AX1 failure, arbitrary locales/sizes, VoiceOver, live commands and physical-device distribution remain separate open gates.

iOS distribution remains deferred under the existing release guide. Android v1.4.55 (149) is already published; this iOS-only source correction does not change that Android binary.
