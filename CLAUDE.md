# CLAUDE.md

## Overview

`ocp` is a single-file Bash tool that installs and switches between multiple
OpenShift versions. It downloads versioned `openshift-install` / `oc` /
`kubectl` (and optionally `oc-mirror`) from the public OpenShift mirror into
`~/.local/bin`, naming each binary with its version so versions coexist; `ocp
use` swaps bare-named symlinks to select the active one. See `README.md` for
full user-facing docs.

## Project Structure

- Single-file Bash script: `ocp` (all logic lives here)
- Tests: `tests/run.sh` runs all suites; fully offline (stubbed curl, file:// mirrors, temp BIN_DIR)
- Docs: `README.md` must stay in sync with `usage()` output and env var table in `ocp`
- Design history: `docs/specs/` and `docs/plans/` hold the specs and
  implementation plans for past features (partial installs, oc-mirror). They
  are point-in-time artifacts — read them to understand *why* things are shaped
  the way they are, not as the current spec (the code is the source of truth)

## Repo & Distribution

- GitHub: `lmcclint/ocp-version-manager` (the local working dir may be named
  differently, e.g. `ocp-installers`)
- `ocp update` replaces the running script in place by downloading
  `https://raw.githubusercontent.com/lmcclint/ocp-version-manager/main/ocp`
  (override with `OCP_UPDATE_URL`). **The `ocp` file in this repo's `main` is
  the distributed binary** — there is no build step or release artifact.
- Because of that, a behavior change is only delivered to users once the
  `VERSION` bump lands on `main` (see Versioning). Forks point users elsewhere
  via `OCP_UPDATE_URL`.

## Versioning

- Version lives in `VERSION="X.Y.Z"` near the top of `ocp`
- Always bump the patch version on every commit that changes behavior, even small fixes. Users may `ocp update` between any two pushes.
- `ocp update` only swaps the script in if the fetched `VERSION` differs, so a
  commit that forgets to bump is a silent no-op for everyone who already ran it.
- Every behavior change bumps `VERSION` **and** prepends a matching `## X.Y.Z`
  section to `CHANGELOG.md` in the same commit. `ocp update` parses those
  headers to show release notes, so the header format (`## X.Y.Z`, no `v`) is a
  contract — keep it exact.

## Development Rules

- Run `bash tests/run.sh` and confirm all suites pass before committing
- Run `bash -n ocp` to syntax-check after edits
- Test a local copy with `install -m 0755 ocp ~/.local/bin/ocp` (or run `./ocp` directly)
- Commit style: `ocp: lowercase description` (see git log for examples)
- Keep `README.md` env var table, usage block, and examples in sync with the script's `usage()` and actual behavior
- Opt-in features use the pattern: `--with-<thing>` flag + `OCP_WITH_<THING>=1` env var
- When bumping `VERSION`, add the matching `CHANGELOG.md` entry (newest first)

## Architecture

- `cmd_get()` is the main download flow — defaults to CLI-only (oc + kubectl); installer and oc-mirror are opt-in
- `CORE_COMPONENTS` (openshift-install, oc, kubectl) vs `OPTIONAL_COMPONENTS` (oc-mirror) governs use/list/remove behavior
- oc-mirror is Linux-only, has its own fetch routine (`fetch_oc_mirror`) due to different tarball naming and arm64 mirror tree

## External Dependencies

- Runtime: `curl`, `tar`, and `sha256sum` (Linux) or `shasum` (macOS)
- The tool is tightly coupled to the layout of `mirror.openshift.com` (the
  `OCP_BASE_URL` clients tree): version dirs, `release.txt` for channel
  resolution, `sha256sum.txt` for verification, and per-platform tarball names.
  If the mirror's structure changes, fetch/list/verify logic must follow.
