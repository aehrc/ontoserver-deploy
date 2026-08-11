# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> Note: this section covers the fixes made during the pre-merge review of the `update-charts`
> branch. Earlier changes on the branch are not yet back-filled here.

### Added

- `ontoserver.deployment.allowScaledReadWrite` — opt in to the unsupported scaled read-write
  topology. Scaled deployments must otherwise be read-only: each replica keeps its own Lucene
  index on its own PVC, so content written through the round-robin Service is indexed only on
  the replica that served the write, and `$expand`/`$validate-code` then fail on the others.
- `ontoserver.deployment.podDisruptionBudget.maxUnavailable` and `.unhealthyPodEvictionPolicy`
  as real values rather than commented-out suggestions.
- Opt-in security context: `ontoserver.deployment.podSecurityContext`,
  `.containerSecurityContext`, `.db.containerSecurityContext` and `.automountServiceAccountToken`.
  The chart previously set no security context anywhere, so pods ran as root. All four default to
  unset, so upgrading an existing release renders a byte-identical pod spec and rolls no pods —
  hardening has to be requested. The Postgres sidecar has its own value because it cannot share
  the Ontoserver container's: the postgres entrypoint requires uid 999.

  A verified hardened configuration is documented in the README, along with the three
  combinations that cannot be made to work non-root (the Postgres sidecar, `readOnlyRootFilesystem`,
  and Ontoserver's own HTTPS mode). Those constraints were established by running the shipped
  images under each setting, not inferred — each failure is a crash at startup.

### Fixed

- `podDisruptionBudget.minAvailable`/`.maxUnavailable` now accept percentages. The previous guard
  compared `int` against 1, and `int "25%"` is 0, so every percentage — including the `25%` form
  the values file suggested — was rejected. Percentages are emitted quoted and counts unquoted,
  as the Kubernetes `IntOrString` type requires. Setting both, setting neither, `maxUnavailable: 0`,
  and a `minAvailable` at or above the replica count are now all rejected with an actionable
  message instead of silently producing an unevictable workload.
- Configuration changes now roll the pods. `checksum/secret-config` and
  `checksum/external-secret` annotations were added to the pod template, because Ontoserver
  resolves its configuration as environment variables at container start, so a `helm upgrade`
  that changed only a Secret left the running pods on the old value indefinitely. See
  "Configuration changes and pod restarts" in the README for what is and is not covered.
- The `<release>-ontoserver-db-files` StorageClass is no longer created when
  `persistence.dbfiles.storageClass.provided.enabled` is `false`. The condition tested the
  enclosing map, which is always truthy, leaving an orphaned cluster-scoped object while the PVC
  correctly referenced `storageClass.name`.
- Registry credentials containing a `"` or `\` no longer corrupt the image pull secret, in both
  the chart-managed Secret and the External Secrets variant. The `.dockerconfigjson` was built by
  interpolating credentials into a JSON string literal, so either character produced invalid
  JSON — which the kubelet reports only as an opaque `ImagePullBackOff`.

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
