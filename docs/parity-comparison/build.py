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
    ("Thermostat", "thermostat", "at parity", "b-parity", [
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
    ("Car", "car", "at parity", "b-parity", [
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
        ("ok", "Setpoint rows now match iOS: the label sits left with a compact <b>[−] value [+]</b> group on the right (was label-above / steppers-spread), the ± are light circles, and the value carries the mode colour."),
        ("ok", "Mode / Fan / Resume are flat iOS-style chips (ported from iOS — Android’s were raised surfaces)."),
        ("gap", "<b>Set up</b>: Android shows a dedicated “Set up thermostat” card; iOS has no climate-setup state and falls back to Unavailable."),
        ("min", "Android keeps an “Off · choose a mode” prompt in the body for the off state; iOS leaves it empty."),
    ],
    "Alarm": [
        ("ok", "Buttons ported from iOS: flat chips — a bright “Disarm” primary pill and dark Arm home / Arm away chips. Arm away now uses a <b>plain shield</b> (no inner lock), matching iOS."),
        ("ok", "The Front Door row is now a flat row (icon + name / status / since on their own lines) — iOS’s clean look, and the “since …” no longer clips on iOS."),
        ("min", "The unconfigured <code>setup</code> card differs in copy: Android “Set up the alarm in Settings”, iOS same."),
    ],
    "Car": [
        ("ok", "<b>Sentry moved onto the charge line</b> (right-aligned, next to Unplugged / charge ETA) on both, freeing the top row so the car photo is larger — matching iOS."),
        ("ok", "Rail, big battery %, range, charge bar, and the facts (lock / doors / cabin / outside / tires) line up on both."),
        ("min", "The Android emulator renders “Tesla unavailable” (no Tesla app installed on it); a real device shows “Open Tesla”, as iOS does."),
    ],
    "ChargePoint": [
        ("ok", "iOS now matches Android’s idle card: the big plug-count hero + “of 86 plugs / N in use / N offline”, the refresh + “Checked” stamp, all five floor levels (P2–P6), and <b>Join + Open</b> buttons — all ported from Android."),
        ("ok", "Timed states lead with the countdown-clock hero + “go to level”; the Accept / Snooze / Start / Leave / Rejoin keys match."),
        ("min", "Floor availability bars are green on Android, brand-orange on iOS."),
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

  /* --- annotation layer (served by server.py; feedback -> feedback.jsonl) --- */
  body { padding-right: 300px; }
  .pane { position: relative; }
  .render { cursor: crosshair; }
  .render:hover, .render.fbflash { outline: 2px solid #4f8cff; outline-offset: -2px; }
  .fbpin { position:absolute; transform:translate(-50%,-50%); width:20px; height:20px; border-radius:50%;
           background:#4f8cff; color:#fff; font-size:11px; font-weight:700; display:flex; align-items:center;
           justify-content:center; box-shadow:0 1px 4px rgba(0,0,0,.55); z-index:5; }
  body.fbhide .fbpin { display:none; }
  .fbcompose { position:absolute; transform:translate(-50%,8px); z-index:10; background:#1b1b22; border:1px solid #3a3a44;
               border-radius:10px; padding:8px; width:230px; box-shadow:0 6px 20px rgba(0,0,0,.6); cursor:default; }
  .fbcompose .fbwhere { font:11px/1.3 ui-monospace,monospace; color:#8fb7ff; margin-bottom:5px; }
  .fbcompose textarea { width:100%; box-sizing:border-box; background:#0e0e12; color:#eee; border:1px solid #333;
                        border-radius:6px; font-size:13px; padding:5px; resize:vertical; }
  .fbcompose .fbbtns { display:flex; gap:6px; margin-top:6px; }
  .fbcompose button { font-size:12px; padding:4px 10px; border-radius:6px; border:0; cursor:pointer; }
  .fbcompose .fbsave { background:#4f8cff; color:#fff; }
  .fbcompose .fbcancel { background:#2a2a32; color:#ccc; }
  #fbpanel { position:fixed; right:0; top:0; width:300px; height:100vh; overflow:auto; background:#141418f2;
             border-left:1px solid #2a2a33; padding:12px; z-index:50; font-size:13px; box-sizing:border-box; }
  #fbpanel .fbhead { display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
  #fbpanel .fbhead b { font-size:15px; }
  #fbcount { background:#4f8cff; color:#fff; border-radius:10px; padding:0 7px; font-size:11px; }
  #fbpanel .fbhead button { font-size:11px; background:#2a2a32; color:#ccc; border:0; border-radius:6px; padding:3px 8px; cursor:pointer; }
  #fbclear { margin-left:auto; }
  .fbhint { color:#8a8a92; font-size:11px; margin:6px 0 10px; }
  .fbrow { display:flex; align-items:flex-start; gap:6px; padding:6px 0; border-top:1px solid #23232a; }
  .fbnum { background:#4f8cff; color:#fff; border-radius:50%; width:18px; height:18px; min-width:18px; display:flex;
           align-items:center; justify-content:center; font-size:11px; font-weight:700; }
  .fbtgt { font:11px/1.4 ui-monospace,monospace; color:#8fb7ff; }
  .fbnote { flex:1; color:#e0e0e6; }
  .fbdel { background:none; border:0; color:#888; cursor:pointer; font-size:15px; line-height:1; }
"""

PLAT = {"and": ("ANDROID", "android"), "ios": ("iOS", "ios")}

def img_pane(plat_dir: str, slug: str, sid: str) -> str:
    label, key = PLAT[plat_dir]
    path = f"{plat_dir}/{slug}-{sid}.png"
    full = os.path.join(HERE, path)
    data = f'data-widget="{slug}" data-state="{sid}" data-platform="{key}"'
    if os.path.exists(full):
        return f'<div class="pane render" {data}><div class="plabel">{label}</div><img loading="lazy" src="{path}" alt="{key} {sid}"></div>'
    return f'<div class="pane miss render" {data}><div><div class="plabel">{label}</div>no render</div></div>'

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
            out.append(img_pane("and", slug, sid))
            out.append(img_pane("ios", slug, sid))
            out.append('</div></div>')
        out.append('</div></section>')

    out.append('<footer>Generated by <code>docs/parity-comparison/build.py</code>. '
               'Non-layout platform walls remain on iOS: the system app-name label under Home-Screen widgets, and no continuous refresh-button animation — documented in <code>docs/PARITY-AUDIT.md</code>.</footer>')
    out.append('<script src="annotate.js"></script>')
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
