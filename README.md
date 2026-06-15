# ocp

A tiny Bash tool to install and switch between multiple OpenShift versions.
It downloads `oc` and `kubectl` from the public mirror
(<https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/>) into
`~/.local/bin`, naming each binary with its version so versions coexist. A
`use` command swaps the bare-named symlinks to point at whichever version you
want active. The installer (`openshift-install`) and `oc-mirror` are opt-in
via flags or environment variables.

## Install

```sh
install -m 0755 ocp ~/.local/bin/ocp
```

Make sure `~/.local/bin` is on your `$PATH` (the script warns if it isn't):

```sh
export PATH="$HOME/.local/bin:$PATH"   # add to ~/.bashrc
```

## Usage

```sh
ocp get <version|channel>       # download CLI (oc + kubectl) only
ocp get --with-installer <ver>  # also fetch openshift-install
ocp get --with-mirror <ver>     # also fetch oc-mirror (Linux only)
ocp get --installer-only <ver>  # only openshift-install
ocp get --mirror-only <ver>     # only oc-mirror (Linux only)
ocp get --use <ver>             # install, then activate it (runs 'use')
ocp use <version>               # activate a version (swap symlinks)
ocp list                        # list installed versions (* = active, with components + total size)
ocp list-versions [X.Y|chan]    # list versions on the mirror (e.g. 4.20, stable-4.20)
ocp list-channels <X.Y>        # list a minor's channels + the version each points to
ocp remove <version>            # remove an installed version's binaries
ocp update                      # update ocp itself to the latest version
ocp --version                   # print the ocp version
```

`ocp update` replaces the running script in place with the latest copy from
the project's `main` branch (set `OCP_UPDATE_URL` to point elsewhere, e.g. a
fork). It downloads to a temp file, syntax-checks it, and only swaps it in if
the version differs — so a bad download can't brick the tool.

By default `get` downloads only the CLI (`oc` + `kubectl`). The installer and
oc-mirror are opt-in — add `--with-installer` or `--with-mirror` to include
them, or set the corresponding env var (`OCP_WITH_INSTALLER=1`,
`OCP_WITH_MIRROR=1`) to make it permanent. `--cli-only` and `--installer-only`
(mutually exclusive) fetch just one component, and a `get` only downloads
what's missing — so running `ocp get --with-installer 4.14.1` after an earlier
`ocp get 4.14.1` just adds the installer. Add `--use` to activate the version
right after installing. When a version has only some components installed,
`ocp use` links the ones present and unsets the bare symlink for any that are
missing (warning as it does so), and `ocp list` annotates each version with
the components it has.

`ocp list-versions` lists the concrete versions on the mirror, optionally
filtered by an `X.Y` (or a channel like `stable-4.20`, which is reduced to its
`4.20` line). `ocp list-channels <X.Y>` lists that minor's release channels
(`candidate-`, `fast-`, `latest-`, `stable-`) alongside the version each
currently resolves to — handy for seeing, e.g., what `stable-4.20` points at
before installing. (`list-remote` remains as a hidden alias for
`list-versions`.)

Both commands annotate anything you already have installed locally with
`(installed: ...)` and the components present, so you can tell at a glance
what's downloaded:

```
$ ocp list-channels 4.20
candidate-4.20   4.20.25
fast-4.20        4.20.24  (installed: installer, oc, kubectl)
latest-4.20      4.20.24  (installed: installer, oc, kubectl)
stable-4.20      4.20.24  (installed: installer, oc, kubectl)
```

### Examples

```sh
ocp get 4.14.1                     # CLI only (oc + kubectl)
ocp get --with-installer 4.14.1    # CLI + installer
ocp get stable-4.15                # channel — resolves to the concrete version
ocp list-versions 4.14             # all 4.14.z available on the mirror
ocp list-channels 4.14             # 4.14 channels and the version each points to
ocp use 4.14.1                     # oc/kubectl now point at 4.14.1
ocp list
```

Version arguments accept either an exact version (`4.14.1`) or a mirror
channel (`stable-4.15`, `latest-4.16`, `candidate-4.17`, `fast-4.14`, ...).
Channels are resolved to a concrete version via the mirror's `release.txt`,
so binaries are always named with the real version number.

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

## Platforms

The platform is auto-detected from `uname` (OS + arch):

| Host | Tarball used |
|------|--------------|
| Linux x86_64 | `linux` |
| Linux arm64 / aarch64 | `linux-arm64` |
| macOS Intel | `mac` |
| macOS Apple Silicon | `mac-arm64` |

Force it with `OCP_PLATFORM` (e.g. `OCP_PLATFORM=mac-arm64`).

All four of these are served from a single mirror directory. Despite the
`x86_64` in the default URL, that path is the mirror's *cross-platform* client
tree — the `linux-arm64`, `mac`, and `mac-arm64` tarballs all live there too
(the arm64 binaries are not in the sibling `arm64/` tree). Linux `ppc64le` and
`s390x` are **not** supported: the client tarballs exist there but the matching
`openshift-install` does not, and those arches are rejected unless you set
`OCP_PLATFORM`/`OCP_BASE_URL` yourself.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `OCP_BIN_DIR` | Install directory (default `~/.local/bin`) |
| `OCP_PLATFORM` | Override the detected platform |
| `OCP_INSECURE` | Set to `1` to continue past a checksum mismatch |
| `OCP_WITH_INSTALLER` | Set to `1` to always include the installer in a default `get` |
| `OCP_WITH_MIRROR` | Set to `1` to always include oc-mirror in a default `get` |
| `OCP_BASE_URL` | Mirror clients directory (default: the cross-platform `x86_64` tree) |
| `OCP_UPDATE_URL` | Source URL for `ocp update` (default: GitHub raw, `main`) |

## Checksums & Apple Silicon

Each tarball is verified against the mirror's `sha256sum.txt` before
extraction; on most platforms a mismatch aborts the install.

**Exception:** the macOS Apple Silicon (`mac-arm64`) binaries are re-signed
and notarized by Apple *after* the mirror publishes `sha256sum.txt`, so their
published hashes never match the served files. For `mac-arm64`, `ocp` reports
the mismatch as a note and continues. (Intel-mac, linux, and linux-arm64 all
verify cleanly.)

## Requirements

`curl`, `tar`, and either `sha256sum` (Linux) or `shasum` (macOS).

## Tests

A small offline test suite lives in `tests/` — it stubs the network (a fake
`curl`, `file://` update sources) and a temporary `OCP_BIN_DIR`, so it needs no
mirror access:

```sh
tests/run.sh                 # test the ocp in this repo
OCP=/path/to/ocp tests/run.sh
```
