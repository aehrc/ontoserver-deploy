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

| Name                       | Description                                                                        | Value   |
| -------------------------- | ---------------------------------------------------------------------------------- | ------- |
| `collector.enabled`        | Enable OpenTelemetryCollector CRD (Instrumentation CRD is in the ontoserver chart) | `false` |
| `collector.otlpEndpoint`   | OTLP gRPC exporter endpoint (required when enabled)                                | `""`    |
| `collector.zipkinEndpoint` | Zipkin exporter endpoint (required when enabled)                                   | `""`    |
| `collector.tolerations`    | Pod tolerations for the OpenTelemetryCollector                                     | `[]`    |
| `collector.debug`          | Enable debug exporter with detailed verbosity (not suitable for production)        | `false` |

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

### Scaled Ontoserver deployments

When Varnish fronts a scaled StatefulSet Ontoserver cluster, two additional settings are relevant:

**`varnish.replicas`** — Number of Varnish pod replicas (default `1`). Consider `2+` to avoid a single point of failure. Each Varnish replica maintains its own independent cache — there is no cache synchronisation between replicas.

**`varnish.graceSeconds`** — Seconds to serve stale cached content when the backend is temporarily unavailable (default `30s`). This covers rolling updates of the Ontoserver StatefulSet: while a pod is being replaced, Varnish continues serving its last-known response rather than returning a 503. Set to `0` to disable grace mode.

**`varnish.closureBackend`** — Optional dedicated backend for the [`$closure` FHIR operation](https://www.hl7.org/fhir/conceptmap-operation-closure.html), which is stateful and must always reach the same Ontoserver instance. When set, Varnish routes all `POST /fhir/ConceptMap/$closure` requests to this specific backend hostname, bypassing the cache and the normal load-balanced backend. Set it to the stable DNS name of pod-0 via the headless service (e.g. `RELEASE-statefulset-0.RELEASE-ontoserver-headless`). Empty string (the default) disables dedicated `$closure` routing.

> [!IMPORTANT]
> You usually do **not** need `varnish.closureBackend` when using the `ontoserver` chart's Gateway or Ingress. In that setup, the `ontoserver` chart already routes `/fhir/ConceptMap/$closure` directly to `RELEASE-ontoserver-pod0-service` before the catchall route to Varnish, so `$closure` bypasses Varnish entirely.
>
> Set `varnish.closureBackend` only when clients send `$closure` requests to Varnish directly, bypassing the `ontoserver` chart's Gateway/Ingress path-based routing. That is a niche setup, such as port-forwarding or exposing Varnish through a separate ingress/proxy in front of the Ontoserver chart. Without `varnish.closureBackend`, Varnish forwards `$closure` to its normal backend service, which load-balances across all Ontoserver pods and breaks the stateful closure table.
>
> Set it to the stable pod-0 DNS name:
> ```yaml
> varnish:
>   closureBackend: "RELEASE-statefulset-0.RELEASE-ontoserver-headless"
> ```
> Replace `RELEASE` with your Helm release name (the same release name used for the `ontoserver` chart).
>
> If you are **not** routing through Varnish (Gateway/Ingress points directly at Ontoserver), this is not needed — the `ontoserver` chart already handles `$closure` routing at the network level.

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
