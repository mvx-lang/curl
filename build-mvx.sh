#!/bin/sh
# build-mvx.sh — build the curl native extension and stage the mvx package into $1.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
#
#   sh build-mvx.sh <stagedir>
#
# The sibling of build-udt.sh and build-jbase.sh, for MVX.  On MVX this package
# is a NATIVE EXTENSION AND NOTHING ELSE: there is no BP/ here, and VOC/ and
# CATALOG/ are empty, because HTTPGET/HTTPGETFILE/HTTPPOST are C functions the
# compiler resolves as expressions -- not verbs, not BASIC subroutines.  So the
# whole build is "compile src/mvxcurl.c into LIB/", which is mkpkg's job.
#
# MKPKG DOES THE COMPILING, NOT THIS SCRIPT.  It reads NATIVE (the sources and
# their libcurl flags) and writes LIB/libmvxext_curl.<so|dylib>.  Duplicating
# that here would mean keeping a second copy of the flag handling in step with
# mvx's -- including the `libs:' fallback that exists because pkg-config has no
# .pc for libcurl on macOS (mvx#201).
#
# AND MKPKG IS NOT INSTALLED WITH THE TOOLCHAIN.  `cmake --install' ships bin/,
# lib/, include/ and the system account; scripts/ stays in the source tree.  So
# point $MVX_SRC at an mvx checkout -- the default is ../.. , which is right
# when this package sits in mvx's own packages/ directory and wrong everywhere
# else, so CI must say.  (mv_git's release job does the same thing, from
# .mvx-src.)  $MVXBASIC, if set, is passed through for the compiler itself.
set -e
STAGE="${1:?usage: build-mvx.sh <stagedir>}"
SRC="$(cd "$(dirname "$0")" && pwd)"
MVX_SRC="${MVX_SRC:-$(cd "$SRC/../.." 2>/dev/null && pwd)}"
MKPKG="$MVX_SRC/scripts/mkpkg.sh"
[ -f "$MKPKG" ] || {
   echo "build-mvx: no mkpkg.sh at $MKPKG" >&2
   echo "  Set MVX_SRC to an mvx source checkout: the toolchain install does" >&2
   echo "  not carry scripts/, only bin/ lib/ include/ and share/mvx." >&2
   exit 1; }

# .so or .dylib -- the same test mkpkg makes, because the artifact is named
# after what it actually built and a wrong guess stages nothing.
case "$(uname)" in Darwin) EXT=dylib ;; *) EXT=so ;; esac

sh "$MKPKG" "$SRC"

# ASSERT THE LIBRARY, DO NOT ASSUME IT.  mkpkg reports a failed native build on
# stdout and carries on, so a package staged without checking is a tarball that
# installs cleanly and then cannot resolve a single function.
[ -f "$SRC/LIB/libmvxext_curl.$EXT" ] || {
   echo "build-mvx: mkpkg produced no LIB/libmvxext_curl.$EXT" >&2
   echo "  libcurl and its headers are the build dependency; on a system whose" >&2
   echo "  pkg-config has no libcurl.pc the NATIVE manifest's \`libs:' line is" >&2
   echo "  what supplies -lcurl (needs mvx with mvx#201)." >&2
   exit 1; }

mkdir -p "$STAGE/LIB"
cp "$SRC/LIB/libmvxext_curl.$EXT" "$STAGE/LIB/"

# EXPORTS TRAVELS, AND IT IS NOT OPTIONAL.  install-pkgs.sh concatenates a
# package's EXPORTS into the system account's aggregate, which is the file the
# COMPILER reads to know HTTPGET exists.  Ship the library without it and every
# program calling HTTPGET fails to compile against an installed toolchain,
# while the library sits there able to answer.
cp "$SRC/EXPORTS" "$STAGE/"

# NATIVE DELIBERATELY DOES NOT TRAVEL.  A prebuilt LIB/libmvxext_<name> with no
# NATIVE manifest is what mkpkg treats as binary-only and leaves alone; ship
# NATIVE without src/ and it would try to rebuild from sources that are not in
# the tarball.  Same reason src/ is not here.
for f in PKG mvpkg.json LICENSE README.md; do
   [ -f "$SRC/$f" ] && cp "$SRC/$f" "$STAGE/"
done

echo "build-mvx: staged the curl mvx package (libmvxext_curl.$EXT + EXPORTS) as $STAGE/"
