# ocp: manage oc-mirror as a fourth component

## Goal

Let `ocp` download, verify, install, activate, list, and remove the
`oc-mirror` binary the same way it already manages `openshift-install`, `oc`,
and `kubectl`. Scope is binary management only — `ocp` does **not** wrap the
oc-mirror workflow (ImageSetConfiguration, mirror-to-disk, registry sync).

## Background: how the mirror packages oc-mirror

Findings from `mirror.openshift.com/.../clients/ocp/<ref>/sha256sum.txt`:

- The tarball is **not** version- or platform-qualified — it is always
  `oc-mirror.tar.gz`, and it extracts to a single binary named `oc-mirror`.
  (Contrast the others: `openshift-install-<platform>-<version>.tar.gz`.)
- **Linux only.** There is no mac build at all.
- From **4.16+** the mirror ships two variants: `oc-mirror.tar.gz` (RHEL8 /
  v1-oriented build) and `oc-mirror.rhel9.tar.gz` (RHEL9 build, what oc-mirror
  v2 wants). Earlier versions have only the plain `oc-mirror.tar.gz`.
- arm64 oc-mirror lives in a **separate** mirror tree
  (`.../arm64/clients/ocp/...`), unlike `oc`/`openshift-install` which are all
  served from the x86_64 tree via platform tokens.

These break every naming/tree assumption the rest of the script relies on, so
oc-mirror's fetch is isolated rather than threaded through the shared loop.

## Model

`oc-mirror` is an **optional** fourth component; `openshift-install`, `oc`, and
`kubectl` remain "core". Locally it is stored version-qualified as
`oc-mirror-<version>` and activated as the bare `oc-mirror` symlink by `use`,
exactly like the others. The only differences are in fetch and in being
optional (it must not introduce new noise for users who never install it).

## Decisions (from brainstorming)

- **Opt-in to `get` via both flags plus an env var:** `--mirror-only`,
  `--with-mirror`, and `OCP_WITH_MIRROR=1` (always include oc-mirror in default
  gets). oc-mirror is never a default component otherwise — it is Linux-only
  and niche.
- **Variant: prefer rhel9, fall back to rhel8.** Use `oc-mirror.rhel9.tar.gz`
  when present (4.16+), else `oc-mirror.tar.gz`. `--rhel8` forces the plain
  build.
- **arm64: derive the arm64 URL** by substituting the `x86_64` path segment for
  `arm64` when fetching oc-mirror on an arm64 host.

## Components

### A. `fetch_oc_mirror <ref> <version>` (new helper)

A dedicated, self-contained fetch routine (isolated because oc-mirror's tree,
tarball name, and variants differ from the core components):

- **Platform guard:** accept only `linux` / `linux-arm64`. On `mac` /
  `mac-arm64`, `die` with a clear "oc-mirror is Linux-only" message. This guard
  runs only when oc-mirror is actually requested, so a normal mac `get` is
  unaffected.
- **Tree selection:** x86_64 → `BASE_URL` unchanged; arm64 → derive by
  replacing the `x86_64` path segment with `arm64`
  (e.g. `sed 's#/x86_64/#/arm64/#'`). If a custom `OCP_BASE_URL` has no such
  segment the substitution is a no-op — documented caveat.
- **Variant selection:** download the chosen tree's `<ref>/sha256sum.txt`.
  If `--rhel8` was given, use `oc-mirror.tar.gz`. Otherwise use
  `oc-mirror.rhel9.tar.gz` when it appears in the sum file, else
  `oc-mirror.tar.gz`.
- Download the tarball → `verify_checksum` (reused unchanged; the generic
  tarball name is exactly what is listed in `sha256sum.txt`) → extract the
  single `oc-mirror` binary → `install -m 0755` as
  `$BIN_DIR/oc-mirror-<version>`.
- The mac-arm64 checksum-mismatch leniency does not apply (no mac build).

### B. `cmd_get` flag/selection model

Three want-booleans: `want_installer`, `want_cli`, `want_mirror`.

