# oc-mirror Component Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `ocp` download, verify, install, activate, list, and remove the `oc-mirror` binary as an optional fourth component alongside `openshift-install`, `oc`, and `kubectl`.

**Architecture:** `oc-mirror` is stored version-qualified (`oc-mirror-<version>`) and activated as a bare `oc-mirror` symlink, exactly like the core components — but it is *optional* (Linux-only, opt-in) so it never adds noise for users who don't install it. Its fetch is isolated in a dedicated helper because the mirror packages it differently: the tarball is neither version- nor platform-qualified (`oc-mirror[.rhel9].tar.gz`, extracting a single `oc-mirror` binary), it is Linux-only, arm64 lives in a separate mirror tree, and 4.16+ ships two RHEL variants.

**Tech Stack:** Bash (single-file `ocp` script), the existing offline test harness in `tests/` (fake `curl`, `file://` URLs, stub binaries).

**Spec:** `docs/specs/2026-06-14-ocp-oc-mirror-design.md`

---

## File Structure

- Modify `ocp` — add component constants; add `oc-mirror` to `active_version`, `installed_components`, `cmd_list`, `cmd_remove`, `cmd_use`; add `cmd_get` flags + restructure; add `fetch_oc_mirror`; update `usage()`.
- Create `tests/test_mirror.sh` — offline tests for all new behavior.
- Modify `README.md` — document new flags, env var, and platform/variant behavior.

A note on a latent glob hazard you must respect: the shell glob `oc-*` also matches `oc-mirror-*`. Any place that globs `oc-*` (only `cmd_list` does) must skip `oc-mirror-*`. Exact-path checks like `oc-$version` are unaffected (they never match `oc-mirror-$version`).

---

## Task 1: Component constants + optional-component plumbing (list/remove/active/installed)

**Files:**
- Modify: `ocp` (add constants; update `active_version`, `installed_components`, `cmd_list`, `cmd_remove`)
- Test: `tests/test_mirror.sh` (create)

- [ ] **Step 1: Write the failing test**

Create `tests/test_mirror.sh`:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_mirror.sh`
Expected: FAIL on the `(installer, oc, kubectl, oc-mirror)` / `(oc-mirror)` / active-marker / removal assertions (oc-mirror not yet handled).

- [ ] **Step 3: Add the component constants**

In `ocp`, after the `UPDATE_URL` block and before the `# ---- helpers` line, add:

```bash
# Components ocp manages. The first three are "core": always expected, and
# 'use' warns + unsets the bare link when one is missing. oc-mirror is optional
# (Linux-only, opt-in): linked when present, silently skipped when absent.
CORE_COMPONENTS=(openshift-install oc kubectl)
OPTIONAL_COMPONENTS=(oc-mirror)
ALL_COMPONENTS=("${CORE_COMPONENTS[@]}" "${OPTIONAL_COMPONENTS[@]}")
```

- [ ] **Step 4: Update `active_version` to iterate all components**

Replace the loop header in `active_version`:

```bash
  for bare in openshift-install oc kubectl; do
```

with:

```bash
  for bare in "${ALL_COMPONENTS[@]}"; do
```

- [ ] **Step 5: Add oc-mirror to `installed_components`**

In `installed_components`, after the `kubectl` line, add a fourth line so the body reads:

```bash
  [ -x "$BIN_DIR/openshift-install-$version" ] && present="${present:+$present, }installer"
  [ -x "$BIN_DIR/oc-$version" ]                && present="${present:+$present, }oc"
  [ -x "$BIN_DIR/kubectl-$version" ]           && present="${present:+$present, }kubectl"
  [ -x "$BIN_DIR/oc-mirror-$version" ]         && present="${present:+$present, }oc-mirror"
```

- [ ] **Step 6: Update `cmd_list` gather loop (and guard the oc-* glob)**

Replace the gather loop in `cmd_list`:

```bash
  for comp in openshift-install oc kubectl; do
    for f in "$BIN_DIR/$comp"-*; do
      [ -L "$f" ] && continue   # skip the bare symlink if it matched
      versions+=("${f##*/$comp-}")
      files+=("$f")
    done
  done
```

with:

