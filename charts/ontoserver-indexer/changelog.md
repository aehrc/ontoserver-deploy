# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-12

> Note: checked against the `ontoserver-indexer-0.1.0` tag by diffing the values keys, not assembled from commit
> messages, so nothing user-facing since that release is missing.

### Added

- `resources.heapGb` — sets the JVM `-Xmx` independently of the container memory limit. The
  default is `memoryGb - 2`, leaving 2 GiB for non-heap JVM memory (metaspace, code cache,
  thread stacks, GC structures, direct buffers). Previously `-Xmx` was set equal to the memory
  limit, which guarantees an eventual OOMKill.
- Validation rejecting a heap that meets or exceeds `resources.memoryGb`, so the misconfiguration
  fails at install time rather than as an OOMKill mid-index.
- Opt-in security context: `job.podSecurityContext`, `job.containerSecurityContext` and
  `job.automountServiceAccountToken`, all unset by default so existing users see no change. The
  README documents a hardened configuration; note a non-root Job needs an `fsGroup` that can
  write the output PVC.
- `job.extraVolumes` and `job.extraVolumeMounts` — arbitrary volumes and mounts for the indexer
  container, rendered verbatim and appended after the chart's own `output-volume`/`input-volume`
  entries so those win a name collision. Both default to empty, so nothing changes for existing
  users. This makes `readOnlyRootFilesystem: true` reachable: the indexer runs the same Spring Boot
  image as the server and needs a writable `/tmp`, which the chart previously could not supply.

### Fixed

- Registry credentials containing a `"` or `\` no longer corrupt the image pull secret. The
  `.dockerconfigjson` was built by interpolating the username and password into a JSON string
  literal with `printf`, so either character produced invalid JSON — which the kubelet reports
  only as an opaque `ImagePullBackOff`. It is now built with `dict` and `toJson`.

### Changed

- The default Job name is now `<release name>-<release revision>` rather than the release name,
  so an upgrade creates a new Job instead of failing on the immutable pod template of the
  existing one.

## [0.1.0]

### Added

- Initial public release of the `ontoserver-indexer` chart.
- A one-shot Kubernetes Job for indexing terminology content with the Ontoserver CLI.
- Support for SNOMED CT RF2 packages and LOINC distribution ZIP inputs.
- Support for reading input files from HTTPS locations or a mounted PVC.
- Support for publishing the generated archive to a syndication server, writing it to a PVC, or both.
- Support for OAuth2 client credentials or HTTP Basic authentication when publishing to the syndication server.
- Automatic creation of a pull secret for the default authenticated `quay.io/aehrc/ontoserver` image, with support for pre-existing image pull secrets as well.
- Controls for job naming, TTL cleanup, and scheduling on spot or preemptible node pools.

### Changed

- This initial `ontoserver-indexer` release was created when the repository was tagged for the released `ontoserver` `0.2.0` chart.
