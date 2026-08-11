# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
