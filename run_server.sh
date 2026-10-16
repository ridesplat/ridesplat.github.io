#!/bin/bash
#
# Serve the site locally for development.
#
# Usage: ./run_server.sh [port]     (default 8000, then http://localhost:8000)
#
# A real HTTP server rather than opening index.html directly: the page fetches
# same-origin assets and uses absolute-ish paths, and file:// applies a stricter
# origin policy that breaks both.
set -euo pipefail
cd "$(dirname "$0")"
PORT="${1:-8000}"
echo "Serving $(pwd) at http://localhost:${PORT}  (Ctrl-C to stop)"
exec python3 -m http.server --bind 127.0.0.1 "$PORT"
