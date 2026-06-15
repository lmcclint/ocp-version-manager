# CLAUDE.md

## Project Structure

- Single-file Bash script: `ocp` (all logic lives here)
- Tests: `tests/run.sh` runs all suites; fully offline (stubbed curl, file:// mirrors, temp BIN_DIR)
- Docs: `README.md` must stay in sync with `usage()` output and env var table in `ocp`

## Versioning

- Version lives in `VERSION="X.Y.Z"` near the top of `ocp`
- Always bump the patch version on every commit that changes behavior, even small fixes. Users may `ocp update` between any two pushes.

## Development Rules

- Run `bash tests/run.sh` and confirm all suites pass before committing
- Run `bash -n ocp` to syntax-check after edits
- Commit style: `ocp: lowercase description` (see git log for examples)
- Keep `README.md` env var table, usage block, and examples in sync with the script's `usage()` and actual behavior
- Opt-in features use the pattern: `--with-<thing>` flag + `OCP_WITH_<THING>=1` env var

## Architecture

- `cmd_get()` is the main download flow — defaults to CLI-only (oc + kubectl); installer and oc-mirror are opt-in
- `CORE_COMPONENTS` (openshift-install, oc, kubectl) vs `OPTIONAL_COMPONENTS` (oc-mirror) governs use/list/remove behavior
- oc-mirror is Linux-only, has its own fetch routine (`fetch_oc_mirror`) due to different tarball naming and arm64 mirror tree
