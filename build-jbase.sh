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

# THE BUILDER IMAGE DOES NOT CARRY curl.h.  The udt builder does, so build-udt.sh
# can assume it; the jBASE image is built by hand on the runner from media that
# cannot be shipped, and there is no Dockerfile in git to add it to.  So the
# package brings its own build dependency rather than requiring an undocumented
# change to a hand-built image -- which would also be lost the next time that
# image is rebuilt.
#
# dnf's post-install scriptlet FAILS NOISILY here and does not matter: ldconfig
# trips over jBASE's own /opt/jbase/*/lib/libjrest.so.el, which is not an ELF
# file.  Thirteen complaints, exit 0, header installed.  Test for the header
# rather than trusting the exit status, so a real failure is still caught.
if [ ! -f /usr/include/curl/curl.h ]; then
   echo "build-jbase: curl.h absent — installing libcurl-devel"
   dnf -y install libcurl-devel >/dev/null 2>&1 || true
fi
[ -f /usr/include/curl/curl.h ] || {
   echo "build-jbase: curl.h still absent after installing libcurl-devel" >&2
   exit 1
}

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