```bash
  for comp in "${ALL_COMPONENTS[@]}"; do
    for f in "$BIN_DIR/$comp"-*; do
      [ -L "$f" ] && continue   # skip the bare symlink if it matched
      # 'oc-*' also matches 'oc-mirror-*'; oc-mirror is gathered on its own pass.
      [ "$comp" = oc ] && case "${f##*/}" in oc-mirror-*) continue ;; esac
      versions+=("${f##*/$comp-}")
      files+=("$f")
    done
  done
```

- [ ] **Step 7: Update `cmd_remove` to iterate all components**

Replace the removal loop header in `cmd_remove`:

```bash
  for bare in openshift-install oc kubectl; do
```

with:

```bash
  for bare in "${ALL_COMPONENTS[@]}"; do
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `bash tests/test_mirror.sh`
Expected: PASS for all assertions in this file.

- [ ] **Step 9: Run the full suite (no regressions)**

Run: `tests/run.sh`
Expected: `ALL SUITES PASSED`.

- [ ] **Step 10: Commit**

```bash
git add ocp tests/test_mirror.sh
git commit -m "ocp: treat oc-mirror as an optional component in list/remove/active"
```

---

## Task 2: `cmd_use` activates oc-mirror (optional, no warning)

**Files:**
- Modify: `ocp` (`cmd_use`)
- Test: `tests/test_mirror.sh` (insert before `finish`)

- [ ] **Step 1: Write the failing test**

In `tests/test_mirror.sh`, insert this block immediately before the `finish` line:

```bash
echo "=== use links oc-mirror when present ==="
for b in openshift-install oc kubectl oc-mirror; do stub "$OCP_BIN_DIR/$b-4.18.11"; done
out="$("$OCP" use 4.18.11 2>&1)"
[ -L "$OCP_BIN_DIR/oc-mirror" ] && ok "oc-mirror symlink created" || bad "oc-mirror symlink missing"
assert_eq "oc-mirror-4.18.11" "$(readlink "$OCP_BIN_DIR/oc-mirror")" "oc-mirror symlink is relative"

echo "=== use a version without oc-mirror: no warning, bare oc-mirror unset ==="
for b in openshift-install oc kubectl; do stub "$OCP_BIN_DIR/$b-4.18.12"; done   # no oc-mirror
out="$("$OCP" use 4.18.12 2>&1)"
assert_no_re 'oc-mirror' "$out" "no oc-mirror warning for versions without it"
[ -e "$OCP_BIN_DIR/oc-mirror" ] && bad "stale oc-mirror symlink left" || ok "oc-mirror symlink cleared"

echo "=== use a mirror-only install works (no error) ==="
stub "$OCP_BIN_DIR/oc-mirror-4.18.13"
"$OCP" use 4.18.13 >/dev/null 2>&1; assert_eq 0 "$?" "use mirror-only exits 0"
assert_eq "oc-mirror-4.18.13" "$(readlink "$OCP_BIN_DIR/oc-mirror")" "mirror-only use links oc-mirror"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_mirror.sh`
Expected: FAIL — the current `cmd_use` neither links oc-mirror nor treats a mirror-only install as usable.

- [ ] **Step 3: Update `cmd_use`**

Replace the "any" guard loop in `cmd_use`:

```bash
  local bare any=0
  for bare in openshift-install oc kubectl; do
    [ -x "$BIN_DIR/$bare-$version" ] && any=1
  done
```

with:

```bash
  local bare any=0
  for bare in "${ALL_COMPONENTS[@]}"; do
    [ -x "$BIN_DIR/$bare-$version" ] && any=1
  done
```

Then replace the linking subshell:

```bash
  ( cd "$BIN_DIR" || die "cannot cd to $BIN_DIR"
    for bare in openshift-install oc kubectl; do
      rm -f "$bare"   # portable replace (BSD ln lacks -n)
      if [ -x "$bare-$version" ]; then
        ln -s "$bare-$version" "$bare"
      else
        info "warning: $bare not installed for $version; '$bare' unset"
      fi
    done )
