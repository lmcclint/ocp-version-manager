#!/usr/bin/env bash
# list-versions (and its list-remote alias) and list-channels.
set -u
. "$(dirname "$0")/lib.sh"

fake_curl <<'CURL'
url="${@: -1}"
case "$url" in
  */candidate-4.20/release.txt) echo "Name: 4.20.25" ;;
  */fast-4.20/release.txt)      echo "Name: 4.20.25" ;;
  */latest-4.20/release.txt)    echo "Name: 4.20.25" ;;
  */stable-4.20/release.txt)    echo "Name: 4.20.24" ;;
  */release.txt)                exit 22 ;;   # unknown channel -> like a 404
  *)
    cat <<'HTML'
<a href="../">../</a>
<a href="stable/">stable/</a>
<a href="latest/">latest/</a>
<a href="candidate/">candidate/</a>
<a href="fast/">fast/</a>
<a href="4.2.0/">4.2.0/</a>
<a href="4.4.20/">4.4.20/</a>
<a href="4.14.20/">4.14.20/</a>
<a href="4.20.0/">4.20.0/</a>
<a href="4.20.0-rc.0/">4.20.0-rc.0/</a>
<a href="4.20.1/">4.20.1/</a>
<a href="4.20.10/">4.20.10/</a>
<a href="stable-4.2/">stable-4.2/</a>
<a href="stable-4.20/">stable-4.20/</a>
<a href="fast-4.20/">fast-4.20/</a>
<a href="candidate-4.20/">candidate-4.20/</a>
<a href="latest-4.20/">latest-4.20/</a>
<a href="candidate-4.21/">candidate-4.21/</a>
HTML
  ;;
esac
CURL

# Isolate from the real ~/.local/bin so 'installed:' annotations are controlled.
export OCP_BIN_DIR="$TESTDIR/bin-dir"
mkdir -p "$OCP_BIN_DIR"

echo "=== list-versions: channel filter reduces to its X.Y line ==="
out="$("$OCP" list-versions stable-4.20 2>/dev/null)"
assert_re '^4\.20\.0$'  "$out" "lists 4.20.0"
assert_re '^4\.20\.10$' "$out" "lists 4.20.10"
assert_no_re '^4\.2\.0$' "$out" "excludes 4.2.0"

echo "=== list-versions: X.Y boundary ==="
out="$("$OCP" list-versions 4.2 2>/dev/null)"
assert_re '^4\.2\.0$' "$out" "4.2 includes 4.2.0"
assert_no_re '^4\.20\.' "$out" "4.2 excludes 4.20.x"

echo "=== list-versions: exact version boundary ==="
out="$("$OCP" list-versions 4.20.1 2>/dev/null)"
assert_re '^4\.20\.1$' "$out" "includes 4.20.1"
assert_no_re '^4\.20\.10$' "$out" "excludes 4.20.10"

echo "=== list-remote alias still works ==="
out="$("$OCP" list-remote 4.20 2>/dev/null)"
assert_re '^4\.20\.1$' "$out" "alias lists 4.20.1"

echo "=== list-versions: graceful no-match ==="
out="$("$OCP" list-versions 9.99 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "exit 0 on no match"
assert_eq "" "$out" "no stdout on no match"
err="$("$OCP" list-versions 9.99 2>&1 >/dev/null)"
assert_re "no versions on the mirror match '9.99'" "$err" "no-match message"

echo "=== list-channels <X.Y>: channels + resolved versions ==="
out="$("$OCP" list-channels 4.20 2>/dev/null)"
assert_re '^candidate-4\.20[[:space:]]+4\.20\.25$' "$out" "candidate-4.20 -> 4.20.25"
assert_re '^fast-4\.20[[:space:]]+4\.20\.25$'      "$out" "fast-4.20 -> 4.20.25"
assert_re '^latest-4\.20[[:space:]]+4\.20\.25$'    "$out" "latest-4.20 -> 4.20.25"
assert_re '^stable-4\.20[[:space:]]+4\.20\.24$'    "$out" "stable-4.20 -> 4.20.24"
assert_no_re '^stable-4\.2[[:space:]]' "$out" "excludes stable-4.2 (boundary)"
assert_no_re '^candidate-4\.21'        "$out" "excludes other minors"
assert_no_re '^(stable|latest|fast|candidate)[[:space:]]' "$out" "excludes bare channels"

echo "=== list-channels: accepts a full channel name ==="
out="$("$OCP" list-channels stable-4.20 2>/dev/null)"
assert_re '^stable-4\.20[[:space:]]+4\.20\.24$' "$out" "stable-4.20 arg -> the 4.20 channels"

echo "=== list-channels: requires an argument ==="
err="$("$OCP" list-channels 2>&1 >/dev/null)"; rc=$?
[ "$rc" -ne 0 ] && ok "nonzero exit without arg" || bad "expected nonzero exit"
assert_re 'usage: ocp list-channels' "$err" "usage message shown"

echo "=== list-channels: graceful no-match ==="
out="$("$OCP" list-channels 9.99 2>/dev/null)"; rc=$?
assert_eq 0 "$rc" "exit 0 on no match"
err="$("$OCP" list-channels 9.99 2>&1 >/dev/null)"
assert_re "no channels on the mirror match '9.99'" "$err" "no-match message"

echo "=== installed annotation reflects local components ==="
stub "$OCP_BIN_DIR/oc-4.20.1"; stub "$OCP_BIN_DIR/kubectl-4.20.1"          # cli-only
for b in openshift-install oc kubectl; do stub "$OCP_BIN_DIR/$b-4.20.24"; done  # full (stable-4.20 target)

out="$("$OCP" list-versions 4.20 2>/dev/null)"
assert_re '^4\.20\.1  \(installed: oc, kubectl\)$' "$out" "list-versions annotates partial install"
assert_re '^4\.20\.0$' "$out" "list-versions leaves uninstalled versions plain"

out="$("$OCP" list-channels 4.20 2>/dev/null)"
assert_re '^stable-4\.20[[:space:]]+4\.20\.24[[:space:]]+\(installed: installer, oc, kubectl\)$' "$out" "list-channels annotates installed channel target"
assert_no_re 'candidate-4\.20.*installed' "$out" "list-channels leaves uninstalled targets plain"

finish
