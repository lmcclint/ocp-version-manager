#!/usr/bin/env bash
# Shared helpers for the ocp test suite. Sourced by each test_*.sh.
#
# Provides: OCP (path to the script under test), a per-test temp dir, and a
# handful of assertion helpers that track pass/fail counts. Each test file
# calls 'finish' at the end to print results and set the exit status.

# Locate the ocp script: $OCP env override, else the repo root next to tests/.
: "${OCP:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ocp}"
[ -x "$OCP" ] || { echo "cannot find executable ocp at: $OCP" >&2; exit 2; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "$TESTDIR"' EXIT

_pass=0
_fail=0

ok()   { echo "PASS: $1"; _pass=$((_pass+1)); }
bad()  { echo "FAIL: $1"; _fail=$((_fail+1)); }

# assert_contains <needle> <haystack> <desc>  (substring match)
assert_contains() { case "$2" in *"$1"*) ok "$3" ;; *) bad "$3 (missing '$1')"; printf '%s\n' "$2" | sed 's/^/    /' ;; esac; }
# assert_missing <needle> <haystack> <desc>
assert_missing()  { case "$2" in *"$1"*) bad "$3 (unexpected '$1')"; printf '%s\n' "$2" | sed 's/^/    /' ;; *) ok "$3" ;; esac; }
# assert_re <ere> <haystack> <desc>
assert_re()       { if printf '%s\n' "$2" | grep -qE "$1"; then ok "$3"; else bad "$3 (no match /$1/)"; printf '%s\n' "$2" | sed 's/^/    /'; fi; }
# assert_no_re <ere> <haystack> <desc>
assert_no_re()    { if printf '%s\n' "$2" | grep -qE "$1"; then bad "$3 (unexpected /$1/)"; printf '%s\n' "$2" | sed 's/^/    /'; else ok "$3"; fi; }
# assert_eq <expected> <actual> <desc>
assert_eq()       { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$1', got '$2')"; fi; }

finish() {
  echo
  echo "RESULTS: pass=$_pass fail=$_fail"
  [ "$_fail" -eq 0 ]
}

# Install a fake 'curl' on PATH from a heredoc body passed on stdin.
# The body is a bash script that may inspect "${@: -1}" (the URL/last arg).
fake_curl() {
  mkdir -p "$TESTDIR/bin"
  { echo '#!/usr/bin/env bash'; cat; } > "$TESTDIR/bin/curl"
  chmod +x "$TESTDIR/bin/curl"
  PATH="$TESTDIR/bin:$PATH"
  export PATH
}

# Create an executable stub binary at $1 (used to fake installed components).
stub() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n' > "$1"; chmod +x "$1"; }