```

with:

```bash
  ( cd "$BIN_DIR" || die "cannot cd to $BIN_DIR"
    for bare in "${CORE_COMPONENTS[@]}"; do
      rm -f "$bare"   # portable replace (BSD ln lacks -n)
      if [ -x "$bare-$version" ]; then
        ln -s "$bare-$version" "$bare"
      else
        info "warning: $bare not installed for $version; '$bare' unset"
      fi
    done
    # Optional components: link when present, silently clear otherwise so the
    # bare link never dangles to a different version (no warning -- most users
    # never install these).
    for bare in "${OPTIONAL_COMPONENTS[@]}"; do
      rm -f "$bare"
      [ -x "$bare-$version" ] && ln -s "$bare-$version" "$bare"
    done )
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test_mirror.sh`
Expected: PASS for all assertions.

- [ ] **Step 5: Run the full suite**

Run: `tests/run.sh`
Expected: `ALL SUITES PASSED` (the existing `test_use_list.sh` warn-on-missing-core behavior is unchanged).

- [ ] **Step 6: Commit**

```bash
git add ocp tests/test_mirror.sh
git commit -m "ocp: activate oc-mirror in 'use' as an optional component"
```

---

## Task 3: `get` flags, mac guard, and `fetch_oc_mirror`

**Files:**
- Modify: `ocp` (`cmd_get`; add `fetch_oc_mirror`)
- Test: `tests/test_mirror.sh` (insert before `finish`)

- [ ] **Step 1: Write the failing flag-validation + mac-guard tests**

In `tests/test_mirror.sh`, insert this block immediately before the `finish` line:

```bash
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test_mirror.sh`
Expected: FAIL — these flags/guards don't exist yet.

- [ ] **Step 3: Add `fetch_oc_mirror` helper**

In `ocp`, immediately after the `verify_checksum` function (before `# ---- subcommands`), add:

```bash
# Download + verify + install oc-mirror for a version. oc-mirror's tarball is
# neither version- nor platform-qualified (always oc-mirror[.rhel9].tar.gz,
# extracting a single 'oc-mirror' binary), is Linux-only, and on arm64 is served
# from a separate mirror tree -- so it gets its own fetch routine.
# Args: <ref> <version> <platform> <force_rhel8>
fetch_oc_mirror() {
  local ref="$1" version="$2" platform="$3" force_rhel8="$4"
  local mirror_url="$BASE_URL" sumfile tarball

  # arm64 oc-mirror lives in the arm64 client tree, not the x86_64 one. If a
  # custom OCP_BASE_URL has no '/x86_64/' segment this is a no-op (documented).
  if [ "$platform" = "linux-arm64" ]; then
    mirror_url="$(printf '%s\n' "$BASE_URL" | sed 's#/x86_64/#/arm64/#')"
  fi

  [ -n "$WORKDIR" ] || WORKDIR="$(mktemp -d)"
  sumfile="$WORKDIR/oc-mirror-sha256sum.txt"

  info "Downloading oc-mirror sha256sum.txt ..."
  curl -fsSL "$mirror_url/$ref/sha256sum.txt" -o "$sumfile" \
    || die "failed to download oc-mirror sha256sum.txt from $mirror_url/$ref/"

  # Prefer the RHEL9 build (what oc-mirror v2 wants) when present; fall back to
  # the plain (RHEL8) build. --rhel8 forces the plain build.
  if [ "$force_rhel8" != 1 ] && grep -qE '[[:space:]]oc-mirror\.rhel9\.tar\.gz$' "$sumfile"; then
    tarball="oc-mirror.rhel9.tar.gz"
  else
    tarball="oc-mirror.tar.gz"
  fi

  info "Downloading $tarball ..."
  curl -fSL --progress-bar "$mirror_url/$ref/$tarball" -o "$WORKDIR/$tarball" \
    || die "failed to download $tarball"

  info "Verifying checksum ..."
  if ! verify_checksum "$sumfile" "$tarball" "$WORKDIR/$tarball"; then
    if [ "${OCP_INSECURE:-}" = "1" ]; then
      info "  OCP_INSECURE=1 set; continuing despite mismatch."
    else
      die "checksum verification failed for $tarball (set OCP_INSECURE=1 to override)"
    fi
  fi

  tar -xzf "$WORKDIR/$tarball" -C "$WORKDIR" oc-mirror
  install -m 0755 "$WORKDIR/oc-mirror" "$BIN_DIR/oc-mirror-$version"
  info "Installed: $BIN_DIR/oc-mirror-$version"
}
```

- [ ] **Step 4: Rewrite `cmd_get` flag parsing + validation**

Replace the flag-parsing prologue of `cmd_get` (from `local ref=""` through the mutually-exclusive `die` line, i.e. down to and including `|| die "--cli-only and --installer-only are mutually exclusive"`):

