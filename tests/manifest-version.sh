#!/bin/sh
# curl — assert the in-tree manifests agree with each other.
# Copyright (C) 2026 Gordon Heydon.  GPL-2.0-only (see LICENSE).
#
#   sh tests/manifest-version.sh <version>
#
# WHAT THIS CHECKS.  The two manifests AGREE -- with each other on the version,
# on the systems list, and on the C library this package loads.  It does NOT
# police the version against the tag: the tag is stamped into every staged
# artifact instead (mvx#363), so the in-tree version is derived, not
# authoritative.
#
# WHICH IS WHY BOTH MANIFESTS SAY 0.0.0-dev (#23).  A number committed there can
# only be stale or coincidentally right -- this repo's said 1.3.0 while 1.4.0
# was the published release -- so the committed value says "this is not the
# answer, ask the tag".  Do not bump it; nothing reads it.
#
# WHY IT EXISTS AT ALL.  json#38 shipped PKG declaring a system mvpkg.json had
# dropped: both files travel in every artifact, nothing resolves against PKG's
# copy, and that is exactly why the disagreement survived a release.  Stamping
# cannot catch it -- it writes one version into both files and so cannot notice
# they disagreed about anything else.
set -eu
WANT="${1:?usage: manifest-version.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rc=0

# A rolling dev tag is not a version and is not expected to match.
case "$WANT" in
  dev|latest) printf 'manifest-version: %s is not a version tag - skipped\n' "$WANT"; exit 0 ;;
esac

got=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/mvpkg.json" | head -1)
if [ "$got" = "$WANT" ]; then
  printf '  ok   mvpkg.json version is %s\n' "$WANT"
else
  printf '  FAIL mvpkg.json says "%s", not "%s"\n' "$got" "$WANT"; rc=1
fi

# PKG is a line-oriented manifest: 1 name, 2 version, 3 description, 4 systems,
# 5 dependencies.
got=$(sed -n '2p' "$ROOT/PKG" | tr -d ' \r')
if [ "$got" = "$WANT" ]; then
  printf '  ok   PKG line 2 is %s\n' "$WANT"
else
  printf '  FAIL PKG line 2 says "%s", not "%s"\n' "$got" "$WANT"; rc=1
fi

sysline=$(sed -n '4p' "$ROOT/PKG" | tr -s ' \r' ' ' | sed 's/^ *//;s/ *$//')
sysjson=$(sed -n '/"systems"/,/]/p' "$ROOT/mvpkg.json" \
          | sed -n 's/.*"\([a-z0-9_]*\)".*/\1/p' | grep -v '^systems$' | tr '\n' ' ' \
          | sed 's/ *$//')
if [ "$sysline" = "$sysjson" ]; then
  printf '  ok   both manifests declare the systems "%s"\n' "$sysline"
else
  printf '  FAIL PKG line 4 says "%s", mvpkg.json says "%s"\n' "$sysline" "$sysjson"; rc=1
fi

# AND THE C LIBRARY, which is this package's whole reason to exist and is named
# in two places that nothing keeps in step.  mvpkg.json's "clibs" is what MVPKG
# checks for before it installs; udt-callc/libs is what the UniData CallC link
# actually passes.  Disagree, and MVPKG either refuses an install that would
# have worked or allows one that cannot link.
for lib in $(sed -n '/"clibs"/,/]/p' "$ROOT/mvpkg.json" \
             | sed -n 's/.*"\(lib[^"]*\)".*/\1/p'); do
  if grep -q -- "$lib" "$ROOT/udt-callc/libs"; then
    printf '  ok   udt-callc/libs links the %s that mvpkg.json declares\n' "$lib"
  else
    printf '  FAIL mvpkg.json "clibs" names %s, which udt-callc/libs does not link\n' "$lib"
    rc=1
  fi
done

if [ "$rc" -ne 0 ]; then
  printf 'manifests: make the two manifests agree on %s\n' "$WANT" >&2
fi
exit "$rc"
