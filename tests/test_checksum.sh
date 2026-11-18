#!/usr/bin/env bash
# Checksum-mismatch policy for core tarballs: fatal by default, overridable
# with OCP_INSECURE=1, and tolerated on mac-arm64 (re-signed after publish).
set -u
. "$(dirname "$0")/lib.sh"

if ! curl -fsSL "file://$OCP" -o /dev/null 2>/dev/null; then
  echo "SKIP: this curl lacks file:// support; skipping checksum tests" >&2
  finish
  exit
fi

# A version dir whose sha256sum.txt lists a wrong hash for each platform's
# client tarball. Args: <dir> <version> <platform>...
mk_bad_version() {
  local d="$1" v="$2" b="$TESTDIR/build" p; shift 2
  mkdir -p "$d" "$b"
  printf 'Name: %s\n' "$v" > "$d/release.txt"
  printf '#!/bin/sh\n' > "$b/oc";      chmod +x "$b/oc"
  printf '#!/bin/sh\n' > "$b/kubectl"; chmod +x "$b/kubectl"
  : > "$d/sha256sum.txt"
  for p in "$@"; do
    ( cd "$b" && tar -czf "$d/openshift-client-$p-$v.tar.gz" oc kubectl )
    printf '%064d  openshift-client-%s-%s.tar.gz\n' 0 "$p" "$v" >> "$d/sha256sum.txt"
  done
}

MIR="$TESTDIR/mirror"
mk_bad_version "$MIR/4.90.1" 4.90.1 linux mac-arm64
export OCP_BASE_URL="file://$MIR"
export OCP_BIN_DIR="$TESTDIR/bin-dir"

echo "=== mismatch is fatal by default ==="
out="$(OCP_PLATFORM=linux "$OCP" get 4.90.1 2>&1)"; rc=$?
assert_eq 1 "$rc" "get fails on mismatch"
assert_re 'checksum verification failed .*OCP_INSECURE=1' "$out" "explains the override"
[ -e "$OCP_BIN_DIR/oc-4.90.1" ] && bad "nothing installed after mismatch" || ok "nothing installed after mismatch"

echo "=== OCP_INSECURE=1 continues ==="
out="$(OCP_PLATFORM=linux OCP_INSECURE=1 "$OCP" get 4.90.1 2>&1)"; rc=$?
assert_eq 0 "$rc" "get succeeds with OCP_INSECURE=1"
assert_re 'OCP_INSECURE=1 set; continuing' "$out" "says it is continuing"
rm -f "$OCP_BIN_DIR"/*-4.90.1

echo "=== mac-arm64 mismatch is tolerated ==="
out="$(OCP_PLATFORM=mac-arm64 "$OCP" get 4.90.1 2>&1)"; rc=$?
assert_eq 0 "$rc" "mac-arm64 get succeeds despite mismatch"
assert_re 'Apple Silicon binaries are re-signed' "$out" "explains the Apple Silicon exception"

finish