```bash
  # "cli" = the client tarball (oc + kubectl); "installer" = openshift-install.
  local ref="" want_cli=1 want_installer=1 do_use=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cli-only)       want_installer=0 ;;
      --installer-only) want_cli=0 ;;
      --use)            do_use=1 ;;
      -*) die "unknown flag: $1 (see 'ocp --help')" ;;
      *)  [ -z "$ref" ] || die "unexpected argument: $1"; ref="$1" ;;
    esac
    shift
  done
  [ -n "$ref" ] || die "usage: ocp get [--cli-only|--installer-only] <version|channel>"
  [ "$want_cli" = 1 ] || [ "$want_installer" = 1 ] \
    || die "--cli-only and --installer-only are mutually exclusive"
  require curl; require tar
```

with:

```bash
  # "cli" = the client tarball (oc + kubectl); "installer" = openshift-install.
  local ref="" want_cli=1 want_installer=1 do_use=0
  # oc-mirror is opt-in: via --with-mirror/--mirror-only, or OCP_WITH_MIRROR=1.
  local want_mirror=0 mirror_only=0 with_mirror=0 force_rhel8=0
  [ -n "${OCP_WITH_MIRROR:-}" ] && want_mirror=1
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cli-only)       want_installer=0 ;;
      --installer-only) want_cli=0 ;;
      --with-mirror)    with_mirror=1; want_mirror=1 ;;
      --mirror-only)    mirror_only=1 ;;
      --rhel8)          force_rhel8=1 ;;
      --use)            do_use=1 ;;
      -*) die "unknown flag: $1 (see 'ocp --help')" ;;
      *)  [ -z "$ref" ] || die "unexpected argument: $1"; ref="$1" ;;
    esac
    shift
  done
  [ -n "$ref" ] || die "usage: ocp get [--cli-only|--installer-only|--mirror-only|--with-mirror] <version|channel>"

  if [ "$mirror_only" = 1 ]; then
    { [ "$want_cli" = 0 ] || [ "$want_installer" = 0 ] || [ "$with_mirror" = 1 ]; } \
      && die "--mirror-only cannot be combined with --cli-only, --installer-only, or --with-mirror"
    want_installer=0; want_cli=0; want_mirror=1
  fi
  [ "$want_installer" = 1 ] || [ "$want_cli" = 1 ] || [ "$want_mirror" = 1 ] \
    || die "--cli-only and --installer-only are mutually exclusive"
  require curl; require tar
```

- [ ] **Step 5: Add the early mac guard + extend the "what's needed" logic**

Replace this section of `cmd_get`:

```bash
  local platform version
  platform="$(detect_platform)"
  version="$(resolve_version "$ref")"
  info "Resolved '$ref' -> $version ($platform)"

  # Only fetch components that are both requested and not already installed,
  # so a repeated 'get' (or one that completes a partial install) skips work.
  local need_installer=0 need_client=0
  [ "$want_installer" = 1 ] && [ ! -x "$BIN_DIR/openshift-install-$version" ] && need_installer=1
  [ "$want_cli" = 1 ]       && [ ! -x "$BIN_DIR/oc-$version" ]                && need_client=1

  if [ "$need_installer" = 0 ] && [ "$need_client" = 0 ]; then
    info "$version already installed (requested components present)"
    if [ "$do_use" = 1 ]; then cmd_use "$version"; else check_path; fi
    return 0
  fi
```

with:

```bash
  local platform version
  platform="$(detect_platform)"

  # Fail fast (before any network) if oc-mirror is wanted on an unsupported host.
  if [ "$want_mirror" = 1 ]; then
    case "$platform" in
      linux|linux-arm64) ;;
      *) die "oc-mirror is Linux-only (no $platform build); drop --with-mirror/--mirror-only on this host" ;;
    esac
  fi

  version="$(resolve_version "$ref")"
  info "Resolved '$ref' -> $version ($platform)"

  # Only fetch components that are both requested and not already installed,
  # so a repeated 'get' (or one that completes a partial install) skips work.
  local need_installer=0 need_client=0 need_mirror=0
  [ "$want_installer" = 1 ] && [ ! -x "$BIN_DIR/openshift-install-$version" ] && need_installer=1
  [ "$want_cli" = 1 ]       && [ ! -x "$BIN_DIR/oc-$version" ]                && need_client=1
  [ "$want_mirror" = 1 ]    && [ ! -x "$BIN_DIR/oc-mirror-$version" ]         && need_mirror=1

  if [ "$need_installer" = 0 ] && [ "$need_client" = 0 ] && [ "$need_mirror" = 0 ]; then
    info "$version already installed (requested components present)"
    if [ "$do_use" = 1 ]; then cmd_use "$version"; else check_path; fi
    return 0
  fi
```

