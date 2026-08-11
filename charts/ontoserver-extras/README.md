# Ontoserver Extras Helm Chart

Optional infrastructure components for [Ontoserver](https://ontoserver.csiro.au/) deployments. Designed to be used alongside the `ontoserver` chart via ArgoCD multi-source Applications.

All features are disabled by default — installing the chart with no overrides produces no resources.

## Components

| Component | Description | Gate |
| --------- | ----------- | ---- |
| **Varnish** | HTTP caching proxy with Prometheus exporter and optional OpenTelemetry tracing sidecars | `varnish.enabled` |
| **OpenTelemetry Collector** | `OpenTelemetryCollector` CRD for receiving, filtering, and forwarding traces | `collector.enabled` |

## Prerequisites

| Feature | Cluster Requirement |
| ------- | ------------------- |
| `collector.enabled` | [OpenTelemetry Operator](https://opentelemetry.io/docs/kubernetes/operator/) installed |
| `varnish.enabled` (ServiceMonitor) | [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) CRDs installed |

## Parameters

### Varnish

| Name                                               | Description                                                                                                                                                                                                                                                                                                                  | Value                                  |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `varnish.enabled`                                  | Enable Varnish caching proxy                                                                                                                                                                                                                                                                                                 | `false`                                |
| `varnish.backendServiceName`                       | Kubernetes service name for the Varnish backend (defaults to RELEASE-ontoserver-service)                                                                                                                                                                                                                                     | `""`                                   |
| `varnish.closureBackend`                           | Kubernetes hostname for the $closure operation backend. The $closure FHIR operation is stateful — it requires all requests to hit the same instance. Set to a stable pod hostname (e.g. RELEASE-statefulset-0.RELEASE-ontoserver-headless) when using a scaled deployment. Empty string disables dedicated $closure routing. | `""`                                   |
| `varnish.replicas`                                 | Number of Varnish pod replicas. For a scaled Ontoserver deployment consider 2+ to avoid a single point of failure. Note: multiple replicas each maintain their own independent cache.                                                                                                                                        | `1`                                    |
| `varnish.graceSeconds`                             | Seconds to serve stale cached content when the backend is unavailable (e.g. during a rolling update). Set to 0 to disable grace mode.                                                                                                                                                                                        | `30`                                   |
| `varnish.podSecurityContext`                       | Pod-level securityContext for the Varnish pod, passed through as-is (e.g. runAsNonRoot, runAsUser, fsGroup, seccompProfile)                                                                                                                                                                                                  | `{}`                                   |
| `varnish.containerSecurityContext`                 | Container-level securityContext, applied to every container in the Varnish pod (varnish, metrics exporter, trace converter, trace forwarder). They share a process namespace, so per-container isolation would be misleading.                                                                                                | `{}`                                   |
| `varnish.automountServiceAccountToken`             | Mount the ServiceAccount token into the Varnish pod. Varnish does not call the Kubernetes API, so false is safe. Leave unset (null) for the cluster default.                                                                                                                                                                 | `nil`                                  |
| `varnish.probes.enabled`                           | Add readiness and liveness probes to the varnish container. Enabling this rolls the pod once on upgrade.                                                                                                                                                                                                                     | `true`                                 |
| `varnish.probes.readiness.initialDelaySeconds`     | Readiness probe initial delay                                                                                                                                                                                                                                                                                                | `3`                                    |
| `varnish.probes.readiness.periodSeconds`           | Readiness probe period                                                                                                                                                                                                                                                                                                       | `5`                                    |
| `varnish.probes.readiness.timeoutSeconds`          | Readiness probe timeout                                                                                                                                                                                                                                                                                                      | `2`                                    |
| `varnish.probes.readiness.failureThreshold`        | Readiness probe failure threshold                                                                                                                                                                                                                                                                                            | `3`                                    |
| `varnish.probes.liveness.initialDelaySeconds`      | Liveness probe initial delay                                                                                                                                                                                                                                                                                                 | `10`                                   |
| `varnish.probes.liveness.periodSeconds`            | Liveness probe period                                                                                                                                                                                                                                                                                                        | `10`                                   |
| `varnish.probes.liveness.timeoutSeconds`           | Liveness probe timeout                                                                                                                                                                                                                                                                                                       | `2`                                    |
| `varnish.probes.liveness.failureThreshold`         | Liveness probe failure threshold. Restarting varnishd discards the whole cache, so this is deliberately tolerant.                                                                                                                                                                                                            | `6`                                    |
| `varnish.opentelemetry.enabled`                    | Enable tracing VCL and sidecar containers (trace-converter + trace-forwarder)                                                                                                                                                                                                                                                | `false`                                |
| `varnish.opentelemetry.collectorEndpoint`          | Zipkin endpoint for trace forwarding (required when opentelemetry enabled)                                                                                                                                                                                                                                                   | `""`                                   |
| `varnish.metrics.enabled`                          | Enable Prometheus metrics exporter sidecar                                                                                                                                                                                                                                                                                   | `false`                                |
| `varnish.metrics.interval`                         | Prometheus scrape interval                                                                                                                                                                                                                                                                                                   | `60s`                                  |
| `varnish.metrics.scrapeTimeout`                    | Prometheus scrape timeout (must be less than interval)                                                                                                                                                                                                                                                                       | `55s`                                  |
| `varnish.image`                                    | Varnish container image                                                                                                                                                                                                                                                                                                      | `varnish:7.7.1`                        |
| `varnish.exporterImage`                            | Prometheus exporter image                                                                                                                                                                                                                                                                                                    | `ghcr.io/aehrc/varnish-exporter:7.7-1` |
| `varnish.traceForwarderImage`                      | Trace forwarder container image (must have curl and sh)                                                                                                                                                                                                                                                                      | `curlimages/curl:8.14.1`               |
| `varnish.resources.varnish.requests.cpu`           | Varnish CPU request                                                                                                                                                                                                                                                                                                          | `200m`                                 |
| `varnish.resources.varnish.requests.memory`        | Varnish memory request                                                                                                                                                                                                                                                                                                       | `256Mi`                                |
| `varnish.resources.varnish.limits.cpu`             | Varnish CPU limit                                                                                                                                                                                                                                                                                                            | `500m`                                 |
| `varnish.resources.varnish.limits.memory`          | Varnish memory limit                                                                                                                                                                                                                                                                                                         | `1024Mi`                               |
| `varnish.resources.exporter.requests.cpu`          | Exporter CPU request                                                                                                                                                                                                                                                                                                         | `50m`                                  |
| `varnish.resources.exporter.requests.memory`       | Exporter memory request                                                                                                                                                                                                                                                                                                      | `64Mi`                                 |
| `varnish.resources.exporter.limits.cpu`            | Exporter CPU limit                                                                                                                                                                                                                                                                                                           | `100m`                                 |
| `varnish.resources.exporter.limits.memory`         | Exporter memory limit                                                                                                                                                                                                                                                                                                        | `128Mi`                                |
| `varnish.resources.traceConverter.requests.cpu`    | Trace converter CPU request                                                                                                                                                                                                                                                                                                  | `25m`                                  |
| `varnish.resources.traceConverter.requests.memory` | Trace converter memory request                                                                                                                                                                                                                                                                                               | `25Mi`                                 |
| `varnish.resources.traceConverter.limits.cpu`      | Trace converter CPU limit                                                                                                                                                                                                                                                                                                    | `50m`                                  |
| `varnish.resources.traceConverter.limits.memory`   | Trace converter memory limit                                                                                                                                                                                                                                                                                                 | `50Mi`                                 |
| `varnish.resources.traceForwarder.requests.cpu`    | Trace forwarder CPU request                                                                                                                                                                                                                                                                                                  | `25m`                                  |
| `varnish.resources.traceForwarder.requests.memory` | Trace forwarder memory request                                                                                                                                                                                                                                                                                               | `32Mi`                                 |
| `varnish.resources.traceForwarder.limits.cpu`      | Trace forwarder CPU limit                                                                                                                                                                                                                                                                                                    | `50m`                                  |
| `varnish.resources.traceForwarder.limits.memory`   | Trace forwarder memory limit                                                                                                                                                                                                                                                                                                 | `64Mi`                                 |
| `varnish.tolerations`                              | Pod tolerations for the Varnish deployment                                                                                                                                                                                                                                                                                   | `[]`                                   |
| `varnish.cache.time200`                            | Cache TTL for 200 responses                                                                                                                                                                                                                                                                                                  | `10m`                                  |
| `varnish.cache.time404`                            | Cache TTL for 404 responses                                                                                                                                                                                                                                                                                                  | `1m`                                   |
| `varnish.cache.timeExpand`                         | Cache TTL for $expand responses (defaults to time200 if empty)                                                                                                                                                                                                                                                               | `""`                                   |
| `varnish.cache.passAuthHeaderRequests`             | Pass through (bypass cache) for requests with Authorization header                                                                                                                                                                                                                                                           | `true`                                 |
| `varnish.cache.memorySize`                         | Varnish malloc storage pool size (e.g. 800m, 1g)                                                                                                                                                                                                                                                                             | `800m`                                 |

### OpenTelemetry Collector

| Name                                 | Description                                                                                                                                                                                     | Value   |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `collector.enabled`                  | Enable OpenTelemetryCollector CRD (Instrumentation CRD is in the ontoserver chart)                                                                                                              | `false` |
| `collector.otlpEndpoint`             | OTLP gRPC exporter endpoint (required when enabled)                                                                                                                                             | `""`    |
| `collector.zipkinEndpoint`           | Zipkin exporter endpoint (required when enabled)                                                                                                                                                | `""`    |
| `collector.tolerations`              | Pod tolerations for the OpenTelemetryCollector                                                                                                                                                  | `[]`    |
| `collector.debug`                    | Enable debug exporter with detailed verbosity (not suitable for production)                                                                                                                     | `false` |
| `collector.podSecurityContext`       | Pod-level securityContext for the collector pod, passed to the CR's spec.podSecurityContext (e.g. runAsNonRoot, runAsUser, fsGroup, seccompProfile)                                             | `{}`    |
| `collector.containerSecurityContext` | Container-level securityContext for the collector container, passed to the CR's spec.securityContext (e.g. allowPrivilegeEscalation, capabilities, readOnlyRootFilesystem)                      | `{}`    |
| `collector.batch.sendBatchSize`      | Spans per batch before the batch processor flushes                                                                                                                                              | `1000`  |
| `collector.batch.timeout`            | Maximum time a span waits before being flushed regardless of batch size. Must not be 0s — that disables the timer entirely, so on a quiet server spans wait indefinitely for the batch to fill. | `5s`    |

## Deploying alongside the ontoserver chart

The `ontoserver` chart is intentionally unaware of Varnish — it routes traffic directly to `RELEASE-ontoserver-service` by default. To insert Varnish into the request path, the ontoserver chart's `gateway.backendServiceNameOverride` (or equivalent Ingress backend) must point to the Varnish service after it is running.

### ArgoCD multi-source (recommended)

When both charts are sources in the same ArgoCD Application, both are reconciled together. Set `backendServiceNameOverride` in your ontoserver values file and ArgoCD will keep both in sync — no manual intervention needed after the initial setup.

The examples below assume both charts share the same Helm release name inside the ArgoCD Application, so generated resource names use that single release prefix.

```yaml
# ArgoCD Application
spec:
  sources:
  - repoURL: https://github.com/your-org/your-argocd-config
    targetRevision: HEAD
    ref: values
  - repoURL: https://aehrc.github.io/ontoserver-deploy
    chart: ontoserver
    targetRevision: 0.1.0
    helm:
      valueFiles:
      - $values/apps/ontoserver/values.yaml
  - repoURL: https://aehrc.github.io/ontoserver-deploy
    chart: ontoserver-extras
    targetRevision: 0.1.0
    helm:
      valueFiles:
      - $values/apps/ontoserver/extras-values.yaml
```

```yaml
# extras-values.yaml
varnish:
  enabled: true
  opentelemetry:
    enabled: true
    collectorEndpoint: http://<argo-release-name>-otel-collector:9411

collector:
  enabled: true
  otlpEndpoint: tempo:4317
  zipkinEndpoint: http://tempo:9411
```

```yaml
# ontoserver values.yaml — route Gateway/Ingress through Varnish
ontoserver:
  gateway:
    backendServiceNameOverride: <argo-release-name>-varnish-service
  opentelemetry:
    instrumentation:
      enabled: true
      exporter:
        endpoint: http://<argo-release-name>-otel-collector:9411
```

### Plain Helm install

When installing with plain `helm` (not ArgoCD), the two charts must be wired up in the correct order — the Varnish service must exist before the ontoserver chart is updated to route to it:

```bash
# 1. Install the main ontoserver chart first (routes directly to ontoserver)
helm install ontoserver-dev ./charts/ontoserver -f values.yaml

# 2. Install the extras chart (deploys Varnish and its service)
helm install ontoserver-dev-extras ./charts/ontoserver-extras -f extras-values.yaml

# 3. Now upgrade the main chart to route traffic through the extras release's Varnish service
helm upgrade ontoserver-dev ./charts/ontoserver -f values.yaml \
  --set ontoserver.gateway.backendServiceNameOverride=ontoserver-dev-extras-varnish-service \
  --set ontoserver.opentelemetry.instrumentation.enabled=true \
  --set ontoserver.opentelemetry.instrumentation.exporter.endpoint=http://ontoserver-dev-extras-otel-collector:9411
```

> [!NOTE]
> Between steps 1 and 3, traffic reaches Ontoserver directly (bypassing Varnish). Step 3 is safe to run immediately after step 2 — the Varnish service is created by `helm install` before any pods are ready.

## Varnish Caching Modes

### Plain caching (`varnish.opentelemetry.enabled: false`)

Standard Varnish reverse proxy with:
- Configurable TTLs for 200, 404, and `$expand` responses
- Accept-Language and Accept header vary handling
- Cache status headers (`X-Cache`, `X-Cache-Hits`, `X-Cache-Age`)
- Authorization header pass-through
- Custom 503 error page

### Tracing-enabled (`varnish.opentelemetry.enabled: true`)

Everything from plain mode plus:
- W3C `traceparent` and B3 header parsing
- Varnish span ID generation
- Traceparent rewriting in backend requests (Varnish as parent span)
- `OTEL_SPAN` log entries with microsecond timestamps
- Two sidecar containers:
  - **varnish-trace-converter** — tails `varnishlog` for `VCL_Log` entries
  - **trace-forwarder** — parses OTEL_SPAN lines and POSTs Zipkin v2 spans to the collector

### VCL changes and restarts

`varnishd` parses `/etc/varnish/default.vcl` once, at startup, and never re-reads it. The VCL
arrives as a mounted ConfigMap, so a `helm upgrade` that changes only a cache setting would
otherwise update the ConfigMap and leave the pod template untouched — no rollout, and Varnish
would keep serving the previous VCL.

The Varnish Deployment therefore carries a `checksum/config` pod annotation holding a hash of
the rendered VCL, so any change to a `varnish.*` value that appears in the VCL (or to the VCL
template itself) rolls the Deployment. The hash covers the VCL text only, so releasing a new
chart version does not restart Varnish and discard a warm cache.

### Probes

The `varnish` container carries a readiness and a liveness probe (`varnish.probes.enabled`, on by default). Previously only the metrics exporter sidecar had one, so the Service began routing to a pod whose `varnishd` was not yet accepting connections — every rolling update dropped requests.

Both are **`tcpSocket` on the `http` port**, deliberately rather than `httpGet`:

- An HTTP probe is *proxied to Ontoserver*. It would put backend traffic on the wire every period, and — worse — it would mark the cache unready whenever the backend was down. That converts a backend outage into a cache outage, which is exactly what `varnish.graceSeconds` exists to prevent: Varnish should keep serving stale content, not be pulled from the Service.
- The VCL defines no synthetic health endpoint, so there is no path that answers without reaching the backend.

`varnishd` accepting connections on `:8080` is the thing this pod is actually responsible for, and that is what the probes check.

The liveness probe is deliberately more tolerant than the readiness probe (`failureThreshold` 6 vs 3): a restart discards the entire cache, so it should take longer to trigger than removal from the Service.

> **Upgrade note:** enabling probes changes the pod template, so the first `helm upgrade` after adopting this rolls the Varnish Deployment once and the cache starts cold. Set `varnish.probes.enabled: false` to keep the old behaviour.

### Trace batching

`collector.batch.timeout` must not be zero. A zero timeout does not mean "flush immediately" — it disables the flush timer, so spans are held until `collector.batch.sendBatchSize` accumulates. A terminology server is usually quiet, so the practical effect is that traces never ship while everything appears configured correctly. The chart rejects a zero value at render time in any unit, and defaults to `5s`.

The `filter/health_checks` processor runs with `error_mode: ignore`. Its default, `propagate`, fails the whole batch when a single condition errors — so one span missing `http.url` would discard every span batched alongside it. The individual conditions are also nil-guarded, since a condition that errors is a condition that never matches, and the span it should have filtered gets exported instead.

### Scaled Ontoserver deployments

When Varnish fronts a scaled StatefulSet Ontoserver cluster, two additional settings are relevant:

**`varnish.replicas`** — Number of Varnish pod replicas (default `1`). Consider `2+` to avoid a single point of failure. Each Varnish replica maintains its own independent cache — there is no cache synchronisation between replicas.

**`varnish.graceSeconds`** — Seconds to serve stale cached content when the backend is temporarily unavailable (default `30s`). This covers rolling updates of the Ontoserver StatefulSet: while a pod is being replaced, Varnish continues serving its last-known response rather than returning a 503. Set to `0` to disable grace mode.

**`varnish.closureBackend`** — Optional dedicated backend for the [`$closure` FHIR operation](https://www.hl7.org/fhir/conceptmap-operation-closure.html), which is stateful and must always reach the same Ontoserver instance. When set, Varnish routes all `POST /fhir/$closure` requests to this specific backend hostname, bypassing the cache and the normal load-balanced backend. Set it to the stable DNS name of pod-0 via the headless service (e.g. `RELEASE-statefulset-0.RELEASE-ontoserver-headless`). Empty string (the default) disables dedicated `$closure` routing.

> [!IMPORTANT]
> Whether you need `varnish.closureBackend` depends on how traffic reaches Varnish:
>
> **`backendServiceNameOverride` NOT set** (Gateway/Ingress routes directly to Ontoserver): The `ontoserver` chart routes `/fhir/$closure` to `RELEASE-ontoserver-pod0-service`, which bypasses Varnish entirely. `varnish.closureBackend` is not needed.
>
> **`backendServiceNameOverride` set to the Varnish service**: `$closure` is routed through Varnish along with all other traffic. Varnish always treats `$closure` as a cache miss (`return (pass)`), but without `varnish.closureBackend` it will forward to its normal backend — which load-balances across all Ontoserver pods and breaks the stateful closure table. In this case, set `varnish.closureBackend` to the stable pod-0 DNS name:
> ```yaml
> varnish:
>   closureBackend: "RELEASE-statefulset-0.RELEASE-ontoserver-headless"
> ```
> Replace `RELEASE` with your Helm release name.
>
> **Varnish exposed directly** (no `ontoserver` chart Gateway/Ingress in front): Same requirement as above — set `varnish.closureBackend` to the pod-0 headless DNS name.

## Security context

By default the chart sets no `securityContext`, so containers run as whatever their images specify. Hardening is opt-in:

| Value | Applies to |
| --- | --- |
| `varnish.podSecurityContext` | the Varnish pod |
| `varnish.containerSecurityContext` | **every** container in the pod — `varnish`, `varnish-exporter`, `varnish-trace-converter`, `trace-forwarder` and the `init-trace-pipe` init container |
| `varnish.automountServiceAccountToken` | the pod — safe to set `false`; Varnish never calls the Kubernetes API |
| `collector.podSecurityContext` / `collector.containerSecurityContext` | the OpenTelemetry Collector pod — see [below](#opentelemetry-collector-1), these are CR fields rather than pod-spec fields |

All default to unset, so upgrading an existing release leaves the pod spec byte-identical and does not discard a warm cache.

There is one container-level value rather than one per container because these containers are a single unit: they share a process namespace (`shareProcessNamespace: true`, which is what lets the exporter and `varnishlog` see the `varnishd` process), so per-container isolation settings would be misleading.

This chart is in better shape than the `ontoserver` chart to begin with: `varnish:7.7.1` already runs as **uid 1000 (`varnish`)** rather than root, and `/var/lib/varnish` is an `emptyDir`, which the kubelet creates world-writable. So a hardened context mostly makes an existing guarantee explicit to your admission policy:

```yaml
varnish:
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000        # the uid the varnish image already uses
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop: [ALL]
  automountServiceAccountToken: false
```

`readOnlyRootFilesystem` is left out deliberately: `varnishd` compiles the VCL into a shared object at startup and needs a writable working directory, and the exporter and trace sidecars have not been verified under it. The `ghcr.io/aehrc/varnish-exporter` image was not reachable for inspection when this was written, so treat the exporter sidecar in particular as unverified and test before relying on it.

### OpenTelemetry Collector

The collector pod is not created by this chart — the OpenTelemetry Operator builds it from the `OpenTelemetryCollector` CR. Hardening it therefore means setting **CR fields**, not pod-spec fields, and the chart passes two values through:

| Value | Rendered as |
| --- | --- |
| `collector.podSecurityContext` | `spec.podSecurityContext` on the CR |
| `collector.containerSecurityContext` | `spec.securityContext` on the CR |

Note the asymmetry: the CR's `spec.securityContext` is the **container** context, despite the name. There is no `spec.containerSecurityContext` field — that plausible-looking spelling is not defined on the CRD, and because the CRD does not reject unknown fields, using it would produce a CR that applies cleanly and is silently ignored. Both names here were checked against the `v1beta1` CRD shipped with operator **0.156.0**, where each carries the full corresponding Kubernetes type.

```yaml
collector:
  podSecurityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: [ALL]
```

This has been validated as rendering the fields the CRD declares; it has **not** been run against a live Operator, so confirm the collector still starts before adopting it — in particular `readOnlyRootFilesystem`, which is included above only as an example.

## Resource Naming

All Kubernetes resources are prefixed with `{{ .Release.Name }}-`:

| Template | Resource Name |
| -------- | ------------- |
| `varnish-deployment.yaml` | `RELEASE-varnish` |
| `varnish-service.yaml` | `RELEASE-varnish-service` |
| `varnish-configmap.yaml` | `RELEASE-varnish-configmap` |
| `varnish-prometheus-service.yaml` | `RELEASE-varnish-prometheus-service` |
| `varnish-servicemonitor.yaml` | `RELEASE-varnish-metrics` |
| `otel-collector.yaml` | `RELEASE-otel-collector` |

Table generated with Readme Generator For Helm: [https://github.com/bitnami/readme-generator-for-helm](https://github.com/bitnami/readme-generator-for-helm)
Regenerate it with `npx --yes @bitnami/readme-generator-for-helm -v values.yaml -r README.md`

***

Copyright &copy; 2026 Commonwealth Scientific and Industrial Research Organisation (CSIRO) ABN 41 687 119 230. All rights reserved.
