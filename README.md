# ocp

A Bash tool that installs and switches between multiple OpenShift versions.
It downloads `oc` and `kubectl` from the public mirror
(<https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/>) into
`~/.local/bin`. Each binary includes its version number in the name, so
multiple versions coexist. The `use` command swaps bare-named symlinks to
select the active version. The installer (`openshift-install`) and `oc-mirror`
are opt-in with flags or environment variables.

## Install

```sh
install -m 0755 ocp ~/.local/bin/ocp
```

Make sure that `~/.local/bin` is on your `$PATH`. If it is not, the script
shows a warning.

```sh
export PATH="$HOME/.local/bin:$PATH"   # add to ~/.bashrc
```

## Usage

```sh
ocp get <version|channel|X.Y>   # download CLI (oc + kubectl) only
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

`ocp update` replaces the current script with the latest copy from the `main`
branch. Set `OCP_UPDATE_URL` to use a different source (for example, a fork).
The command downloads to a temporary file and does a syntax check. If the
version is different, it replaces the old file. A bad download cannot break the
tool.

After a successful update, the command shows the `CHANGELOG.md` entries
between your old version and the new one. Set `OCP_CHANGELOG_URL` to use a
different changelog source. If the changelog cannot be fetched, the update
still completes.

By default, `get` downloads only the CLI (`oc` + `kubectl`). The installer and
oc-mirror are opt-in. Add `--with-installer` or `--with-mirror` to include
them, or set the environment variable (`OCP_WITH_INSTALLER=1`,
`OCP_WITH_MIRROR=1`) to make it permanent. `--cli-only` and `--installer-only`
are mutually exclusive. Each fetches one component.

A `get` downloads only the components that are not yet installed. For example,
`ocp get --with-installer 4.14.1` after an earlier `ocp get 4.14.1` adds only
the installer. Add `--use` to activate the version after the download
completes.

When a version has only some components installed, `ocp use` links the ones
that are present. It removes the bare symlink for components that are not
installed and shows a warning. `ocp list` shows each version with the
components it has.

`ocp list-versions` lists the versions on the mirror. You can filter by a
minor version (`4.14`) or a channel (`stable-4.20`). A channel is reduced to
its minor version line. `list-remote` is a hidden alias for `list-versions`.

`ocp list-channels <X.Y>` lists the release channels for a minor version
(`candidate-`, `fast-`, `latest-`, `stable-`). It shows the version that each
channel points to. Use this to see what a channel resolves to before you
install.

Both commands mark versions that you have installed locally with
`(installed: ...)` and the components that are present:

```
$ ocp list-channels 4.20
candidate-4.20   4.20.25
fast-4.20        4.20.24  (installed: installer, oc, kubectl)
latest-4.20      4.20.24  (installed: installer, oc, kubectl)
stable-4.20      4.20.24  (installed: installer, oc, kubectl)
```

### Examples

```sh
ocp get 4.18                       # short version — latest stable-4.18
ocp get 4.14.1                     # CLI only (oc + kubectl)
ocp get --with-installer 4.14.1    # CLI + installer
ocp get stable-4.15                # channel — resolves to the concrete version
ocp list-versions 4.14             # all 4.14.z available on the mirror
ocp list-channels 4.14             # 4.14 channels and the version each points to
ocp use 4.14.1                     # oc/kubectl now point at 4.14.1
ocp list
```

Version arguments accept three forms:

- An exact version (`4.14.1`)
- A mirror channel (`stable-4.15`, `latest-4.16`, `candidate-4.17`, `fast-4.14`)
- A short major.minor (`4.18`), which resolves through the `stable` channel.

Channels resolve to a concrete version through the mirror's `release.txt`. The
binaries always use the real version number in their names.

### oc-mirror

`oc-mirror` is an optional fourth component. It is opt-in because the mirror
ships it only for **Linux** (x86_64 and arm64). There is no macOS build.

You can fetch it in three ways:

- With a normal `get`, add `--with-mirror`.
- On its own, use `--mirror-only`.
- To include it with every `get`, export `OCP_WITH_MIRROR=1`.

After you install it, `oc-mirror` works like the other components. `ocp use`
links the bare `oc-mirror` name. `ocp list` and `ocp remove` include it.

From version 4.16, the mirror publishes two builds: `oc-mirror.tar.gz` (RHEL8)
and `oc-mirror.rhel9.tar.gz` (RHEL9, which oc-mirror v2 uses). If the RHEL9
build is available, `ocp` installs it. If not, it installs the RHEL8 build.
Use `--rhel8` to force the RHEL8 build.

To switch the build for a version that is already installed, remove it first
with `ocp remove <ver>`. On arm64 hosts, the tool downloads the binary from
the mirror's `arm64/` client tree automatically.

## Platforms

The platform is detected automatically from `uname` (OS + architecture):

| Host | Tarball |
|------|---------|
| Linux x86_64 | `linux` |
| Linux arm64 / aarch64 | `linux-arm64` |
| macOS Intel | `mac` |
| macOS Apple Silicon | `mac-arm64` |

To override the detected platform, set `OCP_PLATFORM` (for example,
`OCP_PLATFORM=mac-arm64`).

All four platforms are served from one mirror directory. The `x86_64` in the
default URL is the mirror's cross-platform client tree. The `linux-arm64`,
`mac`, and `mac-arm64` tarballs all live there. The arm64 binaries are not in
the separate `arm64/` tree.

Linux `ppc64le` and `s390x` are **not** supported. The client tarballs exist
for those architectures, but `openshift-install` does not. The tool rejects
those architectures unless you set `OCP_PLATFORM` and `OCP_BASE_URL` yourself.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `OCP_BIN_DIR` | Install directory (default `~/.local/bin`) |
| `OCP_PLATFORM` | Override the detected platform |
| `OCP_INSECURE` | Set to `1` to continue past a checksum mismatch |
| `OCP_WITH_INSTALLER` | Set to `1` to always include the installer with `get` |
| `OCP_WITH_MIRROR` | Set to `1` to always include oc-mirror with `get` |
| `OCP_BASE_URL` | Mirror clients directory (default: the cross-platform `x86_64` tree) |
| `OCP_UPDATE_URL` | Source URL for `ocp update` (default: GitHub raw, `main`) |
| `OCP_CHANGELOG_URL` | Source URL for release notes from `ocp update` (default: `CHANGELOG.md` alongside `OCP_UPDATE_URL`) |

## Checksums and Apple Silicon

Before extraction, the tool compares each tarball against the mirror's
`sha256sum.txt`. On most platforms, a mismatch stops the install.

**Exception:** Apple re-signs and notarizes the macOS Apple Silicon
(`mac-arm64`) binaries after the mirror publishes `sha256sum.txt`. The
published hashes never match the served files. For `mac-arm64`, `ocp` reports
the mismatch as a note and continues. Intel Mac, Linux, and Linux arm64
tarballs all match.

## Requirements

`curl`, `tar`, and one of: `sha256sum` (Linux) or `shasum` (macOS).

## Tests

An offline test suite lives in `tests/`. It uses a fake `curl`, `file://`
update sources, and a temporary `OCP_BIN_DIR`. It does not need mirror access.

```sh
tests/run.sh                 # test the ocp in this repo
OCP=/path/to/ocp tests/run.sh
```
