#!/usr/bin/env bash
# oc-mirror as an optional fourth component: list/remove/use plumbing (stub-based,
# offline) and end-to-end get/fetch via a local file:// mirror.
set -u
. "$(dirname "$0")/lib.sh"

export OCP_BIN_DIR="$TESTDIR/bin-dir"
mkdir -p "$OCP_BIN_DIR"

echo "=== list/installed_components include oc-mirror ==="
for b in openshift-install oc kubectl oc-mirror; do stub "$OCP_BIN_DIR/$b-4.18.10"; done  # full + mirror
stub "$OCP_BIN_DIR/oc-mirror-4.17.0"                                                       # mirror-only

out="$("$OCP" list 2>&1)"
assert_contains "4.18.10  (installer, oc, kubectl, oc-mirror)" "$out" "full+mirror annotated"
assert_contains "4.17.0  (oc-mirror)"                          "$out" "mirror-only annotated"
# The 'oc-*' glob must not mis-read oc-mirror-* as an 'oc' version named 'mirror-...'.
assert_no_re 'mirror-4\.18\.10' "$out" "oc glob does not swallow oc-mirror files"

echo "=== active_version detects a mirror-only active version ==="
( cd "$OCP_BIN_DIR" && ln -sf oc-mirror-4.17.0 oc-mirror )
out="$("$OCP" list 2>&1)"; assert_re '^\* 4\.17\.0' "$out" "active marker on mirror-only version"
( cd "$OCP_BIN_DIR" && rm -f oc-mirror )

echo "=== remove deletes oc-mirror too ==="
"$OCP" remove 4.17.0 >/dev/null 2>&1
[ -e "$OCP_BIN_DIR/oc-mirror-4.17.0" ] && bad "oc-mirror-4.17.0 not removed" || ok "oc-mirror-4.17.0 removed"
out="$("$OCP" remove 4.18.10 2>&1)"
[ -e "$OCP_BIN_DIR/oc-mirror-4.18.10" ] && bad "oc-mirror-4.18.10 not removed" || ok "oc-mirror-4.18.10 removed"

echo "=== use links oc-mirror when present ==="
for b in openshift-install oc kubectl oc-mirror; do stub "$OCP_BIN_DIR/$b-4.18.11"; done
out="$("$OCP" use 4.18.11 2>&1)"
[ -L "$OCP_BIN_DIR/oc-mirror" ] && ok "oc-mirror symlink created" || bad "oc-mirror symlink missing"
assert_eq "oc-mirror-4.18.11" "$(readlink "$OCP_BIN_DIR/oc-mirror")" "oc-mirror symlink is relative"

echo "=== use a version without oc-mirror: no warning, bare oc-mirror unset ==="
for b in openshift-install oc kubectl; do stub "$OCP_BIN_DIR/$b-4.18.12"; done   # no oc-mirror
out="$("$OCP" use 4.18.12 2>&1)"
rc=$?; assert_eq 0 "$rc" "use without oc-mirror exits 0"
assert_re 'Now using OCP 4.18.12' "$out" "use without oc-mirror still reports success"
assert_no_re 'oc-mirror' "$out" "no oc-mirror warning for versions without it"
[ -e "$OCP_BIN_DIR/oc-mirror" ] && bad "stale oc-mirror symlink left" || ok "oc-mirror symlink cleared"

echo "=== use a mirror-only install works (no error) ==="
stub "$OCP_BIN_DIR/oc-mirror-4.18.13"
"$OCP" use 4.18.13 >/dev/null 2>&1; assert_eq 0 "$?" "use mirror-only exits 0"
assert_eq "oc-mirror-4.18.13" "$(readlink "$OCP_BIN_DIR/oc-mirror")" "mirror-only use links oc-mirror"

finish
