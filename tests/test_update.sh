#!/usr/bin/env bash
# Self-update ('ocp update') and version reporting. Offline: updates are served
# from local files via curl's file:// support (no network).
set -u
. "$(dirname "$0")/lib.sh"

# Work on a private copy so we can let it overwrite itself.
mkdir -p "$TESTDIR/bin"
cp "$OCP" "$TESTDIR/bin/ocp"; chmod +x "$TESTDIR/bin/ocp"
SUT="$TESTDIR/bin/ocp"
cur="$("$SUT" --version 2>&1 | awk '{print $2}')"

echo "=== --version / version ==="
assert_re "^ocp $cur\$" "$("$SUT" --version 2>&1)" "--version prints the embedded version"
assert_re "^ocp $cur\$" "$("$SUT" version 2>&1)"   "version subcommand matches"

if ! curl -fsSL "file://$SUT" -o /dev/null 2>/dev/null; then
  echo "SKIP: this curl lacks file:// support; skipping update tests" >&2
  finish; exit
fi

echo "=== update: no-op when versions match ==="
out="$(OCP_UPDATE_URL="file://$SUT" "$SUT" update 2>&1)"
assert_re "Already up to date \(version $cur\)" "$out" "no-op on matching version"

echo "=== update: newer version replaces in place ==="
sed "s/^VERSION=\"$cur\"/VERSION=\"9.9.9\"/" "$SUT" > "$TESTDIR/newer"
printf '# UPDATED-MARKER\n' >> "$TESTDIR/newer"
out="$(OCP_UPDATE_URL="file://$TESTDIR/newer" "$SUT" update 2>&1)"
assert_re "Updated ocp: $cur -> 9.9.9" "$out" "reports old -> new"
assert_re '^ocp 9\.9\.9$' "$("$SUT" --version 2>&1)" "installed copy now reports 9.9.9"
grep -q 'UPDATED-MARKER' "$SUT" && ok "file content swapped" || bad "content not swapped"
[ -x "$SUT" ] && ok "still executable" || bad "lost +x"
ls -a "$TESTDIR/bin" | grep -q '^\.ocp\.' && bad "staging temp left behind" || ok "no staging leftover"

echo "=== update: a non-script download is rejected, tool left intact ==="
cp "$OCP" "$SUT"; chmod +x "$SUT"   # restore current version
printf '<html>404</html>\n' > "$TESTDIR/bad.html"
out="$(OCP_UPDATE_URL="file://$TESTDIR/bad.html" "$SUT" update 2>&1)"
assert_re 'not a shell script' "$out" "rejects non-script download"
assert_re "^ocp $cur\$" "$("$SUT" --version 2>&1)" "tool intact after rejected update"

echo "=== update through a symlink updates the real file ==="
ln -s "$SUT" "$TESTDIR/ocp-link"
sed "s/^VERSION=\"$cur\"/VERSION=\"9.9.8\"/" "$SUT" > "$TESTDIR/newer2"
out="$(OCP_UPDATE_URL="file://$TESTDIR/newer2" "$TESTDIR/ocp-link" update 2>&1)"
assert_re "$cur -> 9.9.8" "$out" "update via symlink works"
[ -L "$TESTDIR/ocp-link" ] && ok "symlink preserved" || bad "symlink was replaced"
assert_re '^ocp 9\.9\.8$' "$("$SUT" --version 2>&1)" "real target updated"

finish
