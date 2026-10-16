/**
 * pdf-modal.js
 * Full-screen PDF viewer modal with toolbar.
 * - Injected lazily on first open (no DOM cost on load)
 * - Intercepts a[href*=".pdf"] and a[href*="/pdf/"] clicks site-wide via event delegation
 * - Probes first page dimensions via pdf.js to auto-apply #view=Fit for
 *   landscape/poster documents; falls back to browser default for portrait
 * - Title read from link's title attribute, then innerText
 * - Site-agnostic: the site's own name is looked up at runtime (see _getSiteName)
 *   rather than hardcoded, so this file is byte-identical across all of the sites
 * - Exposed as role="dialog" aria-modal="true" labelled by the toolbar title;
 *   focus moves into it on open, is trapped while open, and is restored on close
 * - On mobile (touch) devices, skips the modal and lets the browser/OS
 *   handle PDFs natively (iframe PDF rendering is unsupported on Android/iOS)
 * - Closes on Escape, toolbar ×, or backdrop click
 */

/** True on any touch-primary device (Android, iOS, iPadOS). */
const _isMobile = () => navigator.maxTouchPoints > 0 && /Mobi|Android|iPhone|iPad/i.test(navigator.userAgent);

/** Tabbable controls inside the overlay, in DOM order. The overlay itself carries
 *  tabindex="-1" so it is deliberately excluded from the cycle. */
const _FOCUSABLE = 'a[href], button:not([disabled]), iframe, [tabindex]:not([tabindex="-1"])';

/** Whatever had focus when the modal opened, so closePDF can hand it back. */
let _lastFocused = null;

// ── Helpers ──────────────────────────────────────────────

/** This site's short name, e.g. "RIDE-Splat".
 *  og:site_name is an explicit author declaration and is present on every one of
 *  these sites, so it is the primary source. document.title up to the first colon
 *  is only a fallback: it is a heuristic that silently returns the whole title on
 *  a title with no colon, or truncates a name that itself contains one.
 *  Returns '' if neither yields anything, so callers can degrade gracefully. */
function _getSiteName() {
  const meta = document.querySelector('meta[property="og:site_name"]');
  const fromMeta = meta && meta.getAttribute('content');
  if (fromMeta && fromMeta.trim()) return fromMeta.trim();
  return document.title.split(':')[0].trim();
}

/** Prefer the page's SVG favicon, including its cache-busting query string. */
function _getSiteIcon() {
  const svg = document.querySelector('link[rel~="icon"][type="image/svg+xml"]');
  const fallback = document.querySelector('link[rel~="icon"]');
  const icon = svg || fallback;
  return icon ? icon.href : '';
}

/** Dynamically load pdf.js if not already loaded. */
async function _loadPdfJs() {
  if (window.pdfjsLib) return;
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
    script.onload = () => {
      pdfjsLib.GlobalWorkerOptions.workerSrc =
        'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
      resolve();
    };
    script.onerror = reject;
    document.head.appendChild(script);
  });
}

/** Return the URL with an optimal zoom fragment appended.
 *  Landscape/poster PDFs get #view=Fit; portrait docs use browser default. */
async function _getOptimalViewerUrl(url) {
  // Respect any existing view/zoom parameter
  if (url.includes('zoom=') || url.includes('view=')) return url;

  try {
    await _loadPdfJs();
    const pdf = await pdfjsLib.getDocument(url).promise;
    const viewport = (await pdf.getPage(1)).getViewport({ scale: 1.0 });
    if (viewport.width > viewport.height) {
      return url + (url.includes('#') ? '&' : '#') + 'view=Fit';
    }
  } catch (e) {
    console.warn('pdf-modal: failed to probe PDF dimensions, using default zoom.', e);
  }

  return url;
}

