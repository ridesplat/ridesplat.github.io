#!/bin/bash
#
# Rebuild the self-hosted webfonts: Noto Sans, plus Font Awesome and Academicons
# subsets.
#
# The page uses a handful of icons out of Font Awesome's ~2000 and Academicons'
# ~150. Shipping both in full cost two render-blocking third-party stylesheets
# (109 KB) plus 341 KB of webfonts, and a 1.2 MB fontawesome.all.min.js that
# duplicated the CSS beside it. Subsetting brings the icons to ~2 KB.
#
# Noto Sans replaces the fonts.googleapis.com stylesheet, which was a
# third-party round-trip before any text could paint.
#
# Run this after adding or removing an icon in the markup. It scans for the
# classes actually used, so no list needs maintaining by hand.
#
# Requires: fontTools + brotli  (pip3 install --user fonttools brotli)
#
# Usage: tools/build-webfonts.sh
#
set -euo pipefail

FA_VERSION="6.6.0"
FA_CDN="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/${FA_VERSION}"
AI_CDN="https://cdn.jsdelivr.net/gh/jpswalsh/academicons@1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PYBIN="$(python3 -c 'import site; print(site.USER_BASE + "/bin")')"
export PATH="$PYBIN:$PATH"

command -v pyftsubset >/dev/null || {
  echo "pyftsubset not found. Run: pip3 install --user fonttools brotli" >&2
  exit 1
}

mkdir -p "$ROOT/static/webfonts"

echo "==> Fetching Font Awesome ${FA_VERSION} and Academicons"
curl -sL "${FA_CDN}/css/all.min.css" -o "$WORK/fa.css"
curl -sL "${FA_CDN}/webfonts/fa-solid-900.woff2" -o "$WORK/fa-solid-900.woff2"
curl -sL "${FA_CDN}/webfonts/fa-brands-400.woff2" -o "$WORK/fa-brands-400.woff2"
curl -sL "${AI_CDN}/css/academicons.min.css" -o "$WORK/ai.css"
curl -sL "${AI_CDN}/fonts/academicons.ttf" -o "$WORK/academicons.ttf"

echo "==> Scanning for icon classes in use"
python3 - "$ROOT" "$WORK" <<'PY'
import json, os, re, sys
from fontTools.ttLib import TTFont

root, work = sys.argv[1], sys.argv[2]

# Classes appear in markup (class="..."), and in JS that swaps an icon (the
# BibTeX copy button toggles fa-copy to fa-check).
used = set()
for base, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if not d.startswith((".", "_", "node_modules"))]
    for name in files:
        if not name.endswith((".html", ".js")) or name.startswith("_"):
            continue
        # Vendored bundles reference every icon in the library.
        if "min.js" in name:
            continue
        text = open(os.path.join(base, name), encoding="utf-8",
                    errors="ignore").read()
        for pat in (r'class="([^"]*)"',
                    r'''class(?:Name)?\s*=\s*['"]([^'"]*)['"]''',
                    r'''class=\\?["']([^"'\\]*)''',
                    r'''classList\.(?:add|remove|toggle|contains)\(\s*['"]([^'"]+)['"]''',
                    r'''['"](fa-[a-z0-9-]+)['"]'''):
            for m in re.finditer(pat, text):
                used.update(m.group(1).split())

STYLE_CLASSES = {"fa-brands", "fa-solid", "fa-regular", "fa-spin", "fa-fw",
                 "fa-lg", "fa-2x", "fa-3x", "fa-pulse", "fa-border"}
fa_icons = {c for c in used
            if re.fullmatch(r"fa-[a-z0-9-]+", c) and c not in STYLE_CLASSES}
ai_icons = {c for c in used if re.fullmatch(r"ai-[a-z0-9-]+", c)}

# Resolve each class to its codepoint. Aliases share one rule, so match the
# exact selector token rather than a substring.
fa_css = open(os.path.join(work, "fa.css"), encoding="utf-8").read()
groups = []
for m in re.finditer(r'([^{}]*)\{content:"\\([0-9a-f]+)"\}', fa_css):
    sels = {s.strip().replace(":before", "") for s in m.group(1).split(",")}
    groups.append((sels, m.group(2)))

