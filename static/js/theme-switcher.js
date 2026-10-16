/* ---- Theme switcher ----
 *
 * Flips `data-theme` on <html> and remembers the choice in localStorage. The initial
 * value is set by a small inline script in <head> rather than here, because this file
 * is deferred: waiting for it would paint the page in the wrong theme first and then
 * correct it, which is a visible flash on every load.
 *
 * Light is the default even when the OS prefers dark. These are paper pages usually
 * arrived at from a link and read once, and the light rendering is the one the figures
 * were authored against — so dark is opt-in rather than inferred.
 *
 * The favicon is a colour logo that reads on either tab background, so unlike
 * the reference implementation — whose favicon is a monochrome glyph that has to invert — there is
 * nothing to swap here.
 */
(function () {
    "use strict";

    var STORAGE_KEY = "theme-preference";
    var THEME_ATTR = "data-theme";

    function current() {
        return document.documentElement.getAttribute(THEME_ATTR) || "light";
    }

    function label(theme) {
        var btn = document.getElementById("theme-toggle");
        if (!btn) return;
        btn.setAttribute("aria-label",
            theme === "dark" ? "Switch to light mode" : "Switch to dark mode");
        btn.setAttribute("aria-pressed", theme === "dark" ? "true" : "false");
    }

    /* The browser chrome colour has to follow the page. `<meta name="theme-color">` can
       carry a `media` attribute, but that keys off `prefers-color-scheme` — the OS
       setting — and these pages deliberately default to light regardless of the OS,
       opting into dark only through localStorage. So on an OS-dark machine the media
       version would paint black chrome above a light page, which is wrong in exactly
       the common case. Setting it here instead keeps it tied to the actual theme. */
    function chrome(theme) {
        var m = document.querySelector('meta[name="theme-color"]');
        if (m) m.setAttribute("content", theme === "dark" ? "#000000" : "#ffffff");
    }

    function apply(theme) {
        document.documentElement.setAttribute(THEME_ATTR, theme);
        label(theme);
        chrome(theme);
    }

    function toggle() {
        /* Opt into the colour transition on the first toggle only. If the class were
           present at load, a page arriving already dark would visibly fade in from the
           light palette. */
        document.documentElement.classList.add("theme-anim");
        var next = current() === "dark" ? "light" : "dark";
        try {
            localStorage.setItem(STORAGE_KEY, next);
        } catch (e) {
            /* Private browsing can refuse writes; the theme still applies for the
               session, it just will not be remembered. */
        }
        apply(next);
    }

    function wire() {
        var btn = document.getElementById("theme-toggle");
        if (!btn || btn.dataset.themeWired) return;
        btn.dataset.themeWired = "true";
        btn.addEventListener("click", function (e) {
            e.preventDefault();
            toggle();
        });
        label(current());
    }

    apply(current());

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", wire);
    } else {
        wire();
    }

})();