/** Keep Tab cycling inside the overlay while it is open. */
function _trapTab(e) {
  const overlay = document.getElementById('pdfOverlay');
  if (!overlay || !overlay.classList.contains('active')) return;

  const items = Array.from(overlay.querySelectorAll(_FOCUSABLE))
    .filter((el) => el.offsetWidth > 0 || el.offsetHeight > 0);
  if (!items.length) return;

  const first = items[0];
  const last = items[items.length - 1];
  const active = document.activeElement;

  if (active === overlay || !overlay.contains(active)) {
    // Focus is on the dialog container itself, or has landed on the page behind.
    e.preventDefault();
    (e.shiftKey ? last : first).focus();
  } else if (e.shiftKey && active === first) {
    e.preventDefault();
    last.focus();
  } else if (!e.shiftKey && active === last) {
    e.preventDefault();
    first.focus();
  }
}

/** Create and cache the overlay DOM element. */
function _getOrCreateOverlay() {
  let overlay = document.getElementById('pdfOverlay');
  if (overlay) return overlay;

  overlay = document.createElement('div');
  overlay.id = 'pdfOverlay';
  overlay.className = 'pdf-overlay';
  // Dialog semantics: named by the toolbar title, and focusable (tabindex="-1")
  // so that opening the modal can move focus into it.
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-labelledby', 'pdfTitle');
  overlay.setAttribute('tabindex', '-1');
  // The two logos are decorative here: their <a> is a close affordance, and its
  // aria-label already names it, so alt text would only be redundant noise.
  overlay.innerHTML = `
    <div class="pdf-toolbar">
      <div class="pdf-toolbar-left">
        <a href="#" onclick="closePDF(event)" class="pdf-logo-close" aria-label="Close">
          <img src="" alt="" class="logo-desktop" style="height:22px;width:auto;">
          <img src="" alt="" class="logo-mobile" style="height:26px;width:auto;">
        </a>
        <div class="pdf-title" id="pdfTitle"></div>
      </div>
      <div class="pdf-toolbar-actions">
        <a class="pdf-toolbar-btn" id="pdfDownload" href="#" download>
          <i class="fas fa-download"></i><span class="btn-label">Download</span>
        </a>
        <a class="pdf-toolbar-btn" id="pdfNewTab" href="#" target="_blank">
          <i class="fas fa-external-link-alt"></i><span class="btn-label">Open in New Tab</span>
        </a>
        <button class="pdf-toolbar-btn close-btn" onclick="closePDF(event)" aria-label="Close">&times;</button>
      </div>
    </div>
    <div class="pdf-viewer-container">
      <iframe class="pdf-viewer-frame" id="pdfFrame" src=""></iframe>
    </div>
  `;
  // Set via setAttribute rather than interpolated into the markup above so the
  // looked-up name never has to be HTML-escaped.
  const site = _getSiteName();
  overlay.querySelector('.pdf-logo-close')
    .setAttribute('aria-label', site ? `Close ${site} PDF viewer` : 'Close PDF viewer');
  const icon = _getSiteIcon();
  overlay.querySelectorAll('.pdf-logo-close img').forEach(function (image) {
    image.src = icon;
  });
  document.body.appendChild(overlay);

  // Close on backdrop click (not toolbar)
  overlay.addEventListener('click', function (e) {
    if (e.target === overlay) closePDF();
  });

  return overlay;
}

// ── Public API ───────────────────────────────────────────

