#!/usr/bin/env python3
"""Post-process the Hearth render walker output (docs/RENDER-HARNESS.md).

Reads the PNGs + catalog.tsv the XCUITest walker wrote into the runner's
Documents/renders directory (scripts/render/run_all.sh copies them out), then:
  - copies full-screen shots into <out>/screens/
  - crops the magenta-keyed widget shots (w-<parity id>-<normal|larger>.png, flush at
    top-left) into <out>/widgets/<parity id>-<normal|larger>.png
  - flags frames that look unrendered (black screen, or a widget shot without its
    magenta key), so the batch can be run again
  - writes <out>/manifest.md and <out>/index.html

Usage:
  python3 -I scripts/render/build_gallery.py --src <renders-dir> --out <output-dir> [--scale 3]

Needs Pillow (python3 -m pip install Pillow).
"""
import argparse, os, re, shutil, html, sys
from collections import OrderedDict

try:
    from PIL import Image, ImageStat
except ImportError:
    sys.exit("build_gallery.py needs Pillow: python3 -m pip install Pillow")

DEFAULT_SCALE = 3          # @3x iPhone simulators
BLACK_MEAN = 8             # mean luminance below this: the renderer drew nothing
KEY_MARGIN_PX = 20         # where, right of the card, the magenta key is sampled
WIDGET_NAME = re.compile(r"w-(.+)-(normal|larger)$")
DEFAULT_CROP_PT = (364, 170)


def parse_catalog(src):
    rows = OrderedDict()
    path = os.path.join(src, "catalog.tsv")
    if not os.path.exists(path):
        return rows
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            name, group, reached, shows, source = parts[:5]
            rows[name] = dict(group=group, reached=reached, shows=shows, source=source)
    return rows


def is_black(im):
    return ImageStat.Stat(im.convert("L")).mean[0] < BLACK_MEAN