resolved, unknown = {}, []
for icon in sorted(fa_icons):
    for sels, cp in groups:
        if "." + icon in sels:
            resolved[icon] = cp
            break
    else:
        unknown.append(icon)

# Assign each icon to a family by checking the real font cmaps, not a hardcoded
# list of brand names.
cmaps = {}
for fam, path in (("solid", "fa-solid-900.woff2"), ("brand", "fa-brands-400.woff2")):
    font = TTFont(os.path.join(work, path))
    chars = set()
    for table in font["cmap"].tables:
        chars |= set(table.cmap.keys())
    cmaps[fam] = chars

split = {"solid": {}, "brand": {}, "academicons": {}}
for icon, cp in resolved.items():
    n = int(cp, 16)
    if n in cmaps["brand"]:
        split["brand"][icon] = cp
    elif n in cmaps["solid"]:
        split["solid"][icon] = cp
    else:
        unknown.append(icon)

ai_css = open(os.path.join(work, "ai.css"), encoding="utf-8").read()
for icon in sorted(ai_icons):
    m = re.search(r"\." + re.escape(icon) + r':before\s*\{\s*content:\s*"\\([0-9a-f]+)"',
                  ai_css)
    if m:
        split["academicons"][icon] = m.group(1)
    else:
        unknown.append(icon)

print(f"    {len(split['solid'])} solid, {len(split['brand'])} brand, "
      f"{len(split['academicons'])} academicons")
if unknown:
    print(f"    WARNING: could not resolve: {sorted(set(unknown))}")

json.dump(split, open(os.path.join(work, "split.json"), "w"))
for fam in split:
    codes = ",".join("U+" + cp for cp in sorted(split[fam].values()))
    open(os.path.join(work, f"{fam}.unicodes"), "w").write(codes)
PY

echo "==> Subsetting icon fonts"
for spec in "solid:fa-solid-900.woff2:fa-solid-900" \
            "brand:fa-brands-400.woff2:fa-brands-400" \
            "academicons:academicons.ttf:academicons"; do
  fam="${spec%%:*}"; rest="${spec#*:}"; src="${rest%%:*}"; out="${rest##*:}"
  pyftsubset "$WORK/$src" \
    --unicodes-file="$WORK/$fam.unicodes" \
    --flavor=woff2 --layout-features='' --no-hinting --desubroutinize \
    --output-file="$ROOT/static/webfonts/$out.woff2" 2>/dev/null
  before=$(stat -f%z "$WORK/$src")
  after=$(stat -f%z "$ROOT/static/webfonts/$out.woff2")
  python3 -c "print(f'    $out.woff2: {$before/1024:.1f} KB -> {$after/1024:.1f} KB')"
done

echo "==> Verifying every glyph survived with an outline"
python3 - "$ROOT" "$WORK" <<'PY'
import json, os, sys
from fontTools.ttLib import TTFont

root, work = sys.argv[1], sys.argv[2]
split = json.load(open(os.path.join(work, "split.json")))
files = {"solid": "fa-solid-900.woff2", "brand": "fa-brands-400.woff2",
         "academicons": "academicons.woff2"}

failed = False
for fam, wanted in split.items():
    if not wanted:
        continue
    font = TTFont(os.path.join(root, "static/webfonts", files[fam]))
    chars = {}
    for table in font["cmap"].tables:
        chars.update(table.cmap)
    glyf = font["glyf"] if "glyf" in font else None
    for icon, cp in wanted.items():
        n = int(cp, 16)
        if n not in chars:
            print(f"    MISSING {icon} U+{cp.upper()}")
            failed = True
        elif glyf is not None and glyf[chars[n]].numberOfContours == 0:
            print(f"    BLANK OUTLINE {icon} U+{cp.upper()}")
            failed = True

# The stylesheet is hand-maintained; make sure it agrees with the fonts.
import re
css = open(os.path.join(root, "static/css/icons.css"), encoding="utf-8").read()
declared = {m.group(1): m.group(2).lower() for m in re.finditer(
    r'\.((?:fa|ai)-[a-z0-9-]+)::before\s*\{\s*content:\s*"\\([0-9a-f]+)"', css)}
wanted_all = {k: v.lower() for fam in split.values() for k, v in fam.items()}

