/* BibTeX copy button ------------------------------------------------------- */

document.addEventListener("DOMContentLoaded", function () {
    var copyButton = document.getElementById("copy-btn");
    var bibtex = document.getElementById("bibtex-content");
    var resetTimer;

    if (!copyButton || !bibtex) return;

    function showCopied() {
        copyButton.classList.add("copied");
        copyButton.innerHTML = '<i class="fas fa-check" aria-hidden="true"></i>';
        if (resetTimer) clearTimeout(resetTimer);
        resetTimer = setTimeout(function () {
            copyButton.classList.remove("copied");
            copyButton.innerHTML = '<i class="fa fa-copy" aria-hidden="true"></i>';
        }, 2000);
    }

    function fallbackCopy(text) {
        var textarea = document.createElement("textarea");
        textarea.value = text;
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        document.body.appendChild(textarea);
        textarea.focus();
        textarea.select();
        try {
            document.execCommand("copy");
            showCopied();
        } catch (error) {
            console.error("BibTeX copy failed", error);
        }
        document.body.removeChild(textarea);
    }

    copyButton.addEventListener("click", function (event) {
        event.preventDefault();
        var text = bibtex.textContent;
        if (!navigator.clipboard || !navigator.clipboard.writeText) {
            fallbackCopy(text);
            return;
        }
        navigator.clipboard.writeText(text).then(showCopied).catch(function () {
            fallbackCopy(text);
        });
    });
});
