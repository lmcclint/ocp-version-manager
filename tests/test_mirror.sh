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

finish
