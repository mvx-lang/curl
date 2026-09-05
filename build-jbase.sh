#!/bin/sh
# curl — build the jBASE release into $1: the DEFC shared library plus the BASIC
# wrappers.  Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
#
# Runs INSIDE the jbase-builder container (driven by the jbase-build action).
#
#   sh build-jbase.sh <stagedir>
#
# UniData folds its CallC contribution into libu2callc.so as an OBJECT; jBASE
# resolves DEFC against a SHARED LIBRARY instead, so this links one -- against
# libcurl, and against jBASE's own headers for the VAR type.
set -e
STAGE="${1:?usage: build-jbase.sh <stagedir>}"
SRC="$(cd "$(dirname "$0")" && pwd)"
: "${JBCRELEASEDIR:?JBCRELEASEDIR must be set (run inside the jbase-builder container)}"
CC="${CC:-cc}"
ACCT="$STAGE/curl"

mkdir -p "$ACCT/BP" "$ACCT/lib"

# -std=c11 is STRICT about POSIX: without _POSIX_C_SOURCE the jBASE headers pull
# in declarations that are not ISO C, and an undeclared function is assumed to
# return int -- which truncates a 64-bit pointer and takes the process down with
# no message (the trap mv_git#192 records).  Ask for c11 WITH the POSIX macro.
"$CC" -std=c11 -D_POSIX_C_SOURCE=200809L -O2 -fPIC -shared \
      -DMVXCURL_JBASE \
      -I"$JBCRELEASEDIR/include" \
      "$SRC/src/mvxcurl.c" \
      -lcurl \
      -o "$ACCT/lib/libjbcurl.so"
echo "build-jbase: built lib/libjbcurl.so (JBCURLGET/JBCURLGETFILE)"

cp "$SRC/jbase/HTTPGET" "$SRC/jbase/HTTPGETFILE" "$ACCT/BP/"
for f in mvpkg.json PKG LICENSE README.md; do
   if [ -f "$SRC/$f" ]; then cp "$SRC/$f" "$ACCT/"; fi
done
echo "build-jbase: staged curl as $ACCT/"
