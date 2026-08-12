# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0](https://github.com/aehrc/ontoserver-deploy/compare/ontoserver-v0.4.0...ontoserver-v0.5.0) (2026-08-12)


### ⚠ BREAKING CHANGES

* **ontoserver:** the chart no longer installs an ingress controller.

### Added

* **chart:** add ExternalSecret template for image pull secret ([33ad52c](https://github.com/aehrc/ontoserver-deploy/commit/33ad52ca7701930d9fad6bc08ecefbd45703065a))
* **chart:** add imagePullSecret schema under externalSecret ([8e8765a](https://github.com/aehrc/ontoserver-deploy/commit/8e8765aaf5400c9a833912f8a5c8b91030b76361))
* **chart:** add ontoserver.externalSecret.imagePullSecret values block ([e217232](https://github.com/aehrc/ontoserver-deploy/commit/e217232c4daae991cdba2974dea5fa3815078381))
* **chart:** auto-wire external pull secret into imagePullSecrets ([3ab25fe](https://github.com/aehrc/ontoserver-deploy/commit/3ab25fe730412eeb9858f02e9ee5440947361ec5))
* **charts:** add existingSecretConfig, changelog automation in release.sh ([28df301](https://github.com/aehrc/ontoserver-deploy/commit/28df301f127c63f28a5e52717ba29ca9d1a76e48))
* **charts:** extraVolumes/extraVolumeMounts for ontoserver and indexer ([83f937f](https://github.com/aehrc/ontoserver-deploy/commit/83f937f3f1970b044ae02eeb30561e3b50db9378))
* **charts:** opt-in securityContext for all three charts ([ad65b5f](https://github.com/aehrc/ontoserver-deploy/commit/ad65b5f5085b0292b04887dc2de044f66de7af2b))
* **chart:** validate imagePullSecret keys must be set together ([eddcbaa](https://github.com/aehrc/ontoserver-deploy/commit/eddcbaab33a83d27ad415b005426e6d0d04ae799))
* **ontoserver:** remove the bundled nginx-ingress subchart ([e2ebfa7](https://github.com/aehrc/ontoserver-deploy/commit/e2ebfa76a84a912f16238d4d22c4354e02099e4e))
* **ontoserver:** require isReadOnly for scaled deployments ([0d03095](https://github.com/aehrc/ontoserver-deploy/commit/0d03095ff4c1900b685b216abc23414a979ea6ec))


### Fixed

* **charts:** closure route timeout, ServiceMonitor discovery, name limits ([c6a5ded](https://github.com/aehrc/ontoserver-deploy/commit/c6a5dedc371ed604cce5b9ae7abc559352b304e3))
* **charts:** escape credentials in image pull secrets ([70238c9](https://github.com/aehrc/ontoserver-deploy/commit/70238c9e2237d3c865491e438ae9b908cb178c56))
* **charts:** resolve pre-merge review blockers in all three charts ([f89fdf5](https://github.com/aehrc/ontoserver-deploy/commit/f89fdf5fa6b5d48d3e46671871aa18d18624b844))
* **charts:** roll pods when configuration changes ([9730e8c](https://github.com/aehrc/ontoserver-deploy/commit/9730e8cfc29d634a647a19f9705355869da31dba))
* **ontoserver:** gate the db-files StorageClass on provided.enabled ([e0dd07c](https://github.com/aehrc/ontoserver-deploy/commit/e0dd07c152e5788dac25bf8556a40a52a47d9465))
* **ontoserver:** harden the helm test hook pods ([7a0c59a](https://github.com/aehrc/ontoserver-deploy/commit/7a0c59a7bd08d466868e7bfa4661d455cda89933))
* **ontoserver:** make PodDisruptionBudget minAvailable/maxUnavailable usable ([d769eb8](https://github.com/aehrc/ontoserver-deploy/commit/d769eb82ff0995779157b989e56a05bf1bf0963f))
* **ontoserver:** secretConfig non-strings, falsy-zero PDB, schema gap ([b43a9b0](https://github.com/aehrc/ontoserver-deploy/commit/b43a9b04ec0b63af7fd012aba874baea047f1e6e))
* **ontoserver:** substitute Recreate when a ReadWriteOnce volume is mounted ([97b28b3](https://github.com/aehrc/ontoserver-deploy/commit/97b28b34c6337a17f737e2431f81c2496b957fc0))
* use cloud-agnostic description for diskURI params ([d22592a](https://github.com/aehrc/ontoserver-deploy/commit/d22592a28ec859109bbc0475cea7abd95c618e16))
* use cloud-agnostic description for files.pv and dbfiles.pv enabled params ([025944b](https://github.com/aehrc/ontoserver-deploy/commit/025944bec1bdbea9cc7bfdca661d8c67da7738fc))


### Documentation

* back-fill and verify the changelogs against the release tags ([cdc04ae](https://github.com/aehrc/ontoserver-deploy/commit/cdc04ae4720f9da069b960c0ee0981d6c78ce77a))
* **chart:** replace manual Option B with chart-native imagePullSecret external secret example ([25269db](https://github.com/aehrc/ontoserver-deploy/commit/25269dbb6f0e8646c7fc4e688d5bc132934deff2))
* fix ONTOSERVER_INSECURE parameter description — controls inbound TLS listener not outbound verification ([02bcde1](https://github.com/aehrc/ontoserver-deploy/commit/02bcde16d376da47a5d61788df489bdebce3159a))
* make pre-provisioned PV examples cloud-agnostic, add EKS guidance ([af2a181](https://github.com/aehrc/ontoserver-deploy/commit/af2a181c91bb49808e9587852e749076294eca77))
* **ontoserver:** record cluster validation of the hardened context ([3eca00a](https://github.com/aehrc/ontoserver-deploy/commit/3eca00a7fd7204413f271c794832fe223c20bfeb))
* **ontoserver:** test the literal $ in the $closure route path ([61cf06d](https://github.com/aehrc/ontoserver-deploy/commit/61cf06d99404212396dc5b5d170a84832975828f))


### Changed

* move PV template from ontoserver-extras to ontoserver chart ([a605193](https://github.com/aehrc/ontoserver-deploy/commit/a605193481c820b0fcc7da209502c30492ba11fe))

## [0.4.0] - 2026-08-12

### Removed

- **BREAKING: the bundled `nginx-ingress` subchart.** The chart no longer installs an ingress
  controller. It was pinned at `2.1.0` and nobody was updating it, which makes a vendored
  network-facing controller a liability rather than a convenience.

  **Migration.** Install a controller yourself and point the chart at its IngressClass:

  ```bash
  helm repo add nginx-stable https://helm.nginx.com/stable
  helm install nginx-ingress nginx-stable/nginx-ingress \
    --namespace nginx-ingress --create-namespace \
    --set controller.ingressClass.name=ontoserver-nginx
  ```
  ```yaml
  ontoserver:
    ingress:
      enabled: true
      className: ontoserver-nginx   # must match the controller's IngressClass
  # delete the whole nginx-ingress: block
  ```

  The chart **fails to render** if a `nginx-ingress:` block is still present — including
  `enabled: false`. That is deliberate: nothing at the top level of `values.schema.json` sets
  `additionalProperties: false`, so the key would otherwise be accepted silently and `helm upgrade`
  would quietly stop deploying the controller, taking the service offline with no error anywhere.
  The presence of the key, not its value, is the signal that a values file has not been migrated.

  Consequences worth knowing: the chart now has **no dependencies at all**, so `Chart.lock` and the
  vendored `charts/` directory are gone and `helm dependency build` is a no-op.

> Note: verified against the `ontoserver-v0.3.0` tag rather than assembled from commit messages —
> 18 commits touch this chart since that release, and the values-key diff was used to confirm
> nothing user-facing is missing. Changes predating 0.3.0 are covered by the sections below.

### Added

- `ontoserver.gateway.allowPlaintext` and `ontoserver.gateway.listenerPortPlain`. A plaintext HTTP
  listener now has to be requested explicitly: it is off by default so a public Gateway cannot be
  left unencrypted by accident. Enable it for local development, or when TLS terminates upstream.

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
  needs a writable `/tmp` and the chart had no way to supply one. Validated on a cluster (AKS,
  external PostgreSQL, Gatekeeper auditing): Ready in ~50s with 0 restarts, root filesystem
  genuinely read-only, FHIR served, both `helm test` suites passing, and **zero** violations of
  `readOnlyRootFilesystem`, `allowedUsersGroups` or `noPrivilegeEscalation` for the namespace. `/tmp` turned out to be
  load-bearing rather than just a log destination — a running server writes `spring.log`,
  `hsperfdata`, Tomcat's work directories and `downlaod-*` scratch files there. The hardened
  README recipe now includes both, asserted together by a test so it cannot ship half-applied.
- Schema validation and test coverage for `ontoserver.existingSecretConfig`, a 0.3.0 feature that
  shipped with neither. The value was accepted before (the schema has no `additionalProperties`
  restriction at that level) so this is validation and documentation rather than a functional fix:
  a non-string is now rejected with a message naming the key.

### Fixed

- Documented a silent `$closure` routing failure on Traefik. Traefik matches `PathPrefix` against
  the percent-encoded path, so a client sending `/fhir/%24closure` misses the dedicated pod-0 route
  and is load-balanced across all pods, corrupting the stateful closure table. NGINX decodes before
  matching and is unaffected. Both were tested; AWS ALB and Azure AGIC remain unverified and the
  README says so.

- Removed the unreachable `existingVolume` branch from the StatefulSet's `volumeClaimTemplates`.
  `validate-values.yaml` rejects `persistence.files.existingVolume` for a StatefulSet outright, so
  the branch could never render — and the spec it would have produced (`volumeName` with no
  `accessModes` or `resources`) was not a valid PVC. Renders are byte-identical across all eight
  test fixtures.

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
