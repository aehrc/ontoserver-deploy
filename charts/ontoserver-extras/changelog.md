# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

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
