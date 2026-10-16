/* Interactive four-way comparison backed by one packed 2x2 video.
 *
 * Packed layout:
 *
 *   3DGS        | DC-Gaussian
 *   ------------+------------
 *   RobustSplat | RIDE-Splat
 *
 * One media element means one request, decoder, and playback clock. Canvas
 * crops matching regions from the four packed quadrants as the cross moves.
 */

function canvasDpr() {
    return Math.min(window.devicePixelRatio || 1, 2);
}

function perFrame(fn) {
    var queued = false;
    return function () {
        if (queued) return;
        queued = true;
        requestAnimationFrame(function () {
            queued = false;
            fn();
        });
    };
}

function resizeAndPlayFourWay(video) {
    var canvas = document.getElementById(video.id + "Merge");
    if (!canvas || video.dataset.fourWayReady || video.dataset.fourWayPending) return;

    if (!video.videoWidth || video.readyState < 3) {
        video.dataset.fourWayPending = "true";
        video.addEventListener("canplay", function once() {
            video.removeEventListener("canplay", once);
            delete video.dataset.fourWayPending;
            resizeAndPlayFourWay(video);
        });
        return;
    }

    video.dataset.fourWayReady = "true";
    initialiseFourWayComparison(video, canvas);
}

function initialiseFourWayComparison(video, canvas) {
    var container = canvas.parentElement;
    var context = canvas.getContext("2d", { alpha: false });
    var positionX = 0.5;
    var positionY = 0.5;
    var onScreen = true;
    var touchDragging = false;
    var suppressClick = false;
    var visibilityPaused = false;
    var drawRequest = null;
    var playbackRequest = null;
    var usesVideoFrames = typeof video.requestVideoFrameCallback === "function";
    var isMobile = window.innerWidth <= 960;
    var computedFont = window.getComputedStyle(canvas).fontFamily;
    var labels = {
        topLeft: container.dataset.topLeftLabel || "3DGS",
        topRight: container.dataset.topRightLabel || "DC-Gaussian",
        bottomLeft: container.dataset.bottomLeftLabel || "RobustSplat",
        bottomRight: container.dataset.bottomRightLabel || "RIDE-Splat (Ours)"
    };

    function paintSoon() {
        if (drawRequest !== null) return;
        drawRequest = requestAnimationFrame(function () {
            drawRequest = null;
            paint();
        });
    }

    function schedulePlaybackFrame() {
        if (playbackRequest !== null || video.paused || !onScreen) return;

        if (usesVideoFrames) {
            playbackRequest = video.requestVideoFrameCallback(function () {
                playbackRequest = null;
                paint();
                schedulePlaybackFrame();
            });
        } else {
            playbackRequest = requestAnimationFrame(function () {
                playbackRequest = null;
                paint();
                schedulePlaybackFrame();
            });
        }
    }

    function cancelPlaybackFrame() {
        if (playbackRequest === null) return;
        if (usesVideoFrames && typeof video.cancelVideoFrameCallback === "function") {
            video.cancelVideoFrameCallback(playbackRequest);
        } else {
            cancelAnimationFrame(playbackRequest);
        }
        playbackRequest = null;
    }

    function updateSize() {
        container.style.width = "";
        var containerWidth = parseFloat(window.getComputedStyle(container).width);
        var aspectRatio = video.videoHeight / video.videoWidth;
        var maxViewportHeight = window.innerHeight * 0.8;
        var idealHeight = containerWidth * aspectRatio;
        var finalWidth;
        var finalHeight;

        if (idealHeight > maxViewportHeight) {
            finalHeight = maxViewportHeight;
            finalWidth = finalHeight / aspectRatio;
        } else {
            finalWidth = containerWidth;
            finalHeight = idealHeight;
        }

        var dpr = canvasDpr();
        canvas.width = Math.round(finalWidth * dpr);
        canvas.height = Math.round(finalHeight * dpr);
        canvas.style.width = finalWidth + "px";
        canvas.style.height = finalHeight + "px";
        canvas.style.margin = "0 auto";
        canvas.style.display = "block";

        container.style.width = finalWidth + "px";
        container.style.maxWidth = "100%";
        container.style.marginLeft = "auto";
        container.style.marginRight = "auto";

        context.setTransform(dpr, 0, 0, dpr, 0, 0);
        paintSoon();
    }

    function updateAriaValue() {
        canvas.setAttribute("aria-valuetext",
            "Vertical divider " + Math.round(positionX * 100) +
            " percent; horizontal divider " + Math.round(positionY * 100) + " percent");
    }

    function setPosition(clientX, clientY) {
        var rect = canvas.getBoundingClientRect();
        if (!rect.width || !rect.height) return;
        positionX = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
        positionY = Math.max(0, Math.min(1, (clientY - rect.top) / rect.height));
        updateAriaValue();
        paintSoon();
    }

    function togglePlayback() {
        visibilityPaused = false;
        if (video.paused) {
            var promise = video.play();
            if (promise && promise.catch) promise.catch(function () { });
        } else {
            video.pause();
        }
    }

    canvas.addEventListener("mousemove", function (event) {
        setPosition(event.clientX, event.clientY);
    }, { passive: true });

    canvas.addEventListener("touchstart", function (event) {
        var touch = event.touches[0];
        var rect = canvas.getBoundingClientRect();
        var handleX = rect.left + rect.width * positionX;
        var handleY = rect.top + rect.height * positionY;
        touchDragging = Math.hypot(touch.clientX - handleX, touch.clientY - handleY) < 52;
        suppressClick = false;
        if (touchDragging && event.cancelable) event.preventDefault();
    }, { passive: false });

    canvas.addEventListener("touchmove", function (event) {
        if (!touchDragging) return;
        if (event.cancelable) event.preventDefault();
        suppressClick = true;
        setPosition(event.touches[0].clientX, event.touches[0].clientY);
    }, { passive: false });

    canvas.addEventListener("touchend", function () {
        touchDragging = false;
    }, { passive: true });

    canvas.addEventListener("click", function () {
        if (suppressClick) {
            suppressClick = false;
            return;
        }
        togglePlayback();
    });

    canvas.addEventListener("keydown", function (event) {
        var step = event.shiftKey ? 0.1 : 0.02;
        var handled = true;

        if (event.key === "ArrowLeft") positionX -= step;
        else if (event.key === "ArrowRight") positionX += step;
        else if (event.key === "ArrowUp") positionY -= step;
        else if (event.key === "ArrowDown") positionY += step;
        else if (event.key === "Home") {
            positionX = 0.5;
            positionY = 0.5;
        } else if (event.key === " " || event.key === "Enter") {
            togglePlayback();
        } else {
            handled = false;
        }

        if (!handled) return;
        event.preventDefault();
        positionX = Math.max(0, Math.min(1, positionX));
        positionY = Math.max(0, Math.min(1, positionY));
        updateAriaValue();
        paintSoon();
    });

    video.addEventListener("play", schedulePlaybackFrame);
    video.addEventListener("pause", function () {
        cancelPlaybackFrame();
        paintSoon();
    });
    video.addEventListener("seeked", paintSoon);

    if ("IntersectionObserver" in window) {
        new IntersectionObserver(function (entries) {
            onScreen = entries[entries.length - 1].isIntersecting;
            if (!onScreen) {
                cancelPlaybackFrame();
                if (!video.paused && !video.closest(".slideshow")) {
                    visibilityPaused = true;
                    video.pause();
                }
            } else {
                paintSoon();
                if (visibilityPaused) {
                    visibilityPaused = false;
                    var promise = video.play();
                    if (promise && promise.catch) promise.catch(function () { });
                } else {
                    schedulePlaybackFrame();
                }
            }
        }, { threshold: 0.01 }).observe(canvas);
    }

    function drawQuadrant(column, row, x, y, width, height, cw, ch) {
        if (width <= 0 || height <= 0) return;
        var quadrantWidth = video.videoWidth / 2;
        var quadrantHeight = video.videoHeight / 2;
        var sourceX = column * quadrantWidth + quadrantWidth * (x / cw);
        var sourceY = row * quadrantHeight + quadrantHeight * (y / ch);
        var sourceWidth = quadrantWidth * (width / cw);
        var sourceHeight = quadrantHeight * (height / ch);

        context.drawImage(video,
            sourceX, sourceY, sourceWidth, sourceHeight,
            x, y, width, height);
    }

    function drawBubble(text, x, y, alignRight, alignBottom, fontSize) {
        var paddingX = fontSize * 0.6;
        var paddingY = fontSize * 0.35;
        var radius = fontSize * 0.6;
        var textWidth = context.measureText(text).width;
        var boxWidth = textWidth + paddingX * 2;
        var boxHeight = fontSize + paddingY * 2;
        var rectX = alignRight ? x - boxWidth : x;
        var rectY = alignBottom ? y - boxHeight : y;

        context.fillStyle = "rgba(0, 0, 0, 0.55)";
        context.beginPath();
        context.roundRect(rectX, rectY, boxWidth, boxHeight, radius);
        context.fill();
        context.fillStyle = "white";
        context.fillText(text, rectX + paddingX, rectY + boxHeight / 2);
    }

    function drawHandle(splitX, splitY, cw, ch) {
        var handleRadius = 21;
        var arrowSize = 5;
        var arrowOffset = 5;

        context.save();
        context.shadowColor = "rgba(12, 12, 12, 0.8)";
        context.shadowBlur = 10;
        context.strokeStyle = "#FFFFFF";
        context.fillStyle = "#FFFFFF";
        context.lineWidth = 2;

        context.beginPath();
        context.moveTo(splitX, 0);
        context.lineTo(splitX, Math.max(0, splitY - handleRadius));
        context.moveTo(splitX, Math.min(ch, splitY + handleRadius));
        context.lineTo(splitX, ch);
        context.moveTo(0, splitY);
        context.lineTo(Math.max(0, splitX - handleRadius), splitY);
        context.moveTo(Math.min(cw, splitX + handleRadius), splitY);
        context.lineTo(cw, splitY);
        context.stroke();

        context.beginPath();
        context.arc(splitX, splitY, handleRadius, 0, 2 * Math.PI);
        context.stroke();

        [[-1, 0], [1, 0], [0, -1], [0, 1]].forEach(function (direction) {
            var dx = direction[0];
            var dy = direction[1];
            context.beginPath();
            if (dx) {
                context.moveTo(splitX + dx * (arrowOffset + arrowSize), splitY);
                context.lineTo(splitX + dx * arrowOffset, splitY - arrowSize);
                context.lineTo(splitX + dx * arrowOffset, splitY + arrowSize);
            } else {
                context.moveTo(splitX, splitY + dy * (arrowOffset + arrowSize));
                context.lineTo(splitX - arrowSize, splitY + dy * arrowOffset);
                context.lineTo(splitX + arrowSize, splitY + dy * arrowOffset);
            }
            context.closePath();
            context.fill();
        });
        context.restore();
    }

    function paint() {
        if (!video.videoWidth || video.readyState < 2) return;
        var dpr = canvasDpr();
        var cw = canvas.width / dpr;
        var ch = canvas.height / dpr;
        var splitX = cw * positionX;
        var splitY = ch * positionY;

        context.fillStyle = "#000000";
        context.fillRect(0, 0, cw, ch);
        drawQuadrant(0, 0, 0, 0, splitX, splitY, cw, ch);
        drawQuadrant(1, 0, splitX, 0, cw - splitX, splitY, cw, ch);
        drawQuadrant(0, 1, 0, splitY, splitX, ch - splitY, cw, ch);
        drawQuadrant(1, 1, splitX, splitY, cw - splitX, ch - splitY, cw, ch);

        var fontSize = Math.round(ch * (isMobile ? 0.06 : 0.04));
        var inset = 6;
        context.font = fontSize + "px " + computedFont;
        context.textBaseline = "middle";
        drawBubble(labels.topLeft, inset, inset, false, false, fontSize);
        drawBubble(labels.topRight, cw - inset, inset, true, false, fontSize);
        drawBubble(labels.bottomLeft, inset, ch - inset, false, true, fontSize);
        drawBubble(labels.bottomRight, cw - inset, ch - inset, true, true, fontSize);
        drawHandle(splitX, splitY, cw, ch);
    }

    window.addEventListener("resize", perFrame(function () {
        isMobile = window.innerWidth <= 960;
        computedFont = window.getComputedStyle(canvas).fontFamily;
        updateSize();
    }), { passive: true });

    updateAriaValue();
    updateSize();
    paintSoon();
    schedulePlaybackFrame();
}
