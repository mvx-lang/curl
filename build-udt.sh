#!/bin/sh
# curl — stage the UniData curl HTTP seam into $1 for the udt-build action.
# Pure BASIC (curl-backed HTTPGET/HTTPGETFILE) — no native build — so this just
# lays the functions into BP/ (where MVPKG's CATALOG op finds them) alongside
# the manifest.  Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only.
set -e
STAGE="${1:?usage: build-udt.sh <stagedir>}"
SRC="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$STAGE/BP"
cp "$SRC/udt/HTTPGET" "$STAGE/BP/HTTPGET"
cp "$SRC/udt/HTTPGETFILE" "$STAGE/BP/HTTPGETFILE"
cp "$SRC/mvpkg.json" "$SRC/PKG" "$SRC/LICENSE" "$STAGE/" 2>/dev/null || true
echo "build-udt: staged the curl BASIC HTTP seam"
