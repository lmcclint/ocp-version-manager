#!/usr/bin/env bash
# get flag validation, 'use' with partial installs, and 'list' annotation.
# All offline: flag errors happen before any network call, and use/list only
# touch the local OCP_BIN_DIR (stubbed binaries).
set -u
. "$(dirname "$0")/lib.sh"

export OCP_BIN_DIR="$TESTDIR/bin-dir"
mkdir -p "$OCP_BIN_DIR"

echo "=== get: flag validation (no network) ==="
err="$("$OCP" get --cli-only --installer-only 4.14.1 2>&1)"; assert_re 'mutually exclusive' "$err" "mutually exclusive flags rejected"
err="$("$OCP" get --bogus 4.14.1 2>&1)";                     assert_re 'unknown flag: --bogus' "$err" "unknown flag rejected"
err="$("$OCP" get 2>&1)";                                    assert_re 'usage: ocp get' "$err" "missing ref rejected"
err="$("$OCP" get 4.14.1 4.15.0 2>&1)";                      assert_re 'unexpected argument: 4.15.0' "$err" "extra positional rejected"

echo "=== list: empty ==="
out="$("$OCP" list 2>&1)"; assert_re 'no versions installed' "$out" "empty list message"

echo "=== stub a full + two partial installs ==="
for b in openshift-install oc kubectl; do stub "$OCP_BIN_DIR/$b-4.14.1"; done   # full
for b in oc kubectl; do stub "$OCP_BIN_DIR/$b-4.15.0"; done                     # cli-only
stub "$OCP_BIN_DIR/openshift-install-4.16.0"                                     # installer-only

out="$("$OCP" list 2>&1)"
assert_contains "4.14.1  (installer, oc, kubectl)" "$out" "full install annotated"
assert_contains "4.15.0  (oc, kubectl)"            "$out" "cli-only annotated"
assert_contains "4.16.0  (installer)"              "$out" "installer-only annotated"

echo "=== use cli-only version: installer symlink unset + warned ==="
out="$("$OCP" use 4.15.0 2>&1)"
assert_re "warning: openshift-install not installed for 4.15.0" "$out" "warns missing installer"
[ -L "$OCP_BIN_DIR/oc" ] && ok "oc symlink created" || bad "oc symlink missing"
[ -e "$OCP_BIN_DIR/openshift-install" ] && bad "openshift-install should be unset" || ok "openshift-install symlink unset"
assert_eq "oc-4.15.0" "$(readlink "$OCP_BIN_DIR/oc")" "oc symlink is relative"

echo "=== active-version falls back to oc (cli-only active) ==="
out="$("$OCP" list 2>&1)"; assert_re '^\* 4\.15\.0' "$out" "active marker on cli-only version"

echo "=== use full version: installer symlink restored ==="
"$OCP" use 4.14.1 >/dev/null 2>&1
[ -L "$OCP_BIN_DIR/openshift-install" ] && ok "openshift-install relinked" || bad "openshift-install not relinked"

echo "=== use nonexistent version errors ==="
err="$("$OCP" use 9.9.9 2>&1)"; assert_re '9.9.9 not installed' "$err" "use missing version errors"

echo "=== exit codes are 0 for non-downloading commands ==="
"$OCP" --version >/dev/null 2>&1; assert_eq 0 "$?" "--version exits 0"
"$OCP" list      >/dev/null 2>&1; assert_eq 0 "$?" "list exits 0"
"$OCP" --help    >/dev/null 2>&1; assert_eq 0 "$?" "--help exits 0"

finish
