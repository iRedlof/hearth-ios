#!/usr/bin/env python3
"""Generate index.html for the iOS<->Android widget parity gallery.

Android renders live in  and/<widget>-<state>.png  (BeaconPreviewActivity fixtures,
cropped to the card, 360x222dp).
iOS renders live in      ios/<widget>-<state>.png  (HearthRenderTests ImageRenderer,
374x174pt, same sample data). Re-render with:
  Android: bash /tmp/render_all.sh  (emulator + BeaconPreviewActivity)
  iOS:     xcodebuild test -scheme HearthRender -destination 'platform=iOS Simulator,...'
Then:      python3 docs/parity-comparison/build.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# (state_id, caption) per widget — state_id matches both and/ and ios/ filenames.
WIDGETS = [
    ("Thermostat", "thermostat", "near parity", "b-parity", [
        ("auto", "Auto — violet rail, “Holding 64–69°”, dual ± setpoints (light circles, matched this release)"),
        ("heating", "Heating — heat mode actively heating, yellow, “Heating to 68°”"),
        ("cooling", "Cooling — cool mode, blue, “Cooling to 70°”"),
        ("heat_idle", "Heat, idle — at target, “Holding 64°”"),
        ("cool_idle", "Cool, idle — “Holding 69°”"),
        ("fan", "Fan only — slate rail, fan running, setpoints shown"),
        ("off", "Off — slate; Android prompts “Choose a mode to turn on”, iOS shows “Off”"),
        ("offline", "Offline — last-known reading greyed"),
        ("setup", "Set up — Android has a dedicated “Set up thermostat” card; iOS has none and falls back to Unavailable (gap)"),
    ]),
    ("Alarm", "alarm", "at parity", "b-parity", [
        ("disarmed", "Disarmed — blue rail, shield-off glyph, Arm home / Arm away"),
        ("armed_home", "Armed home — red rail, home glyph, Disarm"),
        ("armed_away", "Armed away — red rail, lock glyph, Disarm"),
        ("armed_night", "Armed night — red, home glyph"),
        ("armed_vacation", "Armed vacation — red, lock glyph"),
        ("armed_custom_bypass", "Armed (bypass) — custom-bypass label"),
        ("arming", "Arming… — exit-delay transitional state"),
        ("triggered", "Alarm triggered — distinct triggered-red tone + alert glyph"),
        ("offline", "Offline — last-known state greyed, “Can’t reach Home Assistant”"),
        ("setup", "Set up — not yet connected"),
    ]),
    ("Car", "car", "arrangement gaps", "b-gaps", [
        ("parked", "Parked — mint rail, Unplugged, sentry chip"),
        ("charging", "Charging — blue rail, “Full by …” ETA + charge bar"),
        ("complete", "Charged — charge complete at 80%"),
        ("sentry", "Sentry on — red sentry indicator"),
        ("low_battery", "Low battery — yellow rail, 18%"),
        ("open", "Trunk open — warn tone, door/trunk open"),
        ("tires", "Tire warning — “Check tires”, low psi highlighted"),
        ("unlocked_away", "Unlocked & away — red rail, lock warning"),
        ("offline", "Offline — last-known reading greyed"),
    ]),
    ("ChargePoint", "chargepoint", "near parity", "b-near", [
        ("available", "Available — plugs-free hero + per-level floors (P2–P6) + Join"),
        ("waiting", "In line — “#3”, floors at 0 free, Leave"),
        ("offer", "Offer — countdown-clock hero + “go to level”, Accept / Snooze"),
        ("held", "Held — plug-in countdown, Start / Snooze"),
        ("snoozed", "Snoozed — back-in-line countdown, floor levels, Rejoin / Leave"),
        ("charging", "Charging — kWh added + kW, Stop"),
        ("done", "Done / move your car — overstay countdown, Open ChargePoint"),
        ("signed_out", "Signed out — Sign in (ChargePoint’s own page)"),
        ("no_location", "No location — “Set up”, choose a location"),
        ("cant_join", "Session expired — silent re-auth, Sign in"),
    ]),
]

# Per-widget verdict bullets: (css-class, html). Kept from the audit; refined for this build.
VERDICTS = {
    "Thermostat": [
        ("ok", "Rail split, room temp + “In the room” + humidity + “Holding …°”, left sensor rows, and the Heat-to / Cool-to rows with value + steppers all match."),
        ("ok", "The ± steppers are light-grey circles on both platforms (Android’s were dark squares until this release)."),
        ("gap", "<b>Set up</b>: Android shows a dedicated “Set up thermostat” card; iOS has no climate-setup state and falls back to Unavailable."),
        ("min", "Freshness-stamp wording and the third action’s label (“Back to Schedule” vs “Resume”) are copy-level."),
    ],
    "Alarm": [
        ("ok", "Rail, shield glyph, big state word + “…at <time>”, “Home” title, the Front Door well <b>with the Unlock button</b>, and the arm buttons <b>with house/shield icons</b> — all match now (these were the previous gaps)."),
        ("ok", "The green “Locked” pill + lock icon renders on both."),
        ("min", "The unconfigured <code>setup</code> card differs in copy: Android “Connect your alarm”, iOS “Set up the alarm in Settings”."),
    ],
    "Car": [
        ("ok", "Rail, big battery %, range, car photo, charge line + bar, Sentry chip, Open Tesla, and the facts (lock / doors / cabin / outside / tires) are all present on both."),
        ("gap", "<b>Lock / Doors placement</b>: Android groups them as fact chips in the right panel; iOS lists them as left-hero rows."),
        ("min", "The Android emulator renders “Tesla unavailable” (no Tesla app installed on it); a real device shows “Open Tesla”, as iOS does."),
    ],
    "ChargePoint": [
        ("ok", "Fixed orange brand rail, Auto pill, account, and the state-specific keys (Accept / Snooze / Start / Leave / Rejoin) all match."),
        ("ok", "iOS now leads timed states with the <b>countdown clock</b> as the hero and shows “go to level” + per-level floor stats — the biggest previous gaps, now closed."),
        ("min", "iOS lists up to <b>4</b> floor levels; Android shows up to 5–6. The aggregate “N in use / N offline” line is richer on Android."),
    ],
}

CSS = """
  :root { color-scheme: dark; }
  body { margin:0; background:#0b0b0d; color:#e9e9ec; font:15px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif; }
  header { padding:28px 24px 8px; }
  h1 { font-size:24px; margin:0 0 4px; }
  .sub { color:#9a9aa2; font-size:14px; max-width:900px; }
  .legend { display:flex; gap:16px; flex-wrap:wrap; margin:12px 0 0; font-size:13px; color:#b9b9c0; }
  .legend b { font-weight:700; }
  section { padding:18px 24px; border-top:1px solid #1d1d22; }
  .whead { display:flex; align-items:center; gap:12px; margin:0 0 4px; position:sticky; top:0; background:#0b0b0d; padding:8px 0; z-index:2; }
  .whead h2 { font-size:20px; margin:0; }
  .count { color:#6f6f77; font-size:13px; }
  .badge { font-size:12px; font-weight:700; padding:3px 10px; border-radius:999px; }
  .b-parity { background:#15351f; color:#5fd48a; }
  .b-near   { background:#36330f; color:#e4cf5a; }
  .b-gaps   { background:#3a2a12; color:#f2a23c; }
  .verdict ul { margin:4px 0 16px; padding-left:0; list-style:none; }
  .verdict li { padding:3px 0 3px 24px; position:relative; font-size:13.5px; color:#cdcdd3; }
  .verdict li.ok::before  { content:"\\2713"; color:#5fd48a; position:absolute; left:0; font-weight:700; }
  .verdict li.gap::before { content:"\\2717"; color:#f2a23c; position:absolute; left:0; font-weight:700; }
  .verdict li.min::before { content:"~"; color:#e4cf5a; position:absolute; left:0; font-weight:700; }
  .states { display:flex; flex-direction:column; gap:20px; }
  .state { }
  .slabel { font-size:14px; margin:0 0 8px; color:#d7d7dd; }
  .slabel .sid { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:12.5px; color:#8fb7ff; background:#131a28; padding:1px 7px; border-radius:6px; margin-right:8px; }
  .cols { display:grid; grid-template-columns:1fr 1fr; gap:16px; align-items:start; }
  .pane { background:#141418; border:1px solid #23232a; border-radius:14px; padding:10px; }
  .plabel { font-size:11px; font-weight:700; color:#9a9aa2; margin:0 0 7px; letter-spacing:.04em; }
  .pane img { width:100%; height:auto; border-radius:10px; display:block; background:#000; }
  .pane.miss { display:flex; align-items:center; justify-content:center; min-height:120px; color:#6f6f77; font-size:13px; text-align:center; }
  footer { padding:22px 24px 48px; color:#7a7a82; font-size:13px; border-top:1px solid #1d1d22; }
  @media (max-width:760px){ .cols{ grid-template-columns:1fr; } }
"""

def img_pane(label: str, path: str) -> str:
    full = os.path.join(HERE, path)
    if os.path.exists(full):
        return f'<div class="pane"><div class="plabel">{label}</div><img loading="lazy" src="{path}" alt="{label} {path}"></div>'
    return f'<div class="pane miss"><div><div class="plabel">{label}</div>no render</div></div>'

def build() -> None:
    total = sum(len(s[4]) for s in WIDGETS)
    out = []
    out.append('<!doctype html><html lang="en"><head><meta charset="utf-8">')
    out.append('<meta name="viewport" content="width=device-width, initial-scale=1">')
    out.append('<title>Hearth — iOS ↔ Android widget parity (all states)</title>')
    out.append(f'<style>{CSS}</style></head><body>')
    out.append('<header><h1>Hearth — iOS ↔ Android widget parity</h1>')
    out.append(f'<div class="sub">Every core state of all four Beacon widgets, rendered on <b>both</b> platforms from the same sample data. '
               f'Left: <b>Android</b> (<code>BeaconPreviewActivity</code> fixtures, 360×222dp, cropped to the card). '
               f'Right: <b>iOS</b> (<code>HearthRenderTests</code> ImageRenderer, systemMedium 374×174pt). '
               f'The shapes differ by platform on purpose: Android 4×2 ≈ 1.62:1, iOS <code>systemMedium</code> ≈ 2.15:1 — a fixed family size, not a choice. '
               f'{total} states across 4 widgets.</div>')
    out.append('<div class="legend"><span><b>✓</b> at parity</span><span><b>~</b> minor (copy/styling)</span><span><b>✗</b> real gap</span></div></header>')

    for name, slug, badge_text, badge_cls, states in WIDGETS:
        out.append('<section>')
        out.append(f'<div class="whead"><h2>{name}</h2><span class="badge {badge_cls}">{badge_text}</span>'
                   f'<span class="count">{len(states)} states</span></div>')
        if name in VERDICTS:
            out.append('<div class="verdict"><ul>')
            for cls, html in VERDICTS[name]:
                out.append(f'<li class="{cls}">{html}</li>')
            out.append('</ul></div>')
        out.append('<div class="states">')
        for sid, caption in states:
            out.append('<div class="state">')
            out.append(f'<div class="slabel"><span class="sid">{sid}</span>{caption}</div>')
            out.append('<div class="cols">')
            out.append(img_pane("ANDROID", f"and/{slug}-{sid}.png"))
            out.append(img_pane("iOS", f"ios/{slug}-{sid}.png"))
            out.append('</div></div>')
        out.append('</div></section>')

    out.append('<footer>Generated by <code>docs/parity-comparison/build.py</code>. '
               'Non-layout platform walls remain on iOS: the system app-name label under Home-Screen widgets, and no continuous refresh-button animation — documented in <code>docs/PARITY-AUDIT.md</code>.</footer>')
    out.append('</body></html>')
    html = "\n".join(out)
    with open(os.path.join(HERE, "index.html"), "w") as f:
        f.write(html)
    # report missing renders
    missing = []
    for _, slug, _, _, states in WIDGETS:
        for sid, _ in states:
            for plat in ("and", "ios"):
                if not os.path.exists(os.path.join(HERE, plat, f"{slug}-{sid}.png")):
                    missing.append(f"{plat}/{slug}-{sid}.png")
    print(f"wrote index.html — {total} states")
    if missing:
        print(f"MISSING {len(missing)} renders:")
        for m in missing:
            print("  " + m)
    else:
        print("all renders present")

if __name__ == "__main__":
    build()
