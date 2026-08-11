# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> Note: this section covers the fixes made during the pre-merge review of the `update-charts`
> branch. Earlier changes on the branch are not yet back-filled here.

### Added

- `ontoserver.gateway.closureRequestTimeout` (default `300s`). The `$closure` HTTPRoute carried no
  `timeouts` block at all, so the chart's longest-running operation inherited whatever the Gateway
  implementation defaults to. Falls back to `requestTimeout` when empty.
- `ontoserver.metrics.serviceMonitor.labels`, `.interval`, `.scrapeTimeout` and
  `.namespaceSelector`. Most Prometheus installations set a non-empty `serviceMonitorSelector`, and
  a ServiceMonitor carrying no matching label is silently never discovered — nothing errors, the
  metrics just never appear.
- Validation of the release-name length, with the limits checked against a live API server. The
  binding constraint is Service names (DNS labels, capped at 63), which caps the release name at
  **33** — Helm's own cap of 53 is not low enough. Without this an over-long name yields a
  partially installed release: everything applies except one Service.

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

  A verified hardened configuration is documented in the README, along with the two
  combinations that cannot be made to work non-root (the Postgres sidecar and Ontoserver's own
  HTTPS mode). Those constraints were established by running the shipped images under each
  setting, not inferred — each failure is a crash at startup.
- `ontoserver.deployment.extraVolumes` and `.extraVolumeMounts` — arbitrary volumes and mounts for
  the Ontoserver container, rendered verbatim and appended after the chart's own entries so
  chart-managed names always win a collision. Both default to empty, so an existing release
  renders a byte-identical pod spec.

  This makes `readOnlyRootFilesystem: true` reachable, which it previously was not: the server
  needs a writable `/tmp` and the chart had no way to supply one. `/tmp` turned out to be
  load-bearing rather than just a log destination — a running server writes `spring.log`,
  `hsperfdata`, Tomcat's work directories and `downlaod-*` scratch files there. The hardened
  README recipe now includes both, asserted together by a test so it cannot ship half-applied.
- Schema validation and test coverage for `ontoserver.existingSecretConfig`, a 0.3.0 feature that
  shipped with neither. The value was accepted before (the schema has no `additionalProperties`
  restriction at that level) so this is validation and documentation rather than a functional fix:
  a non-string is now rejected with a message naming the key.

### Fixed

- Renamed `poddistributionbudget.yaml` to `poddisruptionbudget.yaml` (the resource is a
  PodDisruptionBudget). Template filenames are not part of the API, so this changes nothing at
  install time.

- A `Deployment` with persistence on a `ReadWriteOnce` volume now renders `strategy.type: Recreate`
  instead of the requested `RollingUpdate`. `RollingUpdate` cannot work there: it starts the
  replacement pod before removing the old one, and a RWO disk attaches to one node at a time, so a
  replacement scheduled elsewhere waits indefinitely on `Multi-Attach error` while the old pod is
  never torn down. Reproduced on a live cluster; it also blocks PVC expansion until the volume
  detaches. Scoped to `ReadWriteOnce`/`ReadWriteOncePod`, so `ReadWriteMany` users keep
  zero-downtime rolling upgrades, and the sidecar's `dbfiles` access mode is only consulted when
  the sidecar is enabled.

  **Upgrading an existing release**: Kubernetes defaults `spec.strategy.rollingUpdate` and refuses
  to hold it alongside `type: Recreate`. `helm upgrade` and client-side `kubectl apply` handle the
  removal; **server-side apply fails** with `spec.strategy.rollingUpdate: Forbidden`. Each row of
  that was verified on a cluster, and the README gives the one-line patch that clears it.

- `ontoserver.secretConfig` no longer fails to render on a non-string value. `b64enc` rejects
  anything but a string, so a numeric port or a boolean flag aborted the whole release with
  `wrong type for value; expected string; got int64` — and the error named only `<b64enc>`, not the
  key at fault. Values are now coerced with `toString`, matching the sibling `ontoserver.config`,
  which has always accepted them via `| quote`. Note that Helm parses YAML numbers as float64, so
  quote any value whose exact form matters; that is true of both keys and is not new.
- `envoygateway.envoyProxy.pdbMinAvailable: 0` and `.replicas: 0` are no longer silently coerced to
  1 and 2. Both were rendered with `| default`, and 0 is falsy in Go templates, so the Envoy fleet
  could not be scaled to 0 and its PodDisruptionBudget could not be set to permit full eviction.
  Same class of bug as the PodDisruptionBudget fix above. `minAvailable` now also routes through the
  shared IntOrString helper for consistency, though the quoting is not load-bearing in this field.
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
