#!/usr/bin/env python3
"""
Cache Busting Script for the project pages

Automatically updates version query strings on static assets to force browser cache refresh.

Rewrites three kinds of reference so one version covers the whole site:
  * HTML - href/src/srcset attributes
  * CSS  - url() inside our own stylesheets (e.g. the self-hosted webfonts)
  * JS   - versioned page URLs built as string literals

Covering CSS and JS matters. A <link rel="preload"> in the HTML and the url()
in a stylesheet must agree byte-for-byte, query string included, or the browser
treats them as different resources and the preload becomes a wasted request.
While this script rewrote HTML only, those two silently drifted apart.

Usage:
    python cache_bust.py              # Dry run (show what would change)
    python cache_bust.py --apply      # Apply changes to files
"""

import argparse
import re
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Extensions worth versioning. woff2 is included because we self-host the Noto
# Sans and icon-font subsets: a preload in the HTML and the url() in our own
# stylesheet must carry the same version or they are two different URLs and the
# preload is wasted. Vendored bundles are left untouched.
ASSET_EXTS = [
    "css", "js", "pdf", "bib",
    "ico", "png", "svg", "avif", "webp", "jpg", "jpeg", "gif",
    "mp4", "webm", "woff2",
]
_EXT_ALT = "|".join(ASSET_EXTS)

# href="/path/asset.ext", optionally already versioned. Requiring the closing
# quote right after the extension (or an existing ?v=) leaves URLs that carry
# real query parameters alone, e.g. pdfviewer.html?file=...
# Beyond href/src: poster is the still frame a <video> paints before playback,
# and data-src is the deferred source slideshow.js promotes to src when a slide
# first becomes visible. Both are real asset references and need versioning too.
HTML_ATTR_RE = re.compile(
    r'(?P<attr>data-src|data-poster|href|src|poster)="(?P<url>[^"]+?\.(?:' + _EXT_ALT + r'))'
    r'(?:\?v=[^"]*)?"'
)

# srcset holds a comma-separated candidate list, each entry optionally followed
# by a width or density descriptor.
HTML_SRCSET_RE = re.compile(r'srcset="(?P<value>[^"]+)"')

# url("../webfonts/noto-sans-latin.woff2") in our own CSS. Quotes are optional
# per the spec.
CSS_URL_RE = re.compile(
    r'url\((?P<q>["\']?)(?P<url>[^"\')]+?\.(?:' + _EXT_ALT + r'))'
    r'(?:\?v=[^"\')]*)?(?P=q)\)'
)

# A versioned page URL built in JS, e.g. '/pdfviewer.html?v=2026-07-30&file='
JS_URL_RE = re.compile(
    r"(?P<q>['\"])(?P<url>/[^'\"?]+?\.html)\?v=(?P<version>[^'\"&]*)"
)

# These sites version assets as dot-separated dates (2026.03.08.1); the personal
# site uses hyphens (2026-07-31-22). Accept either, or `extract_current_version`
# returns None on every run here — which silently disabled the same-day increment,
# made the drift warning unreachable, and converted the whole site to the other
# scheme on the first --apply.
VERSION_RE = re.compile(
    r"\?v=(\d{4}[.-]\d{2}[.-]\d{2}(?:[.-]\d+)?)")

# Which separator this site already uses, so a rewrite stays in its own convention.
SEP_RE = re.compile(r"\?v=\d{4}([.-])")

# Vendored third-party bundles, kept byte-for-byte as shipped. Unlike the
# personal site these sit in the same static/css directory as our own files, so
# they are identified by name.
VENDOR_CSS_NAMES = {"bulma.min.css", "bulma-carousel.min.css"}


def is_external(url: str) -> bool:
    """External and inline URLs own their query strings; never touch them."""
    return url.startswith(("http://", "https://", "//", "data:", "mailto:", "#"))


