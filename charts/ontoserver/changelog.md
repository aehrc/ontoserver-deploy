# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-04-01

### Added

- `existingSecretConfig` — reference a pre-existing Kubernetes Secret by name; its keys are injected as environment variables via `envFrom`, enabling GitOps workflows (e.g. ArgoCD) where secrets are managed outside the chart.
- Chart-native External Secrets support for registry credentials via `ontoserver.externalSecret.imagePullSecret`.
- Automatic wiring of the generated external pull secret into workload `imagePullSecrets` for both `Deployment` and `StatefulSet` modes.
- Optional `secretStoreRef` overrides for the image pull secret, allowing registry credentials to come from a different secret store than other external secrets.
- Unit test coverage for external pull secret rendering, workload wiring, and validation behaviour.

### Changed

- Replaced the manual ExternalSecret-based quay.io pull-secret example with the chart-managed `externalSecret.imagePullSecret` workflow in the chart documentation.

### Fixed

- Added render-time validation to require both `imagePullSecret.data.username.key` and `imagePullSecret.data.password.key` to be set together.
- Added render-time validation to block the unsupported combination of `certmanager.enabled=true` with ALB ingress.

## [0.2.0]

### Added

- Initial public release of the `ontoserver` chart.

### Changed

- Established `0.2.0` as the first released chart version. Version `0.1.0` was never released.
