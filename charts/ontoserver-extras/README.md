# Ontoserver Extras Helm Chart

Optional infrastructure components for [Ontoserver](https://ontoserver.csiro.au/) deployments. Designed to be used alongside the `ontoserver` chart via ArgoCD multi-source Applications.

All features are disabled by default — installing the chart with no overrides produces no resources.

## Components

| Component | Description | Gate |
| --------- | ----------- | ---- |
| **Varnish** | HTTP caching proxy with Prometheus exporter and optional OpenTelemetry tracing sidecars | `varnish.enabled` |
| **OpenTelemetry Collector** | `OpenTelemetryCollector` CRD for receiving, filtering, and forwarding traces | `collector.enabled` |
| **PersistentVolume** | PersistentVolume for a pre-provisioned disk, with configurable CSI driver (defaults to `disk.csi.azure.com`) | `pv.enabled` |

## Prerequisites

| Feature | Cluster Requirement |
| ------- | ------------------- |
| `collector.enabled` | [OpenTelemetry Operator](https://opentelemetry.io/docs/kubernetes/operator/) installed |
| `varnish.enabled` (ServiceMonitor) | [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) CRDs installed |
| `pv.enabled` | CSI driver matching `pv.csiDriver` available (default: `disk.csi.azure.com` for AKS) |

## Parameters

### Varnish

| Name                                               | Description                                                                              | Value                                          |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `varnish.enabled`                                  | Enable Varnish caching proxy                                                             | `false`                                        |
| `varnish.backendServiceName`                       | Kubernetes service name for the Varnish backend (defaults to RELEASE-ontoserver-service) | `""`                                           |
| `varnish.opentelemetry.enabled`                    | Enable tracing VCL and sidecar containers (trace-converter + trace-forwarder)            | `false`                                        |
| `varnish.opentelemetry.collectorEndpoint`          | Zipkin endpoint for trace forwarding (required when opentelemetry enabled)               | `""`                                           |
| `varnish.metrics.enabled`                          | Enable Prometheus metrics exporter sidecar                                               | `true`                                         |
| `varnish.metrics.interval`                         | Prometheus scrape interval                                                               | `60s`                                          |
| `varnish.metrics.scrapeTimeout`                    | Prometheus scrape timeout (must be less than interval)                                   | `55s`                                          |
| `varnish.image`                                    | Varnish container image                                                                  | `varnish:7.7.1`                                |
| `varnish.exporterImage`                            | Prometheus exporter image                                                                | `ghcr.io/aehrc/varnish-exporter:7.7-1`         |
| `varnish.traceForwarderImage`                      | Trace forwarder container image (must have curl and sh)                                  | `curlimages/curl:8.14.1`                       |
| `varnish.resources.varnish.requests.cpu`           | Varnish CPU request                                                                      | `200m`                                         |
| `varnish.resources.varnish.requests.memory`        | Varnish memory request                                                                   | `256Mi`                                        |
| `varnish.resources.varnish.limits.cpu`             | Varnish CPU limit                                                                        | `500m`                                         |
| `varnish.resources.varnish.limits.memory`          | Varnish memory limit                                                                     | `1024Mi`                                       |
| `varnish.resources.exporter.requests.cpu`          | Exporter CPU request                                                                     | `50m`                                          |
| `varnish.resources.exporter.requests.memory`       | Exporter memory request                                                                  | `64Mi`                                         |
| `varnish.resources.exporter.limits.cpu`            | Exporter CPU limit                                                                       | `100m`                                         |
| `varnish.resources.exporter.limits.memory`         | Exporter memory limit                                                                    | `128Mi`                                        |
| `varnish.resources.traceConverter.requests.cpu`    | Trace converter CPU request                                                              | `25m`                                          |
| `varnish.resources.traceConverter.requests.memory` | Trace converter memory request                                                           | `25Mi`                                         |
| `varnish.resources.traceConverter.limits.cpu`      | Trace converter CPU limit                                                                | `50m`                                          |
| `varnish.resources.traceConverter.limits.memory`   | Trace converter memory limit                                                             | `50Mi`                                         |
| `varnish.resources.traceForwarder.requests.cpu`    | Trace forwarder CPU request                                                              | `25m`                                          |
| `varnish.resources.traceForwarder.requests.memory` | Trace forwarder memory request                                                           | `32Mi`                                         |
| `varnish.resources.traceForwarder.limits.cpu`      | Trace forwarder CPU limit                                                                | `50m`                                          |
| `varnish.resources.traceForwarder.limits.memory`   | Trace forwarder memory limit                                                             | `64Mi`                                         |
| `varnish.tolerations`                              | Pod tolerations for the Varnish deployment                                               | `[]`                                           |
| `varnish.cache.time200`                            | Cache TTL for 200 responses                                                              | `10m`                                          |
| `varnish.cache.time404`                            | Cache TTL for 404 responses                                                              | `1m`                                           |
| `varnish.cache.timeExpand`                         | Cache TTL for $expand responses (defaults to time200 if empty)                           | `""`                                           |
| `varnish.cache.passAuthHeaderRequests`             | Pass through (bypass cache) for requests with Authorization header                       | `true`                                         |
| `varnish.cache.memorySize`                         | Varnish malloc storage pool size (e.g. 800m, 1g)                                         | `800m`                                         |

### OpenTelemetry Collector

| Name                       | Description                                                                        | Value   |
| -------------------------- | ---------------------------------------------------------------------------------- | ------- |
| `collector.enabled`        | Enable OpenTelemetryCollector CRD (Instrumentation CRD is in the ontoserver chart) | `false` |
| `collector.otlpEndpoint`   | OTLP gRPC exporter endpoint (required when enabled)                                | `""`    |
| `collector.zipkinEndpoint` | Zipkin exporter endpoint (required when enabled)                                   | `""`    |
| `collector.tolerations`    | Pod tolerations for the OpenTelemetryCollector                                     | `[]`    |
| `collector.debug`          | Enable debug exporter with detailed verbosity (not suitable for production)        | `false` |

### PersistentVolume

| Name                  | Description                                                                  | Value                |
| --------------------- | ---------------------------------------------------------------------------- | -------------------- |
| `pv.enabled`          | Enable Azure Disk PersistentVolume                                           | `false`              |
| `pv.volumeName`       | PV name (required when enabled)                                              | `""`                 |
| `pv.diskURI`          | Full Azure disk resource ID (required when enabled)                          | `""`                 |
| `pv.storageSize`      | Storage capacity                                                             | `10Gi`               |
| `pv.storageClassName` | StorageClass name (defaults to RELEASE-ontoserver-files)                     | `""`                 |
| `pv.csiDriver`        | CSI driver for the PersistentVolume (defaults to disk.csi.azure.com for AKS) | `disk.csi.azure.com` |

## Usage with ArgoCD Multi-Source

This chart is intended to be deployed as a second source alongside `ontoserver` in an ArgoCD Application. Use `gateway.backendServiceNameOverride` in the ontoserver chart to route traffic through Varnish.

```yaml
spec:
  sources:
  - repoURL: https://github.com/your-org/your-argocd-config
    targetRevision: HEAD
    ref: values
  - repoURL: oci://your-registry/helm
    chart: ontoserver
    targetRevision: 1.0.0
    helm:
      valueFiles:
      - $values/apps/ontoserver/values.yaml
  - repoURL: https://github.com/aehrc/ontoserver-deploy
    targetRevision: HEAD
    path: ontoserver-extras
    helm:
      valueFiles:
      - $values/apps/ontoserver/extras-values.yaml
```

### Example: extras-values.yaml (Varnish + Collector + PV)

```yaml
varnish:
  enabled: true
  opentelemetry:
    enabled: true
    collectorEndpoint: http://ontoserver-r4-collector:9411

collector:
  enabled: true
  otlpEndpoint: tempo:4317
  zipkinEndpoint: http://tempo:9411

pv:
  enabled: true
  volumeName: r4-pv
  diskURI: /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/disks/r4
  storageSize: 1Ti
```

### Example: ontoserver values.yaml (route Gateway through Varnish)

```yaml
ontoserver:
  gateway:
    backendServiceNameOverride: ontoserver-r4-varnish-service
```

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
| `pv.yaml` | Value of `pv.volumeName` |

Table generated with Readme Generator For Helm: [https://github.com/bitnami/readme-generator-for-helm](https://github.com/bitnami/readme-generator-for-helm)
Regenerate it with `npx --yes @bitnami/readme-generator-for-helm -v values.yaml -r README.md`
---

Copyright &copy; 2025 Commonwealth Scientific and Industrial Research Organisation (CSIRO) ABN 41 687 119 230. All rights reserved.