- Defaults: `want_installer=1`, `want_cli=1`; `want_mirror=1` **iff**
  `OCP_WITH_MIRROR` is set (non-empty), else `0`.
- `--cli-only` → `want_installer=0` (unchanged).
- `--installer-only` → `want_cli=0` (unchanged).
- `--with-mirror` → `want_mirror=1` (additive).
- `--mirror-only` → `want_installer=0`, `want_cli=0`, `want_mirror=1`.
  **Conflicts** with `--cli-only`, `--installer-only`, and `--with-mirror`
  (error).
- `--rhel8` → variant override; only meaningful when oc-mirror is wanted.
- Validation: at least one component must be selected (generalizes the existing
  "--cli-only and --installer-only are mutually exclusive" check).

"Only fetch what's missing" and the "already installed" early return both
extend to include oc-mirror (`need_mirror = want_mirror && ! -x
oc-mirror-<version>`). Once `oc-mirror-<version>` exists, the variant is not
re-checked — switching rhel8↔rhel9 requires `remove` first. Documented.

Orchestration: the installer/client path is unchanged (shared loop, x86_64
tree). When `need_mirror`, `cmd_get` calls `fetch_oc_mirror` separately so the
two-tree / variant logic stays out of the shared loop.

### C. Integration into existing commands

oc-mirror is added as an **optional** component everywhere the core triple is
iterated:

- `installed_components`: append `oc-mirror` when `-x oc-mirror-<version>`.
- `cmd_list`: include `oc-mirror` in the component union that gathers versions
  and files (so it shows up and counts toward the total size).
- `cmd_remove`: include `oc-mirror` in the removal loop.
- `active_version`: include `oc-mirror` in the fallback list so a mirror-only
  active version is still detected.
- `cmd_use`:
  - The "at least one component present" guard includes oc-mirror, so a
    mirror-only install is usable.
  - In the symlink loop oc-mirror is **optional**: linked if
    `oc-mirror-<version>` is present, silently unlinked/skipped if not — **no
    warning** (core components keep their warn-on-missing behavior). This keeps
    `use` quiet for users who never install oc-mirror.

### D. Small cleanup (reduce drift)

The core triple is currently hardcoded in five places. Define the component
lists once — e.g. `CORE_COMPONENTS=(openshift-install oc kubectl)` plus
`oc-mirror` handled as the optional component — and consume that in
`active_version`, `installed_components`, `cmd_use`, `cmd_list`, and
`cmd_remove`. Stay within the existing code style; no unrelated refactoring.

## Docs

Update `README.md`:

- New `get` flags: `--mirror-only`, `--with-mirror`, `--rhel8`.
- `OCP_WITH_MIRROR` env var in the Environment section.
- Note oc-mirror is Linux-only (x86_64 + arm64), the rhel9-preference behavior,
  and the arm64 separate-tree derivation.

Update the in-script `usage()` to match.

## Tests

New `tests/test_mirror.sh`, offline via the existing fake-curl + `stub`
harness:

- Flag parsing and conflict detection (`--mirror-only` vs
  `--cli-only`/`--installer-only`/`--with-mirror`).
- Variant selection: rhel9 present → picks `oc-mirror.rhel9.tar.gz`;
  rhel9 absent → picks `oc-mirror.tar.gz`; `--rhel8` forces plain.
- arm64 URL derivation (assert the fetch hits an `arm64` tree URL).
- mac platform guard errors clearly.
- oc-mirror appears in `list` / `installed_components`, is linkable by `use`
  (and `use` emits no warning when oc-mirror is absent for the target version),
  and is removed by `remove`.

For end-to-end extract/install, the fake curl can serve a small real
`oc-mirror.tar.gz` (a gzip tarball containing an `oc-mirror` stub) so the
extraction path is exercised; the bulk of the new logic is covered without
network.

## Out of scope

- Wrapping the oc-mirror workflow (ImageSetConfiguration generation,
  mirror-to-disk / disk-to-mirror, registry interaction).
- mac support for oc-mirror (no upstream build).
- Re-fetching to switch an already-installed version's rhel8/rhel9 variant
  without an explicit `remove` first.