for icon, cp in wanted_all.items():
    if icon not in declared:
        print(f"    icons.css is MISSING a rule for {icon} (U+{cp.upper()})")
        failed = True
    elif declared[icon] != cp:
        print(f"    icons.css codepoint mismatch for {icon}: "
              f"{declared[icon]} vs {cp}")
        failed = True
for icon in set(declared) - set(wanted_all):
    print(f"    icons.css declares unused icon: {icon}")

if failed:
    sys.exit("Subset and stylesheet disagree; fix static/css/icons.css.")
print(f"    {len(declared)} glyph rules, consistent with the subset fonts")
PY

echo "==> Refreshing self-hosted Noto Sans"
# Google serves Noto Sans as a variable font, so one file per subset covers every
# weight the page uses (400-700) where static faces would need one file each.
# Only latin and latin-ext are kept; the pages are English.
python3 - "$ROOT" <<'PY'
import re, sys, urllib.request
from pathlib import Path

root = Path(sys.argv[1])
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")
CSS = ("https://fonts.googleapis.com/css2?"
       "family=Noto+Sans:wght@400..700&display=swap")

css = urllib.request.urlopen(
    urllib.request.Request(CSS, headers={"User-Agent": UA})).read().decode()

blocks = {}
for m in re.finditer(r"/\*\s*([a-z-]+)\s*\*/\s*@font-face\s*\{(.*?)\}", css, re.S):
    blocks[m.group(1)] = m.group(2)

# latin-ext is subset further: the full face carries 1399 glyphs for scripts
# these pages never use, and it is only fetched when an accented character
# appears anyway.
EXT_RANGES = ("U+0100-017F,U+0180-024F,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,"
              "U+02DD-02FF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,"
              "U+20AD-20C0,U+2113")

rules = []
for subset, name in (("latin", "noto-sans-latin"),
                     ("latin-ext", "noto-sans-latin-ext")):
    body = blocks.get(subset)
    if body is None:
        sys.exit(f"Google did not serve a {subset!r} subset; got {sorted(blocks)}")
    url = re.search(r"url\((https://[^)]+)\)", body).group(1)
    urange = re.search(r"unicode-range:\s*([^;]+);", body).group(1).strip()
    data = urllib.request.urlopen(
        urllib.request.Request(url, headers={"User-Agent": UA})).read()
    dest = root / "static/webfonts" / f"{name}.woff2"
    dest.write_bytes(data)

    if subset == "latin-ext":
        import subprocess, site
        tmp = dest.with_suffix(".full.woff2")
        dest.rename(tmp)
        subprocess.run([str(Path(site.USER_BASE) / "bin/pyftsubset"), str(tmp),
                        f"--unicodes={EXT_RANGES}", "--flavor=woff2",
                        "--layout-features=*", "--no-hinting",
                        f"--output-file={dest}"], check=True,
                       stderr=subprocess.DEVNULL)
        print(f"    {name}.woff2: {tmp.stat().st_size/1024:.1f} KB -> "
              f"{dest.stat().st_size/1024:.1f} KB")
        tmp.unlink()
    else:
        print(f"    {name}.woff2: {dest.stat().st_size/1024:.1f} KB")

    rules.append(f"""@font-face {{
  font-family: 'Noto Sans';
  font-style: normal;
  font-weight: 400 700;
  font-display: swap;
  src: url("../webfonts/{name}.woff2") format("woff2");
  unicode-range: {urange};
}}""")

header = """/* Self-hosted Noto Sans (SIL Open Font License 1.1).
 *
 * Replaces the render-blocking fonts.googleapis.com stylesheet: that was a
 * third-party round-trip before any text could paint, and it also pulled
 * Castoro, which no rule on these pages ever used.
 *
 * Variable faces, so one file per subset covers weights 400-700. Generated by
 * tools/build-webfonts.sh - do not edit by hand.
 */
"""
# Single-backslash escapes: this heredoc is quoted (<<'PY'), so the shell passes the
# body through verbatim and Python sees exactly what is written here. Doubling them
# emitted a literal backslash-n before each @font-face, which is an identifier escape
# in CSS and made the browser parse zero font faces — the self-hosted Noto Sans was
# preloaded and then never used.
(root / "static/css/noto-sans.css").write_text(
    header + "\n" + "\n\n".join(rules) + "\n")
print("    noto-sans.css written")
PY

echo
echo "Done. Run ./cache_bust.py --apply so the new files are picked up."
