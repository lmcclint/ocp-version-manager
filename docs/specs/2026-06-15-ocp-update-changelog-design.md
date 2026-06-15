# ocp update — Release-Notes Summary Design

**Date:** 2026-06-15
**Status:** Approved (design), pending implementation plan

## Goal

When `ocp update` installs a newer version, print a short summary of what
changed between the user's current version and the new one — high-level release
notes — so users see what they're getting instead of a bare `Updated X -> Y`.

## Source of Truth

A hand-maintained `CHANGELOG.md` at the repo root, newest-version-first, one
section per released version:

```markdown
# Changelog

## 0.6.0
- show release notes from CHANGELOG.md during `ocp update`

## 0.5.1
- fix arm64 oc-mirror tree fallback
```

- Section headers are exactly `## X.Y.Z` (the version string, no `v` prefix,
  matching the `VERSION="X.Y.Z"` value in `ocp`).
- The body of a section is free-form Markdown (bullet list expected) and is
  printed verbatim.
- Because `ocp` is distributed as the raw file on `main`, the `CHANGELOG.md` on
  `main` is likewise the canonical changelog — no build step, no release
  artifacts.

## Fetching

- Derive the changelog URL from `UPDATE_URL` by replacing the trailing `ocp`
  path segment with `CHANGELOG.md`. With the default `UPDATE_URL`
  (`https://raw.githubusercontent.com/lmcclint/ocp-version-manager/main/ocp`)
  this yields `.../main/CHANGELOG.md`.
- Allow an explicit override via `OCP_CHANGELOG_URL`, mirroring the existing
  `OCP_UPDATE_URL` pattern. If `UPDATE_URL` was customized to something that
  does not end in `ocp`, the derived URL may be wrong; `OCP_CHANGELOG_URL` is
  the escape hatch.

## Behavior

Integrated into `cmd_update()`, with **no new subcommands and no preview/dry-run
flag** (explicitly scoped out).

1. The existing flow runs unchanged: download script, validate shebang + `bash
   -n`, read `newver`.
2. If `newver == VERSION`, print the existing `Already up to date` message and
   return. **No changelog is fetched or printed** — nothing changed.
3. If `newver != VERSION`, perform the existing atomic swap.
4. **After a successful swap**, fetch the changelog and print the notes:
   - Fetch `CHANGELOG.md` from the changelog URL.
   - Select every `## X.Y.Z` section whose version is **greater than the old
     `VERSION`** and **less than or equal to `newver`**.
   - Print the selected sections in file order (newest first), under a short
     header (e.g. `Changes in this update:`), to stderr (consistent with the
     script's `info`/`die` convention of using stderr for human-facing text).
   - Then print the existing `Updated $VERSION -> $newver` line.

### Version-range filtering

Reuse the existing portable `vsort()` helper (`sort -V`, falling back to plain
`sort`). For each `## X.Y.Z` header found in the changelog, include the section
iff `old < ver <= new`. A workable approach: collect the candidate version
strings, plus `old`, and use `vsort` to establish ordering, then keep versions
that sort after `old` and at-or-before `new`. Implementation detail for the
plan; the contract is the `(old, new]` half-open range.

## Failure Handling (non-fatal)

The changelog is informational and must never block or reverse an update:

- If the fetch fails (network error, 404, non-shell content), print a single
  note to stderr — `release notes unavailable` — and still print `Updated X ->
  Y`. Exit success.
- If the fetch succeeds but **no** sections match the range (e.g. a version
  whose entry the maintainer forgot to add), print the same
  `release notes unavailable` note and continue.
- A malformed changelog must not cause `ocp update` to fail; worst case it
  prints fewer/odd notes but the update stands.

## Backfill

Seed `CHANGELOG.md` with the existing version history so the file is useful
immediately. Versions present in git history: `0.1.0, 0.1.1, 0.2.0, 0.3.0,
0.3.1, 0.3.2, 0.4.0, 0.5.0, 0.5.1`. Reconstruct one-line summaries from
`git log`; older entries can be terse. The new `0.6.0` entry documents this
feature.

## Ripple Effects

- **`VERSION` → `0.6.0`** — this is a behavior change.
- **CLAUDE.md** — add a Development/Versioning rule: every behavior change bumps
  `VERSION` *and* adds a matching `CHANGELOG.md` entry in the same commit. Note
  the new `## X.Y.Z` section-header contract that the parser depends on.
- **README.md** — add `OCP_CHANGELOG_URL` to the environment-variable table and
  mention that `ocp update` now prints release notes.

## Testing

Add coverage to the offline suite (`tests/`), which already stubs `curl` and
uses `file://` URLs:

1. **Happy path:** with `VERSION` old (e.g. 0.5.0) and a stubbed newer script
   (0.6.0) plus a stubbed `CHANGELOG.md`, assert the 0.6.0 (and any intermediate
   e.g. 0.5.1) sections print and that 0.5.0-and-older sections do **not**.
2. **Already up to date:** assert no changelog text is printed.
3. **Graceful degradation:** changelog URL unreachable / missing section →
   `release notes unavailable` printed *and* the update still succeeds
   (`Updated X -> Y` present, exit 0).

## Non-Goals

- `ocp changelog` standalone subcommand.
- `ocp update --dry-run` / `--check` preview.
- Pulling notes from the GitHub API, git tags, or GitHub Releases.
