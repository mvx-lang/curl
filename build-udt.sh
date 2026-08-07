#!/bin/sh
# build-udt.sh — build the curl CallC object + stage the udt package into $1.
# Compiles the libcurl CallC binding (mvxcurl.c -DMVXCURL_UDT) into
# udt-callc/curlcallcb.o, which udt-callc-build folds into libu2callc.so on
# install; the BASIC HTTPGET/HTTPGETFILE verbs CALLC CURLGET/CURLGETFILE.
# Needs gcc + curl.h (libcurl-devel).  GPL-2.0-only.
set -e
STAGE="${1:?usage: build-udt.sh <stagedir>}"
SRC="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-cc}"
mkdir -p "$STAGE/BP" "$STAGE/udt-callc"
"$CC" -m64 -fPIC -O2 -DMVXCURL_UDT -c "$SRC/src/mvxcurl.c" -o "$STAGE/udt-callc/curlcallcb.o"
cp "$SRC/udt/HTTPGET"     "$STAGE/BP/HTTPGET"
cp "$SRC/udt/HTTPGETFILE" "$STAGE/BP/HTTPGETFILE"
cp "$SRC/udt-callc/funcs" "$SRC/udt-callc/libs" "$STAGE/udt-callc/"
cp "$SRC/PKG" "$SRC/mvpkg.json" "$SRC/LICENSE" "$STAGE/" 2>/dev/null || true
echo "build-udt: staged the curl udt package (CallC libcurl)"