- [ ] **Step 6: Restructure the download/extract body to guard the core block and call `fetch_oc_mirror`**

Replace the entire remainder of `cmd_get` (from `local install_tarball=...` through the final `check_path` / closing `fi`):

```bash
  local install_tarball="openshift-install-$platform-$version.tar.gz"
  local client_tarball="openshift-client-$platform-$version.tar.gz"

  # Tarballs to fetch this run (never empty: we returned early if nothing needed).
  local tarballs=()
  [ "$need_installer" = 1 ] && tarballs+=("$install_tarball")
  [ "$need_client" = 1 ]    && tarballs+=("$client_tarball")

  local tmp
  WORKDIR="$(mktemp -d)"
  tmp="$WORKDIR"

  info "Downloading sha256sum.txt ..."
  curl -fsSL "$BASE_URL/$ref/sha256sum.txt" -o "$tmp/sha256sum.txt" \
    || die "failed to download sha256sum.txt"

  local t
  for t in "${tarballs[@]}"; do
    info "Downloading $t ..."
    curl -fSL --progress-bar "$BASE_URL/$ref/$t" -o "$tmp/$t" \
      || die "failed to download $t"
  done

  info "Verifying checksums ..."
  for t in "${tarballs[@]}"; do
    if ! verify_checksum "$tmp/sha256sum.txt" "$t" "$tmp/$t"; then
      if [ "$platform" = "mac-arm64" ]; then
        info "  note: Apple Silicon binaries are re-signed/notarized after the mirror"
        info "  publishes sha256sum.txt, so this mismatch is expected upstream; continuing."
      elif [ "${OCP_INSECURE:-}" = "1" ]; then
        info "  OCP_INSECURE=1 set; continuing despite mismatch."
      else
        die "checksum verification failed for $t (set OCP_INSECURE=1 to override)"
      fi
    fi
  done

  info "Extracting ..."
  mkdir -p "$BIN_DIR"
  info "Installed:"
  if [ "$need_installer" = 1 ]; then
    tar -xzf "$tmp/$install_tarball" -C "$tmp" openshift-install
    install -m 0755 "$tmp/openshift-install" "$BIN_DIR/openshift-install-$version"
    info "  $BIN_DIR/openshift-install-$version"
  fi
  if [ "$need_client" = 1 ]; then
    tar -xzf "$tmp/$client_tarball" -C "$tmp" oc kubectl
    install -m 0755 "$tmp/oc"      "$BIN_DIR/oc-$version"
    install -m 0755 "$tmp/kubectl" "$BIN_DIR/kubectl-$version"
    info "  $BIN_DIR/oc-$version"
    info "  $BIN_DIR/kubectl-$version"
  fi
  if [ "$do_use" = 1 ]; then
    cmd_use "$version"
  else
    info "Run 'ocp use $version' to activate it."
    check_path
  fi
}
```

with:

