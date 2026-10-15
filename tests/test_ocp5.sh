#!/usr/bin/env bash
# OCP 5.x support: short-version channel fallback (stable -> fast -> candidate)
# for minors that have not shipped a stable channel yet, and releases that
# publish no oc-mirror. Driven by a local file:// mirror, so no network.
set -u
. "$(dirname "$0")/lib.sh"

if ! curl -fsSL "file://$OCP" -o /dev/null 2>/dev/null; then
  echo "SKIP: this curl lacks file:// support; skipping ocp5 tests" >&2
  finish
  exit
fi

sha256f() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# Build a channel dir holding the client tarball for <version>, plus a
# sha256sum.txt with no oc-mirror entry (as the 5.0 pre-releases ship).
mk_channel() {  # <dir> <version>
  local d="$1" v="$2" b="$TESTDIR/build-$2"
  mkdir -p "$d" "$b"
  printf 'Name: %s\n' "$v" > "$d/release.txt"
  printf '#!/bin/sh\nexit 0\n' > "$b/oc";      chmod +x "$b/oc"
  printf '#!/bin/sh\nexit 0\n' > "$b/kubectl"; chmod +x "$b/kubectl"
  ( cd "$b" && tar -czf "$d/openshift-client-linux-$v.tar.gz" oc kubectl )
  ( cd "$d" && sha256f "openshift-client-linux-$v.tar.gz" > sha256sum.txt )
}

MIR="$TESTDIR/mirror/x86_64/clients/ocp"
mk_channel "$MIR/candidate-5.0"  5.0.0-rc.6   # pre-GA minor: candidate only
mk_channel "$MIR/fast-4.99"      4.99.1       # fast but no stable
mk_channel "$MIR/stable-4.98"    4.98.1       # stable wins over candidate
mk_channel "$MIR/candidate-4.98" 4.98.2

export OCP_BASE_URL="file://$MIR"
export OCP_BIN_DIR="$TESTDIR/bin-dir"; mkdir -p "$OCP_BIN_DIR"
export OCP_PLATFORM=linux

echo "=== 5.0 falls back to candidate when stable and fast are absent ==="
out="$("$OCP" get 5.0 2>&1)"
assert_re 'no stable-5\.0'                      "$out" "reports the missing stable channel"
assert_re 'Falling back to candidate-5\.0'      "$out" "falls back to candidate-5.0"
assert_re "Resolved 'candidate-5\.0' -> 5\.0\.0-rc\.6" "$out" "resolves the candidate version"
[ -x "$OCP_BIN_DIR/oc-5.0.0-rc.6" ] && ok "installed oc-5.0.0-rc.6" || bad "oc-5.0.0-rc.6 missing"

echo "=== fast is preferred over candidate ==="
out="$("$OCP" get 4.99 2>&1)"
assert_re 'Falling back to fast-4\.99' "$out" "falls back to fast before candidate"
assert_re '\-> 4\.99\.1'               "$out" "resolved the fast version"

echo "=== stable still wins when it exists ==="
out="$("$OCP" get 4.98 2>&1)"
assert_re 'resolving via stable-4\.98' "$out" "prefers stable"
assert_no_re 'Falling back'            "$out" "no fallback message when stable exists"
assert_re '\-> 4\.98\.1'               "$out" "resolved stable, not candidate"

echo "=== a minor with no channels at all fails clearly ==="
out="$("$OCP" get 9.9 2>&1)" && rc=0 || rc=$?
assert_eq 1 "$rc" "unknown minor exits non-zero"
assert_re "no stable/fast/candidate channel for '9\.9'" "$out" "clear error for an unknown minor"

echo "=== exact 5.x versions need no channel probing ==="
"$OCP" remove 5.0.0-rc.6 >/dev/null 2>&1
out="$(OCP_BASE_URL="file://$MIR/candidate-5.0/.." "$OCP" get candidate-5.0 2>&1)"
assert_no_re 'Short version' "$out" "a channel argument is not expanded"

echo "=== --with-mirror on a release that ships no oc-mirror ==="
"$OCP" remove 5.0.0-rc.6 >/dev/null 2>&1
out="$("$OCP" get --with-mirror 5.0 2>&1)"; rc=$?
assert_eq 0 "$rc" "get --with-mirror still succeeds"
assert_re 'oc-mirror is not published for 5\.0\.0-rc\.6' "$out" "says oc-mirror is unavailable"
assert_no_re 'failed to download'                        "$out" "no blind 404 download"
[ -x "$OCP_BIN_DIR/oc-5.0.0-rc.6" ]     && ok "CLI still installed"      || bad "CLI missing"
[ -e "$OCP_BIN_DIR/oc-mirror-5.0.0-rc.6" ] && bad "oc-mirror should not be installed" || ok "no oc-mirror installed"

echo "=== --mirror-only on a release that ships no oc-mirror fails ==="
"$OCP" remove 5.0.0-rc.6 >/dev/null 2>&1
out="$("$OCP" get --mirror-only 5.0 2>&1)" && rc=0 || rc=$?
assert_eq 1 "$rc" "--mirror-only exits non-zero when nothing can be installed"
assert_re 'oc-mirror is not published' "$out" "--mirror-only explains why"

finish
