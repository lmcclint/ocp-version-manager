# ocp update — Release-Notes Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ocp update` print high-level release notes (the `CHANGELOG.md` sections between the user's old version and the new one) after a successful self-update.

**Architecture:** A hand-maintained `CHANGELOG.md` at the repo root is the source of truth (newest-first, `## X.Y.Z` section headers). `cmd_update()` already knows the old (`VERSION`) and new (`newver`) versions; after the in-place swap succeeds it fetches the changelog from a URL derived from `UPDATE_URL` (overridable via `OCP_CHANGELOG_URL`) and prints the sections whose version is in the half-open range `(old, new]`. The whole thing is best-effort: any failure prints `release notes unavailable` and the update still stands.

**Tech Stack:** Single-file Bash (`ocp`); the existing offline test harness in `tests/` (`tests/lib.sh` provides `fake_curl`, assertion helpers, and a temp dir; updates are served over `curl`'s `file://` support).

**Spec:** `docs/specs/2026-06-15-ocp-update-changelog-design.md`

---

## File Structure

- `CHANGELOG.md` (**create**) — root-level changelog, newest-first, `## X.Y.Z` sections. Backfilled with historical versions; the `0.6.0` entry is added in the feature task.
- `ocp` (**modify**) — add `CHANGELOG_URL` config, a `ver_gt` helper, a `print_release_notes` function, one call site in `cmd_update()`, and bump `VERSION`.
- `tests/test_changelog.sh` (**create**) — offline coverage for the happy path, the already-up-to-date no-op, and graceful degradation. Auto-discovered by `tests/run.sh` (globs `test_*.sh`).
- `README.md` / `CLAUDE.md` (**modify**) — document `OCP_CHANGELOG_URL`, the notes-on-update behavior, and the new "bump VERSION + add CHANGELOG entry together" rule.

---

## Task 1: Backfill CHANGELOG.md

Create the changelog with the historical versions (from git history: 0.1.0, 0.1.1, 0.2.0, 0.3.0, 0.3.1, 0.3.2, 0.4.0, 0.5.0, 0.5.1). The `0.6.0` entry is intentionally **not** here yet — it lands with the feature in Task 2, so `VERSION` and the top changelog entry move together.

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write the changelog file**

Create `CHANGELOG.md` with exactly this content:

```markdown
# Changelog

All notable changes to `ocp`. Newest first. Each `## X.Y.Z` section matches a
`VERSION` released to `main`; `ocp update` prints the sections between a user's
current version and the version they update to.

## 0.5.1
- fix arm64 oc-mirror mirror-tree fallback

## 0.5.0
- manage oc-mirror as an optional fourth component (`--with-mirror`, `--mirror-only`, `OCP_WITH_MIRROR`)

## 0.4.0
- groundwork for oc-mirror support

## 0.3.2
- list/use fixes for partial installs

## 0.3.1
- partial-install polish

## 0.3.0
- partial installs: fetch/activate individual components

## 0.2.0
- list-versions / list-channels against the mirror

## 0.1.1
- early fixes

## 0.1.0
- initial release: get / use / list / remove for oc, kubectl, openshift-install
```

- [ ] **Step 2: Verify it is valid Markdown with the expected headers**

Run: `grep -c '^## [0-9]' CHANGELOG.md`
Expected: `9`

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG.md backfilled with version history"
```

---

## Task 2: Implement release-notes-on-update

Add the config, helpers, and call site to `ocp`, bump `VERSION` to `0.6.0`, and prepend the `0.6.0` changelog entry. Test-first.

**Files:**
- Create: `tests/test_changelog.sh`
- Modify: `ocp` (config block near line 33; helpers near the `vsort` definition ~line 88; `cmd_update()` ~line 602; `VERSION` line 21)
- Modify: `CHANGELOG.md` (prepend `0.6.0` section)

- [ ] **Step 1: Write the failing test**

Create `tests/test_changelog.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `chmod +x tests/test_changelog.sh && bash tests/test_changelog.sh`
Expected: FAIL — the first block fails (`missing 'Changes in this update:'`) because the feature does not exist yet. (The "already up to date" and graceful-degradation blocks may partly pass since they assert *absence*/existing text, but the suite exits non-zero.)

- [ ] **Step 3: Add the changelog URL config**

In `ocp`, immediately after the `UPDATE_URL` assignment (the line beginning `UPDATE_URL="${OCP_UPDATE_URL:-...}"`), add:

```bash
# Where 'ocp update' reads release notes from. Derived from UPDATE_URL by
# swapping the trailing 'ocp' for 'CHANGELOG.md'; override for forks/custom
# layouts (e.g. if OCP_UPDATE_URL doesn't end in 'ocp').
CHANGELOG_URL="${OCP_CHANGELOG_URL:-${UPDATE_URL%ocp}CHANGELOG.md}"
```

- [ ] **Step 4: Add the `ver_gt` helper and `print_release_notes` function**

In `ocp`, immediately after the `vsort()` function (the block that ends `}` after the `sort -V` fallback), add:

```bash
# True if version $1 is strictly greater than version $2 (per vsort ordering).
ver_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | vsort | tail -n1)" = "$1" ]
}