class CacheBuster:
    def __init__(self, root_dir: str = "."):
        self.root_dir = Path(root_dir)
        # Separator is detected from the tree in run(); default to hyphens.
        self.sep = "-"
        self.today = datetime.now().strftime("%Y-%m-%d")
        self.changes: Dict[str, List[Tuple[str, str]]] = {}

    # --------------------------------------------------------------- discovery

    def _walk(self, pattern: str) -> List[Path]:
        files = []
        for f in self.root_dir.glob(pattern):
            parts = f.relative_to(self.root_dir).parts
            # Skip hidden paths, and underscore-prefixed ones (Jekyll ignores those).
            if any(p.startswith((".", "_")) for p in parts):
                continue
            files.append(f)
        return sorted(files)

    def find_html_files(self) -> List[Path]:
        return self._walk("**/*.html")

    def find_css_files(self) -> List[Path]:
        """Our own stylesheets only — skip the vendored bundles."""
        return [
            f for f in self._walk("static/css/**/*.css")
            if f.name not in VENDOR_CSS_NAMES
        ]

    def find_js_files(self) -> List[Path]:
        return self._walk("static/js/**/*.js")

    # ----------------------------------------------------------------- version

    def extract_current_version(self, content: str) -> Optional[str]:
        """Return the most common version string in the given content."""
        versions = VERSION_RE.findall(content)
        if not versions:
            return None
        return Counter(versions).most_common(1)[0][0]

    def today_stamp(self) -> str:
        """Today's date in whichever separator this site already uses."""
        return self.today.replace("-", self.sep)

    def calculate_new_version(self, current_version: Optional[str]) -> str:
        """Today's date, with an incrementing suffix for repeat runs the same day.

        The suffix is parsed off the end of the date rather than by splitting on
        the separator, which a bare date always contains: rsplit('-') on
        "2026-03-31" yields a "31" that increments into "2026-03-31-32".
        """
        stamp = self.today_stamp()
        if not current_version or not current_version.startswith(stamp):
            return stamp

        suffix = current_version[len(stamp):].lstrip(".-")
        if not suffix:
            return f"{stamp}{self.sep}1"
        try:
            return f"{stamp}{self.sep}{int(suffix) + 1}"
        except ValueError:
            return f"{stamp}{self.sep}1"

    # --------------------------------------------------------------- rewriting

    def _rewrite(self, content: str, version: str, kind: str,
                 record: List[Tuple[str, str]]) -> str:
        """Apply the rules for one file kind, recording each change."""

        def note(old: str, new: str) -> str:
            if old != new:
                record.append((old, new))
            return new

        def sub_attr(m: "re.Match") -> str:
            url = m.group("url")
            if is_external(url):
                return m.group(0)
            return note(m.group(0), f'{m.group("attr")}="{url}?v={version}"')

        def sub_srcset(m: "re.Match") -> str:
            out = []
            for candidate in m.group("value").split(","):
                candidate = candidate.strip()
                if not candidate:
                    continue
                url, *descriptor = candidate.split()
                base = url.split("?", 1)[0]
                if not is_external(url) and re.search(
                        r"\.(?:" + _EXT_ALT + r")$", base, re.I):
                    url = f"{base}?v={version}"
                out.append(" ".join([url, *descriptor]))
            return note(m.group(0), f'srcset="{", ".join(out)}"')

        def sub_css_url(m: "re.Match") -> str:
            url = m.group("url")
            if is_external(url):
                return m.group(0)
            quote = m.group("q")
            return note(m.group(0), f"url({quote}{url}?v={version}{quote})")

        def sub_js_url(m: "re.Match") -> str:
            quote = m.group("q")
            return note(m.group(0), f'{quote}{m.group("url")}?v={version}')

        if kind == "html":
            content = HTML_ATTR_RE.sub(sub_attr, content)
            content = HTML_SRCSET_RE.sub(sub_srcset, content)
            # Inline background-image declarations are used as lightweight
            # comparison posters before the canvas paints its first video frame.
            content = CSS_URL_RE.sub(sub_css_url, content)
        elif kind == "css":
            content = CSS_URL_RE.sub(sub_css_url, content)
        elif kind == "js":
            content = JS_URL_RE.sub(sub_js_url, content)

        return content

    def process_file(self, file_path: Path, version: str,
                     kind: str) -> Optional[str]:
        original = file_path.read_text(encoding="utf-8")
        record: List[Tuple[str, str]] = []
        updated = self._rewrite(original, version, kind, record)

        if record:
            self.changes[str(file_path)] = record

        return updated if updated != original else None

    # --------------------------------------------------------------------- run

    def run(self, dry_run: bool = True) -> None:
        targets = (
            [(f, "html") for f in self.find_html_files()]
            + [(f, "css") for f in self.find_css_files()]
            + [(f, "js") for f in self.find_js_files()]
        )

        if not targets:
            print("❌ No files found!")
            return

        counts = Counter(kind for _, kind in targets)
        print(f"🔍 Found {counts['html']} HTML, {counts['css']} CSS, "
              f"{counts['js']} JS files")
        print(f"📅 Today's date: {self.today}\n")
        # Printed after the separator is detected, below.

        all_content = "".join(f.read_text(encoding="utf-8") for f, _ in targets)
        # Adopt the separator already in use so a rewrite does not switch schemes.
        sep_match = SEP_RE.search(all_content)
        if sep_match:
            self.sep = sep_match.group(1)
        current_version = self.extract_current_version(all_content)
        new_version = self.calculate_new_version(current_version)

        print(f"📌 Current version: {current_version or 'None'}")
        # More than one version in the tree means something drifted out of sync.
        stale = set(VERSION_RE.findall(all_content)) - {current_version}
        if stale:
            print(f"⚠️  Also found: {', '.join(sorted(stale))}")
        print(f"🆕 New version: {new_version}\n")

        updates = {}
        for file_path, kind in targets:
            updated = self.process_file(file_path, new_version, kind)
            if updated:
                updates[file_path] = updated

        if not self.changes:
            print("✅ All files are already up to date!")
            return

        print(f"📝 Files to update: {len(self.changes)}\n")
        for file_path, changes in self.changes.items():
            rel_path = Path(file_path).relative_to(self.root_dir)
            print(f"📄 {rel_path}")
            print(f"   {len(changes)} change(s)")
            for old, new in changes[:3]:
                print(f"   - {old}")
                print(f"   + {new}")
            if len(changes) > 3:
                print(f"   ... and {len(changes) - 3} more")
            print()

        if not dry_run:
            for file_path, updated in updates.items():
                file_path.write_text(updated, encoding="utf-8")
            print(f"✅ Successfully updated {len(updates)} files!")
            print(f"🎉 All assets now use version: {new_version}")
        else:
            print("🔍 DRY RUN - No files were modified")
            print("💡 Run with --apply to apply these changes")


def main():
    parser = argparse.ArgumentParser(
        description="Cache bust static assets in HTML, CSS, and JS files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python cache_bust.py              # Preview changes (dry run)
  python cache_bust.py --apply      # Apply changes to files
        """,
    )

    parser.add_argument(
        '--apply',
        action='store_true',
        help='Apply changes to files (default is dry run)'
    )

    parser.add_argument(
        '--dir',
        type=str,
        default='.',
        help='Root directory to search (default: current directory)'
    )

    args = parser.parse_args()

    buster = CacheBuster(root_dir=args.dir)
    buster.run(dry_run=not args.apply)


if __name__ == "__main__":
    main()