```bash
  local install_tarball="openshift-install-$platform-$version.tar.gz"
  local client_tarball="openshift-client-$platform-$version.tar.gz"

  # Core tarballs to fetch this run (may be empty for a --mirror-only get).
  local tarballs=()
  [ "$need_installer" = 1 ] && tarballs+=("$install_tarball")
  [ "$need_client" = 1 ]    && tarballs+=("$client_tarball")

  local tmp
  WORKDIR="$(mktemp -d)"
  tmp="$WORKDIR"
  mkdir -p "$BIN_DIR"

  # --- core components (installer + client), served from the x86_64 tree ------
  if [ "${#tarballs[@]}" -gt 0 ]; then
    info "Downloading sha256sum.txt ..."
    curl -fsSL "$BASE_URL/$ref/sha256sum.txt" -o "$tmp/sha256sum.txt" \
      || die "failed to download sha256sum.txt"

    local t
    for t in "${tarballs[@]}"; do
      info "Downloading $t ..."
      curl -fSL --progress-bar "$BASE_URL/$ref/$t" -o "$tmp/$t" \
        || die "failed to download $t"
    done

    info "Verifying checksums ..."
    for t in "${tarballs[@]}"; do
      if ! verify_checksum "$tmp/sha256sum.txt" "$t" "$tmp/$t"; then
        if [ "$platform" = "mac-arm64" ]; then
          info "  note: Apple Silicon binaries are re-signed/notarized after the mirror"
          info "  publishes sha256sum.txt, so this mismatch is expected upstream; continuing."
        elif [ "${OCP_INSECURE:-}" = "1" ]; then
          info "  OCP_INSECURE=1 set; continuing despite mismatch."
        else
          die "checksum verification failed for $t (set OCP_INSECURE=1 to override)"
        fi
      fi
    done

    info "Extracting ..."
    if [ "$need_installer" = 1 ]; then
      tar -xzf "$tmp/$install_tarball" -C "$tmp" openshift-install
      install -m 0755 "$tmp/openshift-install" "$BIN_DIR/openshift-install-$version"
      info "Installed: $BIN_DIR/openshift-install-$version"
    fi
    if [ "$need_client" = 1 ]; then
      tar -xzf "$tmp/$client_tarball" -C "$tmp" oc kubectl
      install -m 0755 "$tmp/oc"      "$BIN_DIR/oc-$version"
      install -m 0755 "$tmp/kubectl" "$BIN_DIR/kubectl-$version"
      info "Installed: $BIN_DIR/oc-$version"
      info "Installed: $BIN_DIR/kubectl-$version"
    fi
  fi

  # --- oc-mirror (separate tree/naming/variants) -----------------------------
  if [ "$need_mirror" = 1 ]; then
    fetch_oc_mirror "$ref" "$version" "$platform" "$force_rhel8"
  fi

  if [ "$do_use" = 1 ]; then
    cmd_use "$version"
  else
    info "Run 'ocp use $version' to activate it."
    check_path
  fi
}
```

- [ ] **Step 7: Run the flag/guard tests to verify they pass**

