# ocp: per-component get flags + partial-install support

## Goal

Let users download just the OpenShift client (`oc`+`kubectl`) or just the
installer (`openshift-install`) for a version, and make the rest of the tool
behave correctly when a version is only partially installed.

## Phase 1 — Incorporate PR #1

Merge `pr-1` into `main`. PR #1 switches `cmd_use` from absolute to relative
symlinks so the bin dir can be moved without breaking links. Phase 2 reworks
`cmd_use`, which also tidies PR #1's `cd`-inside-loop into a single contained
subshell.

## Phase 2 — Features

### A. `ocp get` flags
- `--cli-only` — download the client tarball only (`oc` + `kubectl`).
- `--installer-only` — download the installer tarball only (`openshift-install`).
- Mutually exclusive; error if both are given.
- No flag = download everything (unchanged default).
- Flags may appear in any position; an unknown `-*` argument is an error.

### B. Skip already-present components in `get`
- installer needed only if requested **and** `openshift-install-$version` absent.
- client needed only if requested **and** `oc-$version` absent.
- If nothing is needed, print "already installed" and return. This also lets a
  plain `get` complete a previously partial install by fetching only the
  missing half.
- Download `sha256sum.txt`, tarballs, and install binaries only for the needed
  component(s).

### C. `cmd_use` tolerates partial installs
- Error only if the version has zero components installed.
- For each bare name (`openshift-install`, `oc`, `kubectl`): `rm -f` the bare
  symlink, then re-link if that version's binary exists; otherwise leave it
  unset and warn `warning: <name> not installed for <version>; '<name>' unset`.
- Performed inside a single `( cd "$BIN_DIR" … )` subshell using relative
  links (from PR #1), so the working-directory change is contained.

### D. Ripple fixes
- `active_version()` reads the `openshift-install` symlink, falling back to
  `oc` then `kubectl`, so a cli-only active version is still detected.
- `cmd_list` unions versions across all three component globs (today it globs
  only `openshift-install-*`, hiding cli-only versions) and annotates each line
  with the components present, e.g. `4.14.1  (installer, oc, kubectl)`.

### E. Docs
- Update `usage()` and `README.md` for the new flags.

## Testing
Single bash script, no existing harness. Verify with a temp `OCP_BIN_DIR`
populated with stub binaries to exercise flag parsing, dedup logic, `use`
partial behavior, and `list` annotation without network. Run one real
`get --cli-only` and one `--installer-only` against the mirror to confirm
download + checksum paths.