async function openPDF(event, url, title) {
  if (event) event.preventDefault();

  const overlay = _getOrCreateOverlay();

  // Remember where focus came from, but only on a genuine open, so that reopening
  // over an already-open modal cannot record an element inside the overlay.
  if (!overlay.classList.contains('active')) _lastFocused = document.activeElement;

  document.getElementById('pdfTitle').textContent = title || 'PDF';
  document.getElementById('pdfNewTab').href = url;  // always the full-size original

  const downloadBtn = document.getElementById('pdfDownload');
  downloadBtn.target = '';
  downloadBtn.href = '#';
  downloadBtn.onclick = async (e) => {
    e.preventDefault();
    const originalHtml = downloadBtn.innerHTML;

    // Show loading state
    downloadBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i><span class="btn-label">Downloading...</span>';
    downloadBtn.style.pointerEvents = 'none';

    try {
      // For arXiv, use the bare URL (no .pdf) — that endpoint returns CORS headers.
      // Appending .pdf triggers a 301 redirect that drops Access-Control-Allow-Origin.
      // For local/same-origin PDFs, use the URL as-is.
      const fetchUrl = url.includes('arxiv.org') && url.endsWith('.pdf')
        ? url.slice(0, -4) : url;
      const res = await fetch(fetchUrl);
      const blob = await res.blob();

      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = blobUrl;

      // Use filename from Content-Disposition header if exposed,
      // then arxiv ID fallback, then basename from URL.
      const disposition = res.headers.get('content-disposition') || '';
      const nameMatch = disposition.match(/filename="?([^"]+)"?/);
      const arxivIdMatch = url.match(/arxiv\.org\/(?:pdf|abs)\/([\d.]+)/);
      const baseName = url.split('/').pop().split('?')[0];
      a.download = nameMatch ? nameMatch[1]
        : arxivIdMatch ? `${arxivIdMatch[1]}.pdf`
          : baseName || 'document.pdf';

      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);
    } catch (err) {
      console.error('pdf-modal: download failed, opening in new tab.', err);
      window.open(url, '_blank');
    } finally {
      downloadBtn.innerHTML = originalHtml;
      downloadBtn.style.pointerEvents = '';
    }
  };

  // Show modal immediately while zoom is being determined
  overlay.classList.add('active');
  document.body.style.overflow = 'hidden';
  void overlay.offsetWidth; // trigger CSS transition
  overlay.classList.add('show');

  // Focus the dialog itself (not a control) so its role and title are announced;
  // Tab from here moves to the first toolbar control. Must follow .active, since
  // a display:none element cannot take focus.
  overlay.focus();

  // For poster PDFs, load a scaled-down _viewer version in the iframe so it fits screen sizes.
  // The download and "Open in New Tab" buttons always link to the original full-size URL.
  // Strip query/hash before testing so ?v= cache-bust params don't break the match.
  const isPoster = /poster[^/]*\.pdf$/i.test(url.split('?')[0].split('#')[0]);
  let frameUrl = url;
  if (isPoster) {
    frameUrl = url.replace(/\.pdf(\?|#|$)/i, '_viewer.pdf$1');
    frameUrl += (frameUrl.includes('#') ? '&' : '#') + 'view=Fit';
  } else {
    frameUrl = await _getOptimalViewerUrl(url);
  }
  document.getElementById('pdfFrame').src = frameUrl;
}

function closePDF(event) {
  if (event) event.preventDefault();
  const overlay = document.getElementById('pdfOverlay');
  if (!overlay) return;
  overlay.classList.remove('show');
  document.body.style.overflow = '';

  // Hand focus back to whatever opened the modal, now rather than after the fade,
  // so focus never falls back to <body> when the overlay is hidden.
  const restore = _lastFocused;
  _lastFocused = null;
  if (restore && document.contains(restore) && typeof restore.focus === 'function') {
    restore.focus();
  }

  setTimeout(function () {
    overlay.classList.remove('active');
    document.getElementById('pdfFrame').src = '';
  }, 250);
}

// ── Global event listeners ────────────────────────────────

document.addEventListener('keydown', function (e) {
  if (e.key === 'Escape') closePDF();
  if (e.key === 'Tab') _trapTab(e);
});

// Intercept all PDF link clicks site-wide (matches .pdf extensions and /pdf/ path-style URLs)
document.body.addEventListener('click', function (e) {
  const link = e.target.closest('a[href*=".pdf"], a[href*="/pdf/"]');
  if (!link) return;

  // Skip links inside the overlay itself (Download, Open in New Tab)
  if (link.closest('#pdfOverlay')) return;

  // On mobile, iframe PDF rendering is not supported — let the browser handle it natively
  if (_isMobile()) return;

  e.preventDefault();
  // Prefer explicit title attribute, fall back to visible link text
  const title = link.getAttribute('title') || link.innerText.trim() || 'PDF Document';
  openPDF(e, link.href, title);
});
