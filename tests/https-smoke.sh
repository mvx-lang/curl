#!/bin/sh
# curl — prove the staged mvx package actually speaks HTTPS.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
#
#   sh tests/https-smoke.sh <staged-package-dir>        ($MVXHOME must be set)
#
# THE POINT OF THIS PACKAGE IS HTTPS, SO THAT IS WHAT GETS TESTED -- a library
# that loads is not a transport that works.  Lay the package over a copy of the
# system account, as the mvx installer does, and make real requests.
#
# mvx's own `http' package LEAVES THE COPY FIRST: it exports HTTPGET too, and a
# test that could be answered by the plain-HTTP client is not a test of this
# one.
#
# IT LIVES HERE RATHER THAN IN release.yml BECAUSE CI RUNS IT TOO (#25).  It was
# written as a step inside the release job, so it ran on a tag and nothing else
# -- the one real test this package has, and a pull request never saw it.  A
# second copy in ci.yml would drift from this one; one script, two callers.
set -eu
DIST="${1:?usage: https-smoke.sh <staged-package-dir>}"
: "${MVXHOME:?set MVXHOME to the installed toolchain}"

SMOKE="$(mktemp -d)"
trap 'rm -rf "$SMOKE" /tmp/curl-smoke-index /tmp/curl-smoke-post' EXIT INT TERM

cp -a "$MVXHOME/share/mvx/system" "$SMOKE/system"
rm -f "$SMOKE"/system/LIB/libmvxext_http.*
mkdir -p "$SMOKE/system/LIB" "$SMOKE/u"
cp "$DIST"/LIB/* "$SMOKE/system/LIB/"
cat "$DIST/EXPORTS" > "$SMOKE/system/EXPORTS"

cat > "$SMOKE/u/t.b" <<'BAS'
B = HTTPGET("https://packages.mvx-lang.org/search?q=curl")
PRINT "get:" : LEN(B) : ":" : INDEX(B, '"packages"', 1)
S = HTTPGETFILE("https://packages.mvx-lang.org/packages", "/tmp/curl-smoke-index")
PRINT "getfile:" : S
P = HTTPPOST("https://packages.mvx-lang.org/webhook/release-smoke", "application/json", "{}", "/tmp/curl-smoke-post")
PRINT "post:" : P
BAS

out="$(cd "$SMOKE/u" && MVXSYSTEM="$SMOKE/system" mvx-basic t.b -o t 2>&1 \
       && MVXSYSTEM="$SMOKE/system" MVXACCOUNT=. ./t 2>&1)" || true
printf '%s\n' "$out"

# a body that mentions "packages"; the index downloaded (200); and a POST that
# reached the server and got its real answer (404: there is no such webhook) --
# not -1, which would mean no request was made.
get="$(printf '%s\n' "$out" | sed -n 's/^get:\([0-9]*\):\([0-9]*\)$/\1 \2/p')"
gf="$(printf '%s\n' "$out" | sed -n 's/^getfile:\(-*[0-9]*\)$/\1/p')"
po="$(printf '%s\n' "$out" | sed -n 's/^post:\(-*[0-9]*\)$/\1/p')"
# shellcheck disable=SC2086  # $get is the two numbers above, split on purpose
set -- $get
if [ "${1:-0}" -gt 0 ] && [ "${2:-0}" -gt 0 ] && [ "$gf" = 200 ] && [ "$po" = 404 ]; then
  echo "smoke: HTTPGET, HTTPGETFILE and HTTPPOST work over HTTPS"
else
  echo "::error::the mvx curl package does not work over HTTPS (get='$get' getfile='$gf' post='$po')"
  exit 1
fi
