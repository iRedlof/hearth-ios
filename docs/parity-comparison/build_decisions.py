#!/usr/bin/env python3
"""Generate decisions.html — the iOS↔Android discrepancy decision page.

Each remaining discrepancy is shown with the two renders side by side and radio options
(→ match iOS / → match Android / keep both). Choices POST to the server (/decision ->
decisions.json), which the agent reads to implement them. Regenerate: python3 build_decisions.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# (id, title, state-for-renders, description, [(value, label)])
DISCREPANCIES = [
    ("cp-labels", "ChargePoint — button labels", "chargepoint-available",
     "Android uses long labels (“Stop charging”, “Open ChargePoint”, “Join waitlist”, “Start charge”, “Rejoin now”); iOS uses short ones (“Stop”, “Open”, “Join”, “Start”, “Rejoin”).",
     [("ios", "Short labels (iOS)"), ("android", "Long labels (Android)"), ("keep", "Keep each as-is")]),
    ("cp-charging-open", "ChargePoint — charging: second “Open” button", "chargepoint-charging",
     "Android shows “Stop charging” + “Open”; iOS shows only “Stop”.",
     [("ios", "Stop only (iOS)"), ("android", "Stop + Open (Android)")]),
    ("cp-charging-stats", "ChargePoint — charging: session stats", "chargepoint-charging",
     "Android shows Est. distance / Time elapsed / Charger in the right panel; iOS shows nothing there.",
     [("ios", "Hide them (iOS)"), ("android", "Show the stats (Android)")]),
    ("cp-held-leave", "ChargePoint — held: third “Leave” button", "chargepoint-held",
     "Android has Start + Snooze + Leave; iOS has Start + Snooze.",
     [("ios", "Start + Snooze (iOS)"), ("android", "+ Leave (Android)")]),
    ("cp-timed-detail", "ChargePoint — timed-state detail lines", "chargepoint-offer",
     "In offer/held/snoozed/done, Android adds extra lines (“to accept”, “1 snooze left”, “Back in line at…”, the state word as its own line); iOS is minimal (clock + one word + “respond by…”).",
     [("ios", "Minimal (iOS)"), ("android", "Verbose (Android)"), ("keep", "Keep each")]),
    ("th-off", "Thermostat — Off-state message", "thermostat-off",
     "Android shows an “Off / Choose a mode to turn on” message box; iOS shows nothing in the middle.",
     [("ios", "No message (iOS)"), ("android", "Show message (Android)")]),
    ("th-setup", "Thermostat — Setup state", "thermostat-setup",
     "Android shows a proper “Set up thermostat / Connect” card; iOS shows a greyed “Mode” chip + “Unavailable” (looks unfinished).",
     [("android", "Proper setup card (Android) → fix iOS"), ("ios", "Keep iOS minimal")]),
    ("al-armhome-icon", "Alarm — Arm home button icon", "alarm-disarmed",
     "On the Arm-home button, Android uses a house-in-shield; iOS uses a plain house. (Look at the buttons bottom-right.)",
     [("ios", "Plain house (iOS)"), ("android", "House-in-shield (Android)")]),
    ("al-glyph-style", "Alarm — rail glyph style (disarmed / away / alert)", "alarm-armed_away",
     "Same concepts on both, but Android draws custom vectors while iOS uses SF Symbols, so the exact weight/shape differs. Pixel-match them?",
     [("ios", "Match iOS SF Symbols"), ("android", "Match Android vectors"), ("keep", "Close enough — keep")]),
]

CAR_NOTE = ("Car is fully converged. The only visible difference is “Tesla unavailable” — that's just because "
            "the emulator has no Tesla app installed; a real device shows “Open Tesla”, same as iOS. No change needed.")

CSS = """
  :root{color-scheme:dark}
  body{margin:0;background:#0b0b0d;color:#e9e9ec;font:15px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif;padding-bottom:60px}
  header{padding:26px 24px 10px}
  h1{font-size:23px;margin:0 0 4px}
  .sub{color:#9a9aa2;font-size:14px;max-width:900px}
  .prog{position:sticky;top:0;background:#0b0b0dF2;padding:10px 24px;border-bottom:1px solid #1d1d22;z-index:10;font-size:14px}
  .prog b{color:#5fd48a}
  .note{margin:10px 24px;padding:10px 14px;background:#141418;border:1px solid #23232a;border-radius:10px;color:#b9b9c0;font-size:13px}
  .card{margin:16px 24px;padding:16px;background:#121216;border:1px solid #23232a;border-radius:14px}
  .card.decided{border-color:#2d5a3a}
  .ctitle{font-size:16px;font-weight:700;margin:0 0 4px}
  .cnum{display:inline-flex;width:22px;height:22px;border-radius:50%;background:#2a2a32;color:#cfcfd6;align-items:center;justify-content:center;font-size:12px;font-weight:700;margin-right:8px}
  .cdesc{color:#b9b9c0;font-size:13.5px;margin:0 0 12px}
  .imgs{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:12px}
  .pane{background:#141418;border:1px solid #23232a;border-radius:12px;padding:8px}
  .plabel{font-size:11px;font-weight:700;color:#9a9aa2;letter-spacing:.04em;margin:0 0 6px}
  .pane img{width:100%;height:auto;border-radius:9px;display:block;background:#000}
  .opts{display:flex;gap:10px;flex-wrap:wrap}
  .opt{display:flex;align-items:center;gap:7px;padding:8px 14px;border:1px solid #33333c;border-radius:10px;cursor:pointer;font-size:14px;background:#181820}
  .opt:hover{border-color:#4f8cff}
  .opt.sel{border-color:#5fd48a;background:#15351f;color:#c7f5d6}
  .opt input{accent-color:#5fd48a}
  footer{padding:20px 24px;color:#7a7a82;font-size:13px}
  @media(max-width:760px){.imgs{grid-template-columns:1fr}}
"""

JS = """
let decided = {};
const TOTAL = %d;
function refresh(){
  const n = Object.keys(decided).length;
  document.getElementById('count').textContent = n;
  document.querySelectorAll('.card').forEach(c=>{
    const id=c.dataset.id;
    c.classList.toggle('decided', !!decided[id]);
    c.querySelectorAll('.opt').forEach(o=>{
      const on = decided[id]===o.dataset.choice;
      o.classList.toggle('sel', on);
      o.querySelector('input').checked = on;
    });
  });
}
async function load(){
  try{ decided = await (await fetch('/decisions')).json(); }catch(e){}
  // normalise {id:{choice}} -> {id:choice}
  const m={}; for(const k in decided){ m[k]=decided[k].choice; } decided=m;
  refresh();
}
function choose(id, choice, title){
  decided[id]=choice; refresh();
  fetch('/decision',{method:'POST',body:JSON.stringify({id,choice,title})});
}
load();
"""

def pane(label, src):
    full = os.path.join(HERE, src)
    inner = f'<img loading="lazy" src="{src}">' if os.path.exists(full) else 'no render'
    return f'<div class="pane"><div class="plabel">{label}</div>{inner}</div>'

def build():
    out = ['<!doctype html><html lang="en"><head><meta charset="utf-8">',
           '<meta name="viewport" content="width=device-width, initial-scale=1">',
           '<title>Hearth — parity decisions</title>', f'<style>{CSS}</style></head><body>']
    out.append('<header><h1>Hearth — iOS ↔ Android parity decisions</h1>')
    out.append('<div class="sub">Every remaining discrepancy, side by side. Pick the direction for each — '
               '→ iOS, → Android, or keep both. Your choices save to the server and I implement them. '
               'The full gallery is on <a href="index.html" style="color:#8fb7ff">index.html</a>.</div></header>')
    out.append(f'<div class="prog"><b id="count">0</b> / {len(DISCREPANCIES)} decided</div>')
    out.append(f'<div class="note">🚗 {CAR_NOTE}</div>')
    for i, (did, title, state, desc, opts) in enumerate(DISCREPANCIES, 1):
        widget = state.split("-")[0]
        out.append(f'<div class="card" data-id="{did}">')
        out.append(f'<div class="ctitle"><span class="cnum">{i}</span>{title}</div>')
        out.append(f'<div class="cdesc">{desc}<br><span style="color:#6f6f77">reference state: <code>{state}</code></span></div>')
        out.append('<div class="imgs">')
        out.append(pane("ANDROID", f"and/{state}.png"))
        out.append(pane("iOS", f"ios/{state}.png"))
        out.append('</div><div class="opts">')
        for value, label in opts:
            out.append(f'<label class="opt" data-choice="{value}">'
                       f'<input type="radio" name="{did}" onchange="choose(\'{did}\',\'{value}\',\'{title.replace(chr(39),chr(8217))}\')">{label}</label>')
        out.append('</div></div>')
    out.append('<footer>When you\'ve picked the ones you care about, tell me "go" and I\'ll implement every decision, re-render, and release.</footer>')
    out.append(f'<script>{JS % len(DISCREPANCIES)}</script></body></html>')
    with open(os.path.join(HERE, "decisions.html"), "w") as f:
        f.write("\n".join(out))
    print(f"wrote decisions.html — {len(DISCREPANCIES)} discrepancies")

if __name__ == "__main__":
    build()
