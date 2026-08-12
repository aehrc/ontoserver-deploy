# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0](https://github.com/aehrc/ontoserver-deploy/compare/ontoserver-extras-v0.1.1...ontoserver-extras-v0.2.0) (2026-08-12)


### Added

* **charts:** opt-in securityContext for all three charts ([ad65b5f](https://github.com/aehrc/ontoserver-deploy/commit/ad65b5f5085b0292b04887dc2de044f66de7af2b))
* **extras:** securityContext passthrough for the OTel collector ([57e69e0](https://github.com/aehrc/ontoserver-deploy/commit/57e69e0c337bf862fabc8f914eda66f99912f1ec))


### Fixed

* **charts:** closure route timeout, ServiceMonitor discovery, name limits ([c6a5ded](https://github.com/aehrc/ontoserver-deploy/commit/c6a5dedc371ed604cce5b9ae7abc559352b304e3))
* **charts:** escape credentials in image pull secrets ([70238c9](https://github.com/aehrc/ontoserver-deploy/commit/70238c9e2237d3c865491e438ae9b908cb178c56))
* **charts:** resolve pre-merge review blockers in all three charts ([f89fdf5](https://github.com/aehrc/ontoserver-deploy/commit/f89fdf5fa6b5d48d3e46671871aa18d18624b844))
* **charts:** roll pods when configuration changes ([9730e8c](https://github.com/aehrc/ontoserver-deploy/commit/9730e8cfc29d634a647a19f9705355869da31dba))
* **extras:** probe the varnish container, make traces actually ship ([ecc1294](https://github.com/aehrc/ontoserver-deploy/commit/ecc12948ca3669dd4618b5f5edc772692a08e773))


### Documentation

* back-fill and verify the changelogs against the release tags ([cdc04ae](https://github.com/aehrc/ontoserver-deploy/commit/cdc04ae4720f9da069b960c0ee0981d6c78ce77a))


### Changed

* move PV template from ontoserver-extras to ontoserver chart ([a605193](https://github.com/aehrc/ontoserver-deploy/commit/a605193481c820b0fcc7da209502c30492ba11fe))

## [0.1.1] - 2026-08-12

> Note: checked against the `ontoserver-extras-0.1.0` tag by diffing the values keys, not assembled from commit
> messages, so nothing user-facing since that release is missing.

### Added

- Chart description corrected — it still advertised a PV template, which now lives in the
  `ontoserver` chart.

- `collector.podSecurityContext` and `collector.containerSecurityContext`. The collector pod is
  built by the OpenTelemetry Operator from the `OpenTelemetryCollector` CR, so these render as CR
  fields rather than pod-spec fields: `spec.podSecurityContext` and `spec.securityContext` — the
  latter being the *container* context despite the name. Both verified against the `v1beta1` CRD
  shipped with operator 0.156.0. `spec.containerSecurityContext`, the plausible spelling, is not a
  field on the CRD. How that fails depends on the client, and both were tested against a live
  operator: `kubectl apply` rejects it with a strict decoding error, while **Helm succeeds and the
  API server prunes the field** — the release reports `deployed` and the collector runs with no
  container security context at all. The Helm path is the one that matters here and it is silent, so
  a test asserts the chart never emits that spelling.
  Validated on a cluster: the Operator (0.131.0) applies both contexts verbatim to the collector
  pod it builds, and the collector starts and runs under `readOnlyRootFilesystem` with all
  capabilities dropped.

- Readiness and liveness probes on the `varnish` container (`varnish.probes.*`, on by default).
  Only the metrics exporter sidecar had one before, so the Service began routing to a pod whose
  `varnishd` was not yet accepting connections and every rolling update dropped requests.

  Both are `tcpSocket` on the http port rather than `httpGet`. An HTTP probe would be proxied to
  Ontoserver: backend traffic on every period, and — worse — the cache marked unready whenever the
  backend was down, turning a backend outage into a cache outage and defeating the point of
  `varnish.graceSeconds`. The liveness probe is deliberately more tolerant than the readiness probe
  because a restart discards the whole cache.

  Note this is the one change here that is *not* pod-spec-neutral: the first upgrade rolls the
  Varnish Deployment once and the cache starts cold. Set `varnish.probes.enabled: false` to keep
  the previous behaviour.
- `collector.batch.sendBatchSize` and `collector.batch.timeout`, previously hardcoded.

- Opt-in security context: `varnish.podSecurityContext`, `varnish.containerSecurityContext` and
  `varnish.automountServiceAccountToken`. All default to unset, so upgrading an existing release
  leaves the pod spec byte-identical and does not discard a warm cache. The container-level value
  applies to every container in the pod — varnish, the metrics exporter and both trace sidecars —
  because they share a process namespace and are not independently isolatable.

### Fixed

- Traces now actually ship. The batch processor was configured with `timeout: 0s`, which does not
  mean "flush immediately" — it disables the flush timer, so spans were held until
  `send_batch_size` (1000) accumulated. A terminology server is usually quiet, so the practical
  effect was that tracing appeared configured and nothing arrived. Now defaults to `5s`, and a zero
  value is rejected at render time in any unit.
- The `filter/health_checks` processor now runs with `error_mode: ignore`. Its default,
  `propagate`, fails the entire batch when one condition errors, so a single span missing
  `http.url` would discard every span batched with it. The three `cache_lookup` conditions were
  also missing the nil guard the surrounding conditions already had — and a condition that errors
  is one that never matches, so the spans it should have filtered were being exported.

- Varnish now restarts when its VCL changes. `varnishd` parses `/etc/varnish/default.vcl` once
  at startup and never re-reads the mounted ConfigMap, so a `helm upgrade` that changed only a
  cache setting updated the ConfigMap, left the pod template untouched, and Varnish went on
  serving the previous VCL indefinitely. The Deployment pod template now carries a
  `checksum/config` annotation over the rendered VCL. Note this means upgrading to this version
  restarts Varnish once, discarding the warm cache.

### Changed

- The VCL body moved from `varnish-configmap.yaml` into a named template
  (`ontoserver-extras.varnish.vcl`) so the Deployment can hash exactly the VCL text. The
  rendered ConfigMap content is unchanged. The hash is deliberately independent of the chart
  version, so future releases do not restart Varnish without a VCL change.
- Chart icon URL now points at the `master` branch rather than the non-existent `main`.

## [0.1.0]

### Added

- Initial public release of the `ontoserver-extras` chart.
- Optional Varnish caching proxy support for Ontoserver deployments.
- Optional Prometheus metrics exporter support for Varnish.
- Optional OpenTelemetry tracing sidecars for Varnish.
- Optional OpenTelemetry Collector deployment support.
- Guidance for deploying alongside the main `ontoserver` chart with ArgoCD multi-source applications or plain Helm.
- Support for dedicated `$closure` backend routing when Varnish fronts a scaled Ontoserver deployment.

### Changed

- This initial `ontoserver-extras` release was created when the repository was tagged for the released `ontoserver` `0.2.0` chart.
