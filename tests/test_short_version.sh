#!/usr/bin/env bash
# Short-version resolution: 'ocp get 4.18' expands to stable-4.18 channel.
set -u
. "$(dirname "$0")/lib.sh"

fake_curl <<'CURL'
url="${@: -1}"
case "$url" in
  */stable-4.18/release.txt) echo "Name: 4.18.7" ;;
  */stable-4.18/sha256sum.txt)
    sha256f() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
    sha256f "$TESTDIR/mirror/stable-4.18/openshift-client-linux-4.18.7.tar.gz"
    ;;
  */4.18/release.txt)         exit 22 ;;  # bare 4.18 dir doesn't exist on mirror
  */release.txt)              exit 22 ;;
  *) exit 22 ;;
esac
CURL

export OCP_BIN_DIR="$TESTDIR/bin-dir"
mkdir -p "$OCP_BIN_DIR"

echo "=== get with short version (X.Y) resolves via stable channel ==="
out="$("$OCP" get 4.18 2>&1)"; rc=$?
assert_re 'stable-4\.18' "$out" "mentions stable-4.18 in output"

echo "=== get with full version (X.Y.Z) does not expand ==="
out="$("$OCP" get 4.18.7 2>&1)"
assert_no_re 'Short version' "$out" "full version not expanded"

echo "=== get with channel name does not expand ==="
out="$("$OCP" get stable-4.18 2>&1)"
assert_no_re 'Short version' "$out" "channel name not expanded"

echo "=== get with short version shows hint about other channels ==="
out="$("$OCP" get 4.18 2>&1)"
assert_re 'fast-4\.18' "$out" "hints about fast channel"
assert_re 'candidate-4\.18' "$out" "hints about candidate channel"

finish