# Fetch CHANGELOG.md and print the sections for versions in (old, new].
# Best-effort: any failure prints a note and returns 0 so it never blocks an
# update. Args: <old-version> <new-version>.
print_release_notes() {
  local old="$1" new="$2" body vers v wanted=""
  body="$(curl -fsSL "$CHANGELOG_URL" 2>/dev/null)" \
    || { info "release notes unavailable"; return 0; }
  [ -n "$body" ] || { info "release notes unavailable"; return 0; }

  # Versions of each '## X.Y.Z' header that fall in (old, new].
  vers="$(printf '%s\n' "$body" | sed -n 's/^## \([0-9][0-9.]*\).*/\1/p')"
  for v in $vers; do
    if ver_gt "$v" "$old" && ! ver_gt "$v" "$new"; then
      wanted="$wanted $v"
    fi
  done
  [ -n "$wanted" ] || { info "release notes unavailable"; return 0; }

  info "Changes in this update:"
  # Print each wanted section (header + body) verbatim, in file order, to stderr.
  printf '%s\n' "$body" | awk -v want=" $wanted " '
    /^## / { split($0, a, " "); show = (index(want, " " a[2] " ") > 0) }
    show { print }
  ' >&2
}
```

- [ ] **Step 5: Call it from `cmd_update`**

In `ocp`, in `cmd_update()`, the successful-swap tail currently reads:

```bash
  mv -f "$staging" "$self" || { rm -f "$staging"; die "failed to install update to $self"; }
  info "Updated ocp: $VERSION -> $newver"
```

Insert the notes call between the `mv` and the `info` lines so notes print above the summary:

```bash
  mv -f "$staging" "$self" || { rm -f "$staging"; die "failed to install update to $self"; }
  print_release_notes "$VERSION" "$newver"
  info "Updated ocp: $VERSION -> $newver"
```

- [ ] **Step 6: Bump VERSION**

In `ocp`, change the version line from:

```bash
VERSION="0.5.1"
```

to:

```bash
VERSION="0.6.0"
```

- [ ] **Step 7: Prepend the 0.6.0 entry to CHANGELOG.md**

In `CHANGELOG.md`, insert this section directly above the `## 0.5.1` line:

```markdown
## 0.6.0
- `ocp update` now prints release notes (CHANGELOG.md sections) for the versions you update across
- add `OCP_CHANGELOG_URL` to override the changelog source

```

- [ ] **Step 8: Syntax-check the script**

Run: `bash -n ocp`
Expected: no output, exit 0.

- [ ] **Step 9: Run the changelog test to verify it passes**

Run: `bash tests/test_changelog.sh`
Expected: `RESULTS: pass=9 fail=0` (all assertions pass).

- [ ] **Step 10: Run the full suite**

Run: `bash tests/run.sh`
Expected: ends with `ALL SUITES PASSED`.

- [ ] **Step 11: Commit**

```bash
git add ocp tests/test_changelog.sh CHANGELOG.md
git commit -m "ocp: show release notes from CHANGELOG.md on update (0.6.0)"
```

---

## Task 3: Update docs

Document the new behavior, the env var, and the maintenance rule. No code; no version bump (docs-only).

**Files:**
- Modify: `README.md` (env-var table; the `ocp update` paragraph)
- Modify: `CLAUDE.md` (Versioning + Development Rules; note the section-header contract)

- [ ] **Step 1: Add OCP_CHANGELOG_URL to the README env-var table**

In `README.md`, in the "Environment variables" table, add a row immediately after the `OCP_UPDATE_URL` row:

```markdown
| `OCP_CHANGELOG_URL` | Source URL for release notes shown by `ocp update` (default: `CHANGELOG.md` alongside `OCP_UPDATE_URL`) |
```

- [ ] **Step 2: Mention notes-on-update in the README**

In `README.md`, at the end of the paragraph describing `ocp update` (the one that starts "`ocp update` replaces the running script in place..."), append:

```markdown
After a successful update it prints the `CHANGELOG.md` entries for every version
between your old copy and the new one (set `OCP_CHANGELOG_URL` to point
elsewhere). If the changelog can't be fetched the update still proceeds.
```

- [ ] **Step 3: Update CLAUDE.md Versioning + Development Rules**

In `CLAUDE.md`, under "## Versioning", add a bullet:

```markdown
- Every behavior change bumps `VERSION` **and** prepends a matching `## X.Y.Z`
  section to `CHANGELOG.md` in the same commit. `ocp update` parses those
  headers to show release notes, so the header format (`## X.Y.Z`, no `v`) is a
  contract — keep it exact.
```

And under "## Development Rules", add a bullet:

```markdown
- When bumping `VERSION`, add the matching `CHANGELOG.md` entry (newest first)
```

- [ ] **Step 4: Verify docs reference the real env var**

Run: `grep -n OCP_CHANGELOG_URL README.md CLAUDE.md ocp`
Expected: matches in `README.md` (table) and `ocp` (config line from Task 2); CLAUDE.md need not name it directly.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document OCP_CHANGELOG_URL and release-notes-on-update"
```

---

## Self-Review Notes

- **Spec coverage:** source/format (Task 1 + Task 2 step 7), URL derivation + override (step 3), behavior incl. no-op skip and (old, new] range (steps 4–5, tests in step 1), non-fatal failure (`print_release_notes` returns 0; graceful-degradation test), backfill (Task 1), ripples — VERSION (step 6), CLAUDE.md/README (Task 3) — all mapped.
- **Type/name consistency:** `CHANGELOG_URL`, `ver_gt`, `print_release_notes`, `OCP_CHANGELOG_URL` are used identically across config, helpers, call site, and tests.
- **Range semantics:** `ver_gt v old && ! ver_gt v new` ⇒ `old < v <= new`, the half-open `(old, new]` from the spec. The test fixes `cur` (e.g. 0.5.1) between `0.0.1` (excluded) and `9.9.8`/`9.9.9` (included) so it's deterministic regardless of the repo's current version.
- **Test count:** 9 assertions in `test_changelog.sh` (5 + 2 + 2 across the three blocks → step 9 expects `pass=9`); adjust the expected count if assertions are edited.
