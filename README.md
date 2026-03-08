# Ontoserver Deployment

Deployment resources for [Ontoserver](https://ontoserver.csiro.au) — a FHIR terminology server — across different platforms and technologies.

| Directory | Description |
|-----------|-------------|
| [`charts/`](charts/) | Helm charts for Kubernetes deployments |
| [`docker/`](docker/) | Docker Compose and container images |
| [`azure/`](azure/) | Azure infrastructure (Terraform, AKS setup) |
| [`legacy/`](legacy/) | Archived charts — see deprecation notices |

## Helm Charts (Kubernetes)

Three charts are published from this repository:

| Chart | Description |
|-------|-------------|
| [`ontoserver`](charts/ontoserver/) | Main chart — single/scaled deployments, Gateway API or Ingress, optional Postgres sidecar, Prometheus, OTel, External Secrets |
| [`ontoserver-extras`](charts/ontoserver-extras/) | Optional add-ons — Varnish cache, OTel Collector, PersistentVolume |
| [`ontoserver-indexer`](charts/ontoserver-indexer/) | One-shot Job to index SNOMED CT or LOINC and publish to a syndication server and/or write to a PVC |

### Installing

**From GitHub Pages (Helm repository):**
```bash
helm repo add ontoserver https://aehrc.github.io/ontoserver-deploy
helm repo update
helm install my-ontoserver ontoserver/ontoserver -f your-values.yaml
```

**From OCI (GitHub Container Registry):**
```bash
helm install my-ontoserver oci://ghcr.io/aehrc/ontoserver --version <version> -f your-values.yaml
helm install my-ontoserver-extras oci://ghcr.io/aehrc/ontoserver-extras --version <version> -f your-extras-values.yaml
helm install my-indexer oci://ghcr.io/aehrc/ontoserver-indexer --version <version> -f your-indexer-values.yaml
```

See each chart's README for full configuration reference:
- [`charts/ontoserver/README.md`](charts/ontoserver/README.md) — platform-specific examples (AKS, EKS, local k3d)
- [`charts/ontoserver-extras/README.md`](charts/ontoserver-extras/README.md)
- [`charts/ontoserver-indexer/README.md`](charts/ontoserver-indexer/README.md) — SNOMED CT and LOINC indexing examples

### Prerequisites

Depending on features enabled, you may need these cluster components:

| Feature | Requirement |
|---------|-------------|
| `ontoserver.gateway.enabled` | [Envoy Gateway](https://gateway.envoyproxy.io/) |
| `ontoserver.metrics.serviceMonitor.enabled` | [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) |
| `ontoserver.opentelemetry.instrumentation.enabled` | [OpenTelemetry Operator](https://opentelemetry.io/docs/kubernetes/operator/) |
| `ontoserver.externalSecret.enabled` | [External Secrets Operator](https://external-secrets.io/) |
| TLS certificates | [cert-manager](https://cert-manager.io/) |
| `ontoserver-indexer` with spot nodes | Node pool with `kubernetes.azure.com/scalesetpriority=spot` taint |
| `ontoserver-indexer` with local output | PersistentVolumeClaim (e.g. Azure Files CSI) pre-created in the target namespace |

**Installing cert-manager with a Let's Encrypt ClusterIssuer:**
```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --set crds.enabled=true
```
Then create a `ClusterIssuer` resource — see [cert-manager docs](https://cert-manager.io/docs/configuration/acme/).

## Docker

[`docker/`](docker/) contains Docker Compose and container image sources:

- [`docker/ontocache/`](docker/ontocache/) — Nginx caching proxy for Ontoserver
- [`docker/varnish-exporter/`](docker/varnish-exporter/) — Varnish + Prometheus exporter image (published to `ghcr.io/aehrc/varnish-exporter`)

## Azure Infrastructure

[`azure/`](azure/) contains Terraform configurations for provisioning AKS clusters and supporting Azure resources.

---

Copyright &copy; 2025 Commonwealth Scientific and Industrial Research Organisation (CSIRO) ABN 41 687 119 230. All rights reserved.