def has_magenta_key(im, w_px, h_px):
    """The flush card leaves the magenta key showing just right of it."""
    x, y = min(im.width - 1, w_px + KEY_MARGIN_PX), min(im.height - 1, h_px // 2)
    r, g, b = im.getpixel((x, y))
    return r > 230 and g < 60 and b > 230


def crop_widget(im, dst_png, w_px, h_px):
    im.crop((0, 0, min(w_px, im.width), min(h_px, im.height))).save(dst_png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--scale", type=int, default=DEFAULT_SCALE, help="simulator pixels per point")
    args = ap.parse_args()
    src, out = args.src, args.out
    if not os.path.isdir(src):
        sys.exit(f"build_gallery.py: no renders directory at {src}")
    screens = os.path.join(out, "screens")
    widgets = os.path.join(out, "widgets")
    os.makedirs(screens, exist_ok=True)
    os.makedirs(widgets, exist_ok=True)

    cat = parse_catalog(src)
    # Catalog may include GAP rows that have no PNG.
    png_names = sorted(f[:-4] for f in os.listdir(src) if f.endswith(".png"))

    screen_entries = []   # (name, meta)
    widget_entries = []   # (kind, parity id, variant, outfile, meta)
    suspects = []         # (name, why)

    for name in png_names:
        meta = cat.get(name, dict(group="?", reached="", shows="", source=""))
        srcp = os.path.join(src, name + ".png")
        try:
            im = Image.open(srcp).convert("RGB")
        except OSError as error:
            suspects.append((name, f"unreadable image: {error}"))
            continue
        if is_black(im):
            suspects.append((name, "black frame"))
        m = WIDGET_NAME.match(name)
        if m:
            parity_id, variant = m.groups()
            w_pt, h_pt = DEFAULT_CROP_PT
            mcrop = re.search(r"crop=(\d+)x(\d+)", meta.get("source", ""))
            if mcrop:
                w_pt, h_pt = int(mcrop.group(1)), int(mcrop.group(2))
            w_px, h_px = w_pt * args.scale, h_pt * args.scale
            if not has_magenta_key(im, w_px, h_px):
                suspects.append((name, "no magenta key beside the card (not rendered, or the wrong --scale)"))
            outfile = f"{parity_id}-{variant}.png"
            crop_widget(im, os.path.join(widgets, outfile), w_px, h_px)
            widget_entries.append((parity_id.split("-")[0], parity_id, variant, outfile, meta))
        else:
            shutil.copyfile(srcp, os.path.join(screens, name + ".png"))
            screen_entries.append((name, meta))

    gaps = [(n, m) for n, m in cat.items() if m.get("reached") == "GAP"]
    write_manifest(out, screen_entries, widget_entries, gaps, suspects)
    write_index(out, screen_entries, widget_entries)
    print(f"screens={len(screen_entries)} widgets={len(widget_entries)} gaps={len(gaps)} suspects={len(suspects)}")
    for name, why in suspects:
        print(f"  SUSPECT {name}: {why}")


def write_manifest(out, screens, widgets, gaps, suspects):
    bygroup = OrderedDict()
    for name, meta in sorted(screens, key=lambda x: x[0]):
        bygroup.setdefault(meta["group"], []).append((name, meta))
    lines = ["# Hearth iOS render — manifest", "",
             "Every image is a real screen or sheet of the DEBUG app, drawn over the `-demoHouse` demo",
             "house (or a labelled fixture). Light and dark are the app's own tokens, forced with",
             "`-renderColorScheme`. How this was made: docs/RENDER-HARNESS.md.", "",
             "## Screens", ""]
    for g, items in bygroup.items():
        lines.append(f"### {g}")
        lines.append("")
        lines.append("| image | reached | shows | data |")
        lines.append("|---|---|---|---|")
        for name, meta in items:
            lines.append(f"| `screens/{name}.png` | {meta['reached']} | {meta['shows']} | {meta['source']} |")
        lines.append("")
    lines += ["## Widgets", "",
              "Cropped from the parity catalog (`-parityState <id> -parityFlush`): "
              "`<parity id>-normal.png` is 364×170 in the default Card style, "
              "`<parity id>-larger.png` is 329×155 with Larger text.", "",
              "| image | reached | data |", "|---|---|---|"]
    for kind, parity_id, variant, outfile, meta in sorted(widgets, key=lambda x: (x[0], x[1], x[2])):
        lines.append(f"| `widgets/{outfile}` | {meta['reached']} | {meta['source']} |")
    lines.append("")
    lines += ["## Gaps", "", "Screens the walker could not reach.", ""]
    lines += [f"- `{n}` — {m['shows']}" for n, m in gaps] or ["- None."]
    lines += ["", "## Suspect frames", "",
              "Images that look unrendered. Run their batch again (the simulator's renderer goes black "
              "after too many launches).", ""]
    lines += [f"- `{n}` — {why}" for n, why in suspects] or ["- None."]
    lines.append("")
    with open(os.path.join(out, "manifest.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def pair_light_dark(entries):
    """Group screen entries by base name (strip trailing -light/-dark/-xxxl)."""
    bases = OrderedDict()
    for name, meta in sorted(entries, key=lambda x: x[0]):
        m = re.match(r"(.+)-(light|dark|xxxl)$", name)
        base = m.group(1) if m else name
        appr = m.group(2) if m else ""
        bases.setdefault(base, {"meta": meta})[appr] = name
    return bases


def write_index(out, screens, widgets):
    css = """
body{font-family:-apple-system,Helvetica,Arial,sans-serif;margin:0;background:#f5f3ef;color:#1c1b19}
header{padding:20px 24px;background:#111110;color:#f2efea}
h1{margin:0;font-size:20px} h2{margin:28px 24px 8px;font-size:17px}
h3{margin:18px 24px 4px;font-size:14px;color:#555}
.row{display:flex;flex-wrap:wrap;gap:16px;padding:6px 24px 14px}
.cell{width:230px} .cell img{width:230px;border:1px solid #ddd;border-radius:14px;background:#fff;display:block}
.cap{font-size:11px;color:#555;margin:4px 0 0;word-break:break-all}
.pair{display:flex;gap:12px;padding:8px 24px 16px;border-bottom:1px solid #e7e3dd}
.pair .meta{flex:1;min-width:200px;font-size:12px;color:#444}
.pair .meta b{color:#111}
.wgrid{display:flex;flex-wrap:wrap;gap:14px;padding:6px 24px 16px}
.wcell{background:repeating-conic-gradient(#eee 0% 25%,#fafafa 0% 50%) 50%/16px 16px;border-radius:12px;padding:8px}
.wcell img{display:block;max-width:300px;border-radius:8px}
.wcap{font-size:11px;color:#555;margin-top:4px}
"""
    parts = ["<!doctype html><html><head><meta charset='utf-8'>",
             "<title>Hearth iOS render</title><style>", css, "</style></head><body>",
             "<header><h1>Hearth iOS — render of every screen</h1>",
             "<div>DEBUG build over the demo house. Light / dark side by side; widgets at 364×170 "
             "and, with Larger text, 329×155.</div></header>"]

    # screens grouped
    bygroup = OrderedDict()
    for name, meta in sorted(screens, key=lambda x: x[0]):
        bygroup.setdefault(meta["group"], []).append((name, meta))
    for g, items in bygroup.items():
        parts.append(f"<h2>{html.escape(g)}</h2>")
        for base, d in pair_light_dark(items).items():
            meta = d["meta"]
            parts.append("<div class='pair'>")
            for appr in ("light", "dark", "xxxl"):
                if appr in d:
                    fn = f"screens/{d[appr]}.png"
                    parts.append(f"<div class='cell'><img loading='lazy' src='{fn}'>"
                                 f"<div class='cap'>{html.escape(d[appr])}</div></div>")
            parts.append(f"<div class='meta'><b>{html.escape(meta['shows'])}</b><br>"
                         f"reached: {html.escape(meta['reached'])}<br>"
                         f"data: {html.escape(meta['source'])}</div>")
            parts.append("</div>")

    # widgets grid by kind
    parts.append("<h2>Widgets</h2>")
    bykind = OrderedDict()
    for kind, parity_id, variant, outfile, meta in sorted(widgets, key=lambda x: (x[0], x[1], x[2])):
        bykind.setdefault(kind, []).append((parity_id, variant, outfile))
    for kind, items in bykind.items():
        parts.append(f"<h3>{html.escape(kind)}</h3><div class='wgrid'>")
        for parity_id, variant, outfile in items:
            parts.append(f"<div class='wcell'><img loading='lazy' src='widgets/{html.escape(outfile)}'>"
                         f"<div class='wcap'>{html.escape(f'{parity_id} · {variant}')}</div></div>")
        parts.append("</div>")

    parts.append("</body></html>")
    with open(os.path.join(out, "index.html"), "w", encoding="utf-8") as f:
        f.write("".join(parts))


if __name__ == "__main__":
    main()
