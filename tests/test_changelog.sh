#!/usr/bin/env bash
# Release notes on 'ocp update'. Offline: the script and CHANGELOG.md are served
# from local files via curl's file:// support (no network).
set -u
. "$(dirname "$0")/lib.sh"

# Private copy we can let overwrite itself.
mkdir -p "$TESTDIR/bin"
cp "$OCP" "$TESTDIR/bin/ocp"; chmod +x "$TESTDIR/bin/ocp"
SUT="$TESTDIR/bin/ocp"
cur="$("$SUT" --version 2>&1 | awk '{print $2}')"

if ! curl -fsSL "file://$SUT" -o /dev/null 2>/dev/null; then
  echo "SKIP: this curl lacks file:// support; skipping changelog tests" >&2
  finish; exit
fi

# A newer script (9.9.9) and a changelog spanning old->new plus an ancient entry.
sed "s/^VERSION=\"$cur\"/VERSION=\"9.9.9\"/" "$SUT" > "$TESTDIR/newer"
cat > "$TESTDIR/CHANGELOG.md" <<'EOF'
# Changelog

## 9.9.9
- top feature

## 9.9.8
- middle feature

## 0.0.1
- ancient feature
EOF

echo "=== update prints notes in the (old, new] range ==="
out="$(OCP_UPDATE_URL="file://$TESTDIR/newer" \
       OCP_CHANGELOG_URL="file://$TESTDIR/CHANGELOG.md" \
       "$SUT" update 2>&1)"
assert_contains "Changes in this update:" "$out" "prints a notes header"
assert_contains "top feature"   "$out" "includes the new version's notes"
assert_contains "middle feature" "$out" "includes an intermediate version's notes"
assert_missing  "ancient feature" "$out" "excludes versions <= the old one"
assert_re "Updated ocp: $cur -> 9\.9\.9" "$out" "still reports the version swap"

echo "=== no notes when already up to date ==="
cp "$OCP" "$SUT"; chmod +x "$SUT"   # restore current version
out="$(OCP_UPDATE_URL="file://$SUT" \
       OCP_CHANGELOG_URL="file://$TESTDIR/CHANGELOG.md" \
       "$SUT" update 2>&1)"
assert_re "Already up to date" "$out" "no-op reports up to date"
assert_missing "Changes in this update:" "$out" "no notes header on a no-op"

echo "=== missing changelog degrades gracefully, update still succeeds ==="
cp "$OCP" "$SUT"; chmod +x "$SUT"   # restore current version
out="$(OCP_UPDATE_URL="file://$TESTDIR/newer" \
       OCP_CHANGELOG_URL="file://$TESTDIR/does-not-exist.md" \
       "$SUT" update 2>&1)"
assert_contains "release notes unavailable" "$out" "warns when changelog missing"
assert_re "Updated ocp: $cur -> 9\.9\.9" "$out" "update still completes"

finish
