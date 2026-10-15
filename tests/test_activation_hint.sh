#!/usr/bin/env bash
# After a 'get' without --use, make the active version unambiguous: what you
# just installed is not on your PATH until you 'use' it. Covers both exit
# paths out of cmd_get (fresh install and the already-installed early return).
set -u
. "$(dirname "$0")/lib.sh"

if ! curl -fsSL "file://$OCP" -o /dev/null 2>/dev/null; then
  echo "SKIP: this curl lacks file:// support; skipping activation-hint tests" >&2
  finish
  exit
fi

sha256f() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

mk_version() {  # <dir> <version>
  local d="$1" v="$2" b="$TESTDIR/build-$2"
  mkdir -p "$d" "$b"
  printf 'Name: %s\n' "$v" > "$d/release.txt"
  printf '#!/bin/sh\nexit 0\n' > "$b/oc";      chmod +x "$b/oc"
  printf '#!/bin/sh\nexit 0\n' > "$b/kubectl"; chmod +x "$b/kubectl"
  ( cd "$b" && tar -czf "$d/openshift-client-linux-$v.tar.gz" oc kubectl )
  ( cd "$d" && sha256f "openshift-client-linux-$v.tar.gz" > sha256sum.txt )
}

MIR="$TESTDIR/mirror/x86_64/clients/ocp"
mk_version "$MIR/4.90.1" 4.90.1
mk_version "$MIR/4.90.2" 4.90.2

export OCP_BASE_URL="file://$MIR"
export OCP_BIN_DIR="$TESTDIR/bin-dir"; mkdir -p "$OCP_BIN_DIR"
export OCP_PLATFORM=linux

echo "=== nothing active yet: plain activation hint ==="
out="$("$OCP" get 4.90.1 2>&1)"
assert_re "Run 'ocp use 4\.90\.1' to activate it\." "$out" "tells you to activate the first install"
assert_no_re 'still the active version' "$out" "no stale-active note when nothing is active"

echo "=== a different version is active: name it and offer the switch ==="
"$OCP" use 4.90.1 >/dev/null 2>&1
out="$("$OCP" get 4.90.2 2>&1)"
assert_re 'Note: 4\.90\.1 is still the active version\.' "$out" "names the version that is still active"
assert_re "Run 'ocp use 4\.90\.2' to switch\."           "$out" "offers the switch to what was installed"
assert_eq "oc-4.90.1" "$(readlink "$OCP_BIN_DIR/oc")"    "get without --use does not move the symlink"

echo "=== already-installed early return warns too ==="
out="$("$OCP" get 4.90.2 2>&1)"
assert_re 'already installed'                            "$out" "still reports the no-op"
assert_re 'Note: 4\.90\.1 is still the active version\.' "$out" "no-op path names the active version"
assert_re "Run 'ocp use 4\.90\.2' to switch\."           "$out" "no-op path offers the switch"

echo "=== re-get of the already-active version says so ==="
"$OCP" use 4.90.2 >/dev/null 2>&1
out="$("$OCP" get 4.90.2 2>&1)"
assert_re '4\.90\.2 is already the active version\.' "$out" "reports it is already active"
assert_no_re "Run 'ocp use"   "$out" "no pointless use suggestion"
assert_no_re 'still the active' "$out" "no stale-active note"

echo "=== --use activates, so no reminder ==="
out="$("$OCP" get --use 4.90.1 2>&1)"
assert_re 'Now using OCP 4\.90\.1' "$out" "--use activates"
assert_no_re 'still the active'    "$out" "no reminder when --use did the work"
assert_eq "oc-4.90.1" "$(readlink "$OCP_BIN_DIR/oc")" "--use moved the symlink"

finish
