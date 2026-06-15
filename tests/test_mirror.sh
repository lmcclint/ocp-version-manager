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

echo "=== get: oc-mirror flag conflicts (offline) ==="
err="$("$OCP" get --mirror-only --cli-only 4.18.10 2>&1)"
assert_re 'mirror-only' "$err" "--mirror-only + --cli-only rejected"
err="$("$OCP" get --mirror-only --installer-only 4.18.10 2>&1)"
assert_re 'mirror-only' "$err" "--mirror-only + --installer-only rejected"
err="$("$OCP" get --mirror-only --with-mirror 4.18.10 2>&1)"
assert_re 'mirror-only' "$err" "--mirror-only + --with-mirror rejected"

echo "=== get: oc-mirror is Linux-only (mac guard, offline) ==="
err="$(OCP_PLATFORM=mac-arm64 "$OCP" get --mirror-only 4.18.10 2>&1)"
assert_re 'Linux-only' "$err" "mac host rejected for oc-mirror"

echo "=== get/fetch via a local file:// mirror ==="
if ! curl -fsSL "file://$OCP" -o /dev/null 2>/dev/null; then
  echo "SKIP: this curl lacks file:// support; skipping fetch tests" >&2
else
  sha256f() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

  # Build a tarball containing an 'oc-mirror' that prints a marker, so tests can
  # tell which variant/tree was installed by running the installed binary.
  mk_mirror_tar() {  # <out-tar> <marker>
    local out="$1" marker="$2" b="$TESTDIR/build"
    rm -rf "$b"; mkdir -p "$b"
    printf '#!/bin/sh\necho %s\n' "$marker" > "$b/oc-mirror"; chmod +x "$b/oc-mirror"
    ( cd "$b" && tar -czf "$out" oc-mirror )
  }

  # Build a tarball whose members are the given stub binaries (each just exits 0).
  mk_core_tar() {  # <out-tar> <member>...
    local out="$1"; shift
    local b="$TESTDIR/cbuild"; rm -rf "$b"; mkdir -p "$b"
    local m
    for m in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$b/$m"; chmod +x "$b/$m"; done
    ( cd "$b" && tar -czf "$out" "$@" )
  }

  MIR="$TESTDIR/mirror"
  X="$MIR/x86_64/clients/ocp/4.18.10"; A="$MIR/arm64/clients/ocp/4.18.10"
  P="$MIR/x86_64/clients/ocp/4.17.0"   # a version with only the plain build
  mkdir -p "$X" "$A" "$P"

  for d in "$X" "$A" "$P"; do printf 'Name: %s\n' "${d##*/}" > "$d/release.txt"; done

  mk_mirror_tar "$X/oc-mirror.tar.gz"       "rhel8-x86"
  mk_mirror_tar "$X/oc-mirror.rhel9.tar.gz" "rhel9-x86"
  mk_mirror_tar "$A/oc-mirror.tar.gz"       "rhel8-arm"
  mk_mirror_tar "$A/oc-mirror.rhel9.tar.gz" "rhel9-arm"
  mk_mirror_tar "$P/oc-mirror.tar.gz"       "rhel8-only"
  mk_core_tar "$X/openshift-install-linux-4.18.10.tar.gz" openshift-install
  mk_core_tar "$X/openshift-client-linux-4.18.10.tar.gz"  oc kubectl
  ( cd "$X" && sha256f oc-mirror.tar.gz oc-mirror.rhel9.tar.gz \
      openshift-install-linux-4.18.10.tar.gz openshift-client-linux-4.18.10.tar.gz > sha256sum.txt )
  ( cd "$A" && sha256f oc-mirror.tar.gz oc-mirror.rhel9.tar.gz > sha256sum.txt )
  ( cd "$P" && sha256f oc-mirror.tar.gz                        > sha256sum.txt )

  export OCP_BASE_URL="file://$MIR/x86_64/clients/ocp"
  export OCP_BIN_DIR="$TESTDIR/fetch-dir"; mkdir -p "$OCP_BIN_DIR"

  echo "--- prefers the rhel9 build ---"
  OCP_PLATFORM=linux "$OCP" get --mirror-only 4.18.10 >/dev/null 2>&1
  assert_eq "rhel9-x86" "$("$OCP_BIN_DIR/oc-mirror-4.18.10" 2>&1)" "installs the rhel9 build by default"

  echo "--- --rhel8 forces the plain build ---"
  "$OCP" remove 4.18.10 >/dev/null 2>&1
  OCP_PLATFORM=linux "$OCP" get --mirror-only --rhel8 4.18.10 >/dev/null 2>&1
  assert_eq "rhel8-x86" "$("$OCP_BIN_DIR/oc-mirror-4.18.10" 2>&1)" "--rhel8 installs the plain build"

  echo "--- falls back to the plain build when no rhel9 exists ---"
  OCP_PLATFORM=linux "$OCP" get --mirror-only 4.17.0 >/dev/null 2>&1
  assert_eq "rhel8-only" "$("$OCP_BIN_DIR/oc-mirror-4.17.0" 2>&1)" "falls back to the plain build"

  echo "--- arm64 pulls from the arm64 tree ---"
  "$OCP" remove 4.18.10 >/dev/null 2>&1
  OCP_PLATFORM=linux-arm64 "$OCP" get --mirror-only 4.18.10 >/dev/null 2>&1
  assert_eq "rhel9-arm" "$("$OCP_BIN_DIR/oc-mirror-4.18.10" 2>&1)" "arm64 fetch hits the arm64 tree"

  echo "--- a bare get installs only CLI (no installer, no oc-mirror) ---"
  "$OCP" remove 4.18.10 >/dev/null 2>&1
  OCP_PLATFORM=linux "$OCP" get 4.18.10 >/dev/null 2>&1
  [ -x "$OCP_BIN_DIR/oc-4.18.10" ]                && ok "bare get installed oc"           || bad "bare get missing oc"
  [ -e "$OCP_BIN_DIR/openshift-install-4.18.10" ] && bad "bare get should not fetch installer" || ok "bare get skips installer"
  [ -e "$OCP_BIN_DIR/oc-mirror-4.18.10" ] && bad "bare get should not fetch oc-mirror" || ok "bare get skips oc-mirror"

  echo "--- OCP_WITH_INSTALLER=1 adds installer to a bare get ---"
  "$OCP" remove 4.18.10 >/dev/null 2>&1
  OCP_PLATFORM=linux OCP_WITH_INSTALLER=1 "$OCP" get 4.18.10 >/dev/null 2>&1
  [ -x "$OCP_BIN_DIR/openshift-install-4.18.10" ] && ok "OCP_WITH_INSTALLER fetched installer" || bad "OCP_WITH_INSTALLER did not fetch installer"
  [ -x "$OCP_BIN_DIR/oc-4.18.10" ]                && ok "CLI still installed alongside installer" || bad "CLI missing"

  echo "--- OCP_WITH_MIRROR=1 adds oc-mirror to a bare get ---"
  "$OCP" remove 4.18.10 >/dev/null 2>&1
  OCP_PLATFORM=linux OCP_WITH_MIRROR=1 "$OCP" get 4.18.10 >/dev/null 2>&1
  [ -x "$OCP_BIN_DIR/oc-mirror-4.18.10" ] && ok "OCP_WITH_MIRROR fetched oc-mirror on a bare get" || bad "OCP_WITH_MIRROR did not fetch oc-mirror"
  [ -x "$OCP_BIN_DIR/oc-4.18.10" ]        && ok "CLI still installed alongside oc-mirror" || bad "CLI missing"

  echo "--- already-installed is a no-op ---"
  out="$(OCP_PLATFORM=linux "$OCP" get --mirror-only 4.18.10 2>&1)"
  assert_re 'already installed' "$out" "re-get of present oc-mirror is a no-op"
fi

finish
