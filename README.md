# ocp

A tiny Bash tool to install and switch between multiple OpenShift versions.
It downloads `openshift-install`, `oc`, and `kubectl` from the public mirror
(<https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/>) into
`~/.local/bin`, naming each binary with its version so versions coexist. A
`use` command swaps the bare-named symlinks (`openshift-install`, `oc`,
`kubectl`) to point at whichever version you want active.

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
ocp get <version|channel>   # download, verify (sha256) and install a version
ocp get --cli-only <ver>    # only the client (oc + kubectl)
ocp get --installer-only <ver>  # only openshift-install
ocp get --use <ver>         # install, then activate it (runs 'use')
ocp use <version>           # activate a version (swap openshift-install/oc/kubectl)
ocp list                    # list installed versions (* = active, with components)
ocp list-remote [X.Y|chan]  # list versions on the mirror (e.g. 4.20, stable-4.20)
ocp remove <version>        # remove an installed version's binaries
ocp update                  # update ocp itself to the latest version
ocp --version               # print the ocp version
```

`ocp update` replaces the running script in place with the latest copy from
the project's `main` branch (set `OCP_UPDATE_URL` to point elsewhere, e.g. a
fork). It downloads to a temp file, syntax-checks it, and only swaps it in if
the version differs — so a bad download can't brick the tool.

By default `get` downloads all three binaries. `--cli-only` and
`--installer-only` (mutually exclusive) fetch just one component, and a `get`
only downloads what's missing — so running `ocp get 4.14.1` after an earlier
`ocp get --cli-only 4.14.1` just adds the installer. Add `--use` to activate
the version right after installing (it also activates if everything was
already present). When a version has only
some components installed, `ocp use` links the ones present and unsets the bare
symlink for any that are missing (warning as it does so), and `ocp list`
annotates each version with the components it has.

### Examples

```sh
ocp get 4.14.1              # exact version
ocp get stable-4.15         # channel — resolves to the concrete version
ocp list-remote 4.14        # all 4.14.z available on the mirror
ocp use 4.14.1              # openshift-install/oc/kubectl now point at 4.14.1
ocp list
```

Version arguments accept either an exact version (`4.14.1`) or a mirror
channel (`stable-4.15`, `latest-4.16`, `candidate-4.17`, `fast-4.14`, ...).
Channels are resolved to a concrete version via the mirror's `release.txt`,
so binaries are always named with the real version number.

## Platforms

The platform is auto-detected from `uname` (OS + arch):

| Host | Tarball used |
|------|--------------|
| Linux x86_64 | `linux` |
| Linux arm64 / aarch64 | `linux-arm64` |
| macOS Intel | `mac` |
| macOS Apple Silicon | `mac-arm64` |

Force it with `OCP_PLATFORM` (e.g. `OCP_PLATFORM=mac-arm64`).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `OCP_BIN_DIR` | Install directory (default `~/.local/bin`) |
| `OCP_PLATFORM` | Override the detected platform |
| `OCP_INSECURE` | Set to `1` to continue past a checksum mismatch |
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
