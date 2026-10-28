# RIDE-Splat: Reflection Removal for In-the-Wild Driving Environments

Website source for [RIDE-Splat](https://ridesplat.github.io/).

Built as plain HTML, CSS and JavaScript — no framework and no application build step, so what is
in the repository is what the browser gets. The notes below cover the parts that are not obvious
from reading the markup. The [RIDE-Splat code](https://github.com/ridesplat/ride-splat) and
[dataset](https://github.com/ridesplat/ride-splat/releases/tag/dataset-v0.1) are available on GitHub.

---

## Credits

**Template.** This site began as the excellent academic paper template by the authors of
**[Nerfies](https://github.com/nerfies/nerfies.github.io)**.

Huge thanks to them for open-sourcing a clean, well-structured starting point. The page has since
been substantially rewritten — the stylesheets, JavaScript and media pipeline are our own — but
the page architecture and much of the class vocabulary (`publication-title`,
`publication-authors`, `author-block`, the footer glyph row) are still theirs, and these pages
would not look the way they do without it.

**Favicon.** The RIDE-Splat road-and-reflection mark is original to this project. Its SVG is the
canonical source; `tools/build-icons.sh` regenerates the PNG and ICO fallbacks.

**Libraries.** [Bulma](https://bulma.io/) (MIT), purged to the rules this page uses;
[Font Awesome](https://fontawesome.com/) and [Academicons](https://jpswalsh.github.io/academicons/)
(SIL OFL 1.1), subset to the glyphs in use; [Noto Sans](https://fonts.google.com/noto/specimen/Noto+Sans)
(SIL OFL 1.1), self-hosted; and [PDF.js](https://mozilla.github.io/pdf.js/) (Apache 2.0), loaded
from a CDN on demand.

**Licence.** The Nerfies template is released under
[CC BY-SA 4.0](http://creativecommons.org/licenses/by-sa/4.0/), so this site is offered under the
same terms. If you build on it, please credit both Nerfies and this repository, and pass the same
terms along.

---

## Performance

- **Packed comparison media.** Each four-way viewer decodes one 2×2 video rather than four
  independent streams. Phones receive a 1280px-wide pack, tablets and smaller laptops receive a
  1920px pack, and large screens retain the full-resolution pack. AV1 is preferred, H.264 is the
  compatibility fallback, and every variant is fast-start enabled. The source renders are
  frame-synchronized before packing, so one media clock guarantees exact comparison timing.
- **Media loaded on demand.** The teaser keeps its sources deferred until it approaches the
  viewport. Below-fold video sources and posters likewise remain in `data-` attributes until their
  carousel approaches. Only the active slide plays, and an off-screen viewer stops both canvas
  painting and video decoding.
- **Frame-synchronized drawing.** The comparison canvas uses `requestVideoFrameCallback` where
  available, painting once per decoded video frame instead of once per display refresh. Its
  backing store is capped at 2× DPR, beyond which extra pixels cost real per-frame work without a
  visible benefit.
- **Purged Bulma.** Only the rules this page uses are shipped — about 12 KB of the framework's
  roughly 200 KB. jQuery, bulma-carousel and the full Font Awesome bundle are absent.
- **Self-hosted, subset fonts.** Noto Sans is served from this repository. Font Awesome and
  Academicons contain only the glyphs present on the page; `tools/build-webfonts.sh` rebuilds and
  validates those subsets.
- **Space reserved before decode.** Images, videos and canvases declare their source aspect ratio,
  so media arriving does not shift the surrounding page.
- **`cache_bust.py`.** One version query covers local assets in HTML attributes, inline poster
  backgrounds, stylesheet `url()` declarations and JavaScript-built URLs. Matching the preload
  and `@font-face` URLs prevents the browser from fetching one font twice.

## Light and dark themes

- **`theme.css` + `theme-switcher.js`.** Every colour resolves through a custom property, so a
  theme is one attribute on `<html>` rather than a cascade of overrides. The footer's sun/moon
  toggle persists its choice in `localStorage`.
- **Light is the deliberate default.** These are paper pages usually reached from a link and read
  once, and the light rendering is the one against which the figures were authored. Dark is
  opt-in rather than inferred from the operating system.
- **No flash.** A small inline script at the top of `<head>` applies the saved theme before first
  paint. A deferred script would let the page paint light before correcting itself.
- **Dark is a palette, not an inversion.** Shadows, text, links, controls and surfaces use values
  chosen for their actual dark background; paper figures remain on light cards so their encoded
  colours and black text are preserved.

## Accessibility

- Landmarks and a document-order heading outline with one `<h1>`.
- Meaningful alternative text on figures and discernible names on links and controls.
- Keyboard operation for both axes of the four-way comparison, plus play/pause and reset.
- Visible focus rings in both themes and 44px touch targets where compact glyphs need them.
- `prefers-reduced-motion` disables carousel and interaction animation.
- Long words wrap rather than becoming clipped behind Bulma's hidden horizontal overflow.
- The PDF overlay is focus-trapped, labelled as a dialog, closes with Escape, restores focus, and
  falls back to the operating system's PDF viewer on touch-primary mobile devices.

## Repository layout

```text
.
├── index.html
├── static/
│   ├── css/
│   │   ├── bulma.min.css         # purged to this page's rules
│   │   ├── icons.css             # @font-face + the glyphs in use
│   │   ├── index.css             # page-specific layout
│   │   ├── interactions.css      # hover and focus polish
│   │   ├── noto-sans.css         # self-hosted body typeface
│   │   ├── pdf-modal.css         # in-page PDF overlay
│   │   ├── rhythm.css            # responsive spacing and footer layout
│   │   ├── slideshow.css         # responsive peeking carousels
│   │   └── theme.css             # colour tokens and both themes
│   ├── js/
│   │   ├── pdf-modal.js          # focus-trapped PDF overlay, PDF.js on demand
│   │   ├── script.js             # BibTeX copy button
│   │   ├── slideshow.js          # cyclic carousel and playback handling
│   │   ├── theme-switcher.js     # persisted light/dark choice
│   │   └── video_comparison.js   # packed four-way canvas viewer
│   ├── webfonts/                 # subset icon fonts + Noto Sans
│   ├── images/                   # figures, social card and favicons
│   ├── videos/                   # web-delivery AV1/H.264 encodes + posters
├── tools/
│   ├── build-comparison-media.sh # pack masters and encode delivery media
│   ├── build-icons.sh            # regenerate favicon/touch-icon assets
│   ├── build-media.sh            # generic media encoder
│   ├── build-results-table.sh    # rasterize Table II from a supplied paper PDF
│   └── build-webfonts.sh         # rebuild font subsets
├── cache_bust.py                 # stamp ?v= on every local asset
├── run_server.sh
├── robots.txt
└── sitemap.xml
```

## The moving parts

- **Four-way video comparison** (`video_comparison.js`)
  One packed 2×2 source is cropped into four canvas regions around a cross that moves on both
  axes. Labels remain canvas-drawn and resolution-independent rather than burned into the media.
  Pointer, touch and keyboard input share one position model; click, Space or Enter toggles
  playback. The teaser pauses when it leaves the viewport.
- **Dataset and results carousels** (`slideshow.js` + `slideshow.css`)
  Dependency-free cyclic rings with arrows, dots and keyboard navigation. The dataset tours keep
  their reflective and non-reflective traversals side by side. Results comparisons disable swipe
  so a drag belongs to the comparison cross; dataset slides retain mouse and touch swiping.
- **Source and delivery media** (`../.video/` + `tools/build-comparison-media.sh`)
  Original media is kept outside the website repository under `/RIDE-Splat/.video/`; comparison
  masters also mirror the private [`ridesplat/raw-comparisons` release](https://github.com/ridesplat/raw-comparisons/releases/tag/v1-shared-path).
  The build verifies matching dimensions, frame rates and frame counts before packing comparisons,
  writes AV1 and H.264 variants, moves MP4 metadata to the front for progressive playback, and
  generates lightweight posters plus 1280px and 1920px responsive variants. Town02 uses its
  recommended frame-77-through-216 trim. The packed order is 3DGS/DC-Gaussian on top and
  RobustSplat/RIDE-Splat on the bottom. Set `RIDE_SPLAT_MEDIA_ROOT` when the source directory is
  stored elsewhere; use `--responsive-only` to rebuild responsive variants from the packed
  delivery files.
- **In-page PDF viewer** (`pdf-modal.js`)
  PDF links open in a focus-trapped overlay. PDF.js is fetched only on first use to determine an
  appropriate initial zoom; mobile devices use their native viewer. The Paper controls link to the
  external arXiv PDF.
- **Footer colophon** (`.colophon` in `theme.css`)
  Copyright, theme toggle and source link share one line after the paper-link glyph row. The
  toggle is a button because it changes this page rather than navigating elsewhere.

## Related project websites

These paper pages share the same foundation — purged Bulma, self-hosted font subsets, responsive
carousels, theme switching, cache busting and media build tools. Read any of them as reference
code, and borrow freely:

- **[PUP 3D-GS](https://pup3dgs.github.io/)** — [source](https://github.com/pup3dgs/pup3dgs.github.io)
- **[Speedy-Splat](https://speedysplat.github.io/)** — [source](https://github.com/speedysplat/speedysplat.github.io)
- **[SpeeDe3DGS](https://speede3dgs.github.io/)** — [source](https://github.com/speede3dgs/speede3dgs.github.io)
- **[SplatSuRe](https://splatsure.github.io/)** — [source](https://github.com/splatsure/splatsure.github.io)
- **[TransFIRA](https://transfira.github.io/)** — [source](https://github.com/transfira/transfira.github.io)

If you are starting a paper page from scratch, take Nerfies as the base and treat these as worked
examples of where to go next. Anything from these repositories carries the CC BY-SA 4.0 terms
noted above.

## Local development

```sh
./run_server.sh                    # serve at http://localhost:8000
python3 cache_bust.py              # dry run: show version changes
python3 cache_bust.py --apply      # update local-asset versions
tools/build-comparison-media.sh    # rebuild packed and dataset delivery videos
tools/build-results-table.sh PDF   # rebuild Table II from a supplied paper PDF
tools/build-icons.sh               # rebuild raster icons from the SVG mark
tools/build-webfonts.sh            # rebuild and validate font subsets
```
