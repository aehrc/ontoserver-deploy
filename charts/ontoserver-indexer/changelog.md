# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0](https://github.com/aehrc/ontoserver-deploy/compare/ontoserver-indexer-v0.2.0...ontoserver-indexer-v0.3.0) (2026-08-12)


### Added

* add Basic auth env vars to job template ([dd3585b](https://github.com/aehrc/ontoserver-deploy/commit/dd3585b0e767256a316286b40fdfef80c0163cf9))
* add job args and JAVA_OPTS env var ([32aba40](https://github.com/aehrc/ontoserver-deploy/commit/32aba40cd9f8b9a49de40cec13254d5078bc89b4))
* add job template structure, image and resources ([e030c2e](https://github.com/aehrc/ontoserver-deploy/commit/e030c2e806662d9594b9124745a96aee2de28855))
* add OAuth2 env vars to job template ([11b7938](https://github.com/aehrc/ontoserver-deploy/commit/11b7938506d93c749d72371b41eccc21ba332fb2))
* add optional env vars (languageRefsets, resolveSkew, sentry) ([e4c7e25](https://github.com/aehrc/ontoserver-deploy/commit/e4c7e25f149f557d762f917b8fee608eeef61d37))
* add secret template and tests ([ba68bc1](https://github.com/aehrc/ontoserver-deploy/commit/ba68bc1e7f13f7411ba3ceda7401239d17a41ea6))
* add snomed-au example and complete ontoserver-indexer chart ([9572ff0](https://github.com/aehrc/ontoserver-deploy/commit/9572ff03c320b8e0e7daa411242a5c6258b5aaf8))
* add validate-values template and tests ([758e3c5](https://github.com/aehrc/ontoserver-deploy/commit/758e3c5111bd67a0af49a3e5a823ce773f5b99c6))
* **charts:** extraVolumes/extraVolumeMounts for ontoserver and indexer ([83f937f](https://github.com/aehrc/ontoserver-deploy/commit/83f937f3f1970b044ae02eeb30561e3b50db9378))
* **charts:** opt-in securityContext for all three charts ([ad65b5f](https://github.com/aehrc/ontoserver-deploy/commit/ad65b5f5085b0292b04887dc2de044f66de7af2b))
* scaffold ontoserver-indexer chart ([340d44d](https://github.com/aehrc/ontoserver-deploy/commit/340d44de320b853b23dbd66dcf4d4ee8322608e0))


### Fixed

* add type: Opaque to secret template ([f7718ae](https://github.com/aehrc/ontoserver-deploy/commit/f7718aef739996168de60795a45415e7edb567af))
* address final review issues (validation, labels, CPU, NOTES) ([dcc212b](https://github.com/aehrc/ontoserver-deploy/commit/dcc212b772695d6af7dbe3a36d6ad4fbccda8b60))
* **charts:** escape credentials in image pull secrets ([70238c9](https://github.com/aehrc/ontoserver-deploy/commit/70238c9e2237d3c865491e438ae9b908cb178c56))
* **charts:** resolve pre-merge review blockers in all three charts ([f89fdf5](https://github.com/aehrc/ontoserver-deploy/commit/f89fdf5fa6b5d48d3e46671871aa18d18624b844))
* correct helpers whitespace, add Chart.yaml annotations ([531cf63](https://github.com/aehrc/ontoserver-deploy/commit/531cf635392638af15ee451c76df4abf6023435e))
* remove redundant null guard in rf2.files range ([e14f4e6](https://github.com/aehrc/ontoserver-deploy/commit/e14f4e63dae02051e6e4a062af5059864c180c35))
* use fixture file for two-security-labels test ([71a89dd](https://github.com/aehrc/ontoserver-deploy/commit/71a89dd8bd5855aad63d8d012686b38c8b0efc2f))


### Documentation

* back-fill and verify the changelogs against the release tags ([cdc04ae](https://github.com/aehrc/ontoserver-deploy/commit/cdc04ae4720f9da069b960c0ee0981d6c78ce77a))

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
