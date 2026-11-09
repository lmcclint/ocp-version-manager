#!/usr/bin/env bash
# oc/kubectl plugins (oc-<name>, kubectl-<name>) commonly share BIN_DIR with
# ocp's versioned binaries. They must never be treated as versions: not listed,
# not activated, and above all not deleted by 'remove'.
set -u
. "$(dirname "$0")/lib.sh"

export OCP_BIN_DIR="$TESTDIR/bin-dir"
mkdir -p "$OCP_BIN_DIR"

for b in oc kubectl; do stub "$OCP_BIN_DIR/$b-4.18.1"; done
stub "$OCP_BIN_DIR/oc-5.0.0-ec.3"              # pre-release still counts
stub "$OCP_BIN_DIR/kubectl-neat"
stub "$OCP_BIN_DIR/oc-login-helper"

echo "=== list ignores plugins ==="
out="$("$OCP" list 2>&1)"
assert_re '4\.18\.1' "$out" "real version listed"
assert_re '5\.0\.0-ec\.3' "$out" "pre-release version listed"
assert_missing 'neat' "$out" "kubectl plugin not listed"
assert_missing 'login-helper' "$out" "oc plugin not listed"

echo "=== remove refuses a plugin name ==="
err="$("$OCP" remove neat 2>&1)"; rc=$?
assert_eq 1 "$rc" "remove of a plugin name fails"
assert_re 'not a version' "$err" "remove explains why"
[ -e "$OCP_BIN_DIR/kubectl-neat" ] && ok "kubectl-neat survives" || bad "kubectl-neat was deleted"

echo "=== use refuses a plugin name ==="
err="$("$OCP" use neat 2>&1)"; rc=$?
assert_eq 1 "$rc" "use of a plugin name fails"
[ -e "$OCP_BIN_DIR/kubectl" ] && bad "kubectl linked to a plugin" || ok "kubectl not linked"

echo "=== a foreign bare symlink is not an active version ==="
# 'get' of an installed version takes the early-return path, which only needs
# release.txt from the mirror and then prints the activation hint.
if curl -fsSL "file://$OCP" -o /dev/null 2>/dev/null; then
  mkdir -p "$TESTDIR/mirror/4.18.1"
  printf 'Name: 4.18.1\n' > "$TESTDIR/mirror/4.18.1/release.txt"
  ln -s /opt/tools/oc-wrapper "$OCP_BIN_DIR/oc"
  out="$(OCP_BASE_URL="file://$TESTDIR/mirror" OCP_PLATFORM=linux "$OCP" get 4.18.1 2>&1)"
  assert_no_re 'wrapper' "$out" "foreign symlink target not reported as a version"
  assert_re "Run 'ocp use 4\.18\.1' to activate it" "$out" "treated as nothing active"
else
  echo "SKIP: this curl lacks file:// support" >&2
fi

finish
