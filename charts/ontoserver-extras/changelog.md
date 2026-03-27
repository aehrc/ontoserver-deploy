# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