Run: `bash tests/test_mirror.sh`
Expected: PASS for the conflict + mac-guard assertions added in Step 1. (The earlier tasks' assertions still pass.)

- [ ] **Step 8: Add the end-to-end fetch tests (file:// mirror)**

In `tests/test_mirror.sh`, insert this block immediately before the `finish` line:

```bash
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
  ( cd "$X" && sha256f oc-mirror.tar.gz oc-mirror.rhel9.tar.gz > sha256sum.txt )
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

  echo "--- OCP_WITH_MIRROR opts oc-mirror into a default get ---"
  "$OCP" remove 4.18.10 >/dev/null 2>&1
  OCP_PLATFORM=linux OCP_WITH_MIRROR=1 "$OCP" get --mirror-only 4.18.10 >/dev/null 2>&1
  [ -x "$OCP_BIN_DIR/oc-mirror-4.18.10" ] && ok "OCP_WITH_MIRROR fetched oc-mirror" || bad "OCP_WITH_MIRROR did not fetch oc-mirror"

  echo "--- already-installed is a no-op ---"
  out="$(OCP_PLATFORM=linux "$OCP" get --mirror-only 4.18.10 2>&1)"
  assert_re 'already installed' "$out" "re-get of present oc-mirror is a no-op"
fi
```

- [ ] **Step 9: Run the fetch tests to verify they pass**

Run: `bash tests/test_mirror.sh`
Expected: PASS for all assertions (or `SKIP` for the file:// block on a curl without file:// support, with the rest passing).

- [ ] **Step 10: Run the full suite**

Run: `tests/run.sh`
Expected: `ALL SUITES PASSED`.

- [ ] **Step 11: Commit**

```bash
git add ocp tests/test_mirror.sh
git commit -m "ocp: fetch oc-mirror in 'get' (--mirror-only/--with-mirror, rhel9 default, arm64 tree)"
```

---

## Task 4: Documentation (`usage()` + README)

**Files:**
- Modify: `ocp` (`usage()`)
- Modify: `README.md`

- [ ] **Step 1: Update `usage()` in `ocp`**

In the `usage()` heredoc, replace the `get` description line:

```
  ocp get [--cli-only|--installer-only] [--use] <version|channel>
                              Download, verify and install a version.
                              --cli-only       only oc + kubectl
                              --installer-only only openshift-install
                              --use            activate it afterwards
```

with:

```
  ocp get [--cli-only|--installer-only|--mirror-only|--with-mirror] [--rhel8] [--use] <version|channel>
                              Download, verify and install a version.
                              --cli-only       only oc + kubectl
                              --installer-only only openshift-install
                              --mirror-only    only oc-mirror (Linux only)
                              --with-mirror    also fetch oc-mirror
                              --rhel8          oc-mirror: force the RHEL8 build
                              --use            activate it afterwards
```

Then, in the same heredoc's `Environment:` section, add after the `OCP_INSECURE` line:

```
  OCP_WITH_MIRROR set to 1 to always include oc-mirror in a default 'get'
```

- [ ] **Step 2: Update `README.md` usage block**

In `README.md`, in the `## Usage` fenced block, replace the three `ocp get ...` lines:

```sh
ocp get <version|channel>   # download, verify (sha256) and install a version
ocp get --cli-only <ver>    # only the client (oc + kubectl)
ocp get --installer-only <ver>  # only openshift-install
ocp get --use <ver>         # install, then activate it (runs 'use')
```

with:

```sh
ocp get <version|channel>   # download, verify (sha256) and install a version
ocp get --cli-only <ver>    # only the client (oc + kubectl)
ocp get --installer-only <ver>  # only openshift-install
ocp get --mirror-only <ver> # only oc-mirror (Linux only)
ocp get --with-mirror <ver> # the default two, plus oc-mirror
ocp get --use <ver>         # install, then activate it (runs 'use')
```

- [ ] **Step 3: Add an oc-mirror section to `README.md`**

In `README.md`, immediately before the `## Platforms` heading, add:

```markdown
### oc-mirror

`oc-mirror` is managed as an optional fourth component. It's opt-in because the
mirror only ships it for **Linux** (x86_64 and arm64 — there is no macOS build).
Fetch it alongside a normal `get` with `--with-mirror`, on its own with
`--mirror-only`, or always-on by exporting `OCP_WITH_MIRROR=1`. Once installed
it behaves like the others: `ocp use` links the bare `oc-mirror`, and `ocp list`
/ `ocp remove` include it.

From 4.16 the mirror publishes two builds — `oc-mirror.tar.gz` (RHEL8) and
`oc-mirror.rhel9.tar.gz` (RHEL9, which oc-mirror v2 expects). `ocp` installs the
RHEL9 build when it's available and falls back to the plain build otherwise; use
`--rhel8` to force the plain build. (To switch an already-installed version's
build, `ocp remove <ver>` first.) On arm64 hosts the binary is pulled from the
mirror's `arm64/` client tree automatically.
```

- [ ] **Step 4: Update the Environment table in `README.md`**

In `README.md`, find the `OCP_BASE_URL` row/line in the environment documentation and add an `OCP_WITH_MIRROR` entry next to it describing: "set to 1 to always include oc-mirror in a default `get`". (Match the surrounding format — list or table — exactly.)

- [ ] **Step 5: Verify docs reflect reality**

Run: `bash -n ocp && ./ocp --help`
Expected: clean syntax check, and `--help` shows the new flags and `OCP_WITH_MIRROR`.

- [ ] **Step 6: Commit**

```bash
git add ocp README.md
git commit -m "docs: document oc-mirror get flags, OCP_WITH_MIRROR, and variant/arch behavior"
```

---

## Self-Review notes

- **Spec coverage:** binary management (Task 3 fetch + Tasks 1–2 plumbing); both flags + env var (Task 3 Step 4); rhel9-prefer/rhel8 fallback + `--rhel8` (Task 3 Step 3); arm64 tree derivation (Task 3 Step 3); mac guard (Task 3 Step 5); optional/no-warning `use` (Task 2); list/remove/active/installed (Task 1); docs + tests (Task 4 + per-task tests). Remove-first-to-switch-variant is covered by the "already installed" no-op (Task 3 Step 5) and documented (Task 4 Step 3).
- **Glob hazard:** addressed once in `cmd_list` (Task 1 Step 6) and verified by `assert_no_re 'mirror-4\.18\.10'`.
- **Naming consistency:** `fetch_oc_mirror <ref> <version> <platform> <force_rhel8>` defined in Task 3 Step 3 and called with the same 4 args in Task 3 Step 6; flag variables (`want_mirror`, `mirror_only`, `with_mirror`, `force_rhel8`, `need_mirror`) introduced and consumed within Task 3.
```
