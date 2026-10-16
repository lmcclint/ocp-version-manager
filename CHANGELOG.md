# Changelog

All notable changes to `ocp`. Newest first. Each `## X.Y.Z` section matches a
`VERSION` released to `main`; `ocp update` prints the sections between a user's
current version and the version they update to.

## 0.9.0
- the list commands are now `ocp list <noun>`: `list available` (was `list-versions`) and `list channels` (was `list-channels`)
- `ocp list` is unchanged and still lists installed versions; `ocp list installed` is the explicit form
- the old flat names (`list-versions`, `list-remote`, `list-channels`) still work as undocumented aliases
- `ocp list <anything-else>` is an error naming the valid nouns, rather than a guess at what you meant

## 0.8.1
- `ocp list` now shows the disk usage of each installed version, not just the total
- the summary line is relabelled `Total disk:` so the number says what it measures

## 0.8.0
- support OpenShift 5.x: `ocp get 5.0` now works before 5.0 ships a stable channel
- short versions (`X.Y`) resolve via stable, then fast, then candidate, and report which channel was used
- `--with-mirror` reports `oc-mirror is not published for <version>` and skips it, instead of failing on a missing download; `--mirror-only` still exits non-zero
- after a `get` without `--use`, name the version that is still active, so a newly installed build is never mistaken for the one on your `PATH`
- the already-installed no-op path now reports the active version too, instead of printing nothing

## 0.7.0
- `ocp get 4.18` (short major.minor version) now resolves to the latest stable channel release automatically
- hints about `fast-X.Y` and `candidate-X.Y` alternatives when using short version

## 0.6.0
- `ocp update` now prints release notes (CHANGELOG.md sections) for the versions you update across
- add `OCP_CHANGELOG_URL` to override the changelog source

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
