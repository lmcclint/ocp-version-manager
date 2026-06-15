# Changelog

All notable changes to `ocp`. Newest first. Each `## X.Y.Z` section matches a
`VERSION` released to `main`; `ocp update` prints the sections between a user's
current version and the version they update to.

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
