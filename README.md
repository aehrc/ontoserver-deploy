# Ontoserver Deployment


[![Unit Tests](https://github.com/aehrc/ontoserver-deploy/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/aehrc/ontoserver-deploy/actions/workflows/unit-tests.yml)
[![Integration Tests](https://github.com/aehrc/ontoserver-deploy/actions/workflows/integration-tests.yml/badge.svg)](https://github.com/aehrc/ontoserver-deploy/actions/workflows/integration-tests.yml)
[![ontoserver](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Faehrc.github.io%2Fontoserver-deploy%2Findex.yaml&query=%24.entries.ontoserver%5B0%5D.version&label=ontoserver&logo=helm&color=0F1689)](https://aehrc.github.io/ontoserver-deploy)
[![ontoserver-extras](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Faehrc.github.io%2Fontoserver-deploy%2Findex.yaml&query=%24.entries.ontoserver-extras%5B0%5D.version&label=ontoserver-extras&logo=helm&color=0F1689)](https://aehrc.github.io/ontoserver-deploy)
[![ontoserver-indexer](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Faehrc.github.io%2Fontoserver-deploy%2Findex.yaml&query=%24.entries.ontoserver-indexer%5B0%5D.version&label=ontoserver-indexer&logo=helm&color=0F1689)](https://aehrc.github.io/ontoserver-deploy)

> **Note for GHCR visitors:** The packages under `ghcr.io/aehrc/ontoserver-helm` are **Helm charts**, not Docker images. Install them with Helm, not `docker pull`:
> ```bash
> helm install ontoserver oci://ghcr.io/aehrc/ontoserver-helm/ontoserver --version <version> \
>   --set ontoserver.imageCredentials.username=<QUAY_USERNAME> \
>   --set ontoserver.imageCredentials.password=<QUAY_PASSWORD>
> ```

Deployment resources for [Ontoserver](https://ontoserver.csiro.au) — a FHIR terminology server — across different platforms and technologies.

| Directory | Description |
|-----------|-------------|
| [`charts/`](charts/) | Helm charts for Kubernetes deployments |
| [`docker/`](docker/) | Docker Compose and container images |
| [`azure/`](azure/) | Azure infrastructure (Terraform, AKS setup) |
| [`legacy/`](legacy/) | Archived charts — never publicly released; superseded by `charts/` |

## Helm Charts (Kubernetes)

Three charts are published from this repository:

| Chart | Description |
|-------|-------------|
| [`ontoserver`](charts/ontoserver/) | Main chart — single/scaled deployments, Gateway API or Ingress, optional Postgres sidecar, Prometheus, OTel, External Secrets |
| [`ontoserver-extras`](charts/ontoserver-extras/) | Optional add-ons — Varnish cache, OTel Collector |
| [`ontoserver-indexer`](charts/ontoserver-indexer/) | One-shot Job to index SNOMED CT or LOINC and publish to a syndication server and/or write to a PVC |

### Installing

**From GitHub Pages (Helm repository): **
```bash
helm repo add ontoserver https://aehrc.github.io/ontoserver-deploy
helm repo update
helm install my-ontoserver ontoserver/ontoserver -f your-values.yaml
```

**From OCI (GitHub Container Registry):**
```bash
# The chart name appears twice: `helm push` to oci://ghcr.io/aehrc/<chart>-helm appends the
# chart name from the package, so the pullable reference is <chart>-helm/<chart>.
helm install my-ontoserver oci://ghcr.io/aehrc/ontoserver-helm/ontoserver --version <version> -f your-values.yaml
helm install my-ontoserver-extras oci://ghcr.io/aehrc/ontoserver-extras-helm/ontoserver-extras --version <version> -f your-extras-values.yaml
helm install my-indexer oci://ghcr.io/aehrc/ontoserver-indexer-helm/ontoserver-indexer --version <version> -f your-indexer-values.yaml
```

See each chart's README for full configuration reference:
- [`charts/ontoserver/README.md`](charts/ontoserver/README.md) — platform-specific examples (AKS, EKS, local k3d)
- [`charts/ontoserver-extras/README.md`](charts/ontoserver-extras/README.md)
- [`charts/ontoserver-indexer/README.md`](charts/ontoserver-indexer/README.md) — SNOMED CT and LOINC indexing examples
- [`charts/README.md`](charts/README.md) — chart release and publishing instructions

### Releasing Charts

Maintainer-facing release instructions live in [`charts/README.md`](charts/README.md).
Use that document for chart tag formats, workflow triggers, and post-release checks.

### Deployment Examples

A comprehensive set of examples for various platforms and tools is available in the [**`examples/`**](examples/) directory:

- [**ArgoCD**](examples/argocd/) — Ready-to-use Application and ApplicationSet manifests.
- [**Kustomize**](examples/kustomize/) — Post-processing examples, such as adding a `priorityClassName`.
- [**Cloud & Networking**](charts/ontoserver/examples/) — Infrastructure-specific Helm values for AKS, EKS, and local clusters.

See [**`examples/README.md`**](examples/README.md) for a full overview of all available deployment scenarios.

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

> **Note:** cert-manager is not compatible with `ingress.className: alb`. AWS ALB only supports TLS via ACM certificate ARNs — it cannot use Kubernetes TLS secrets that cert-manager creates. Use `alb.ingress.kubernetes.io/certificate-arn` instead, or switch to nginx ingress.

## Docker

[`docker/`](docker/) contains Docker Compose and container image sources:

- [`docker/ontocache/`](docker/ontocache/) — Nginx caching proxy for Ontoserver
- [`docker/varnish-exporter/`](docker/varnish-exporter/) — Varnish + Prometheus exporter image (published to `ghcr.io/aehrc/varnish-exporter`)

## Azure Infrastructure

[`azure/`](azure/) contains Terraform configurations for provisioning AKS clusters and supporting Azure resources.

---

Copyright &copy; 2026 Commonwealth Scientific and Industrial Research Organisation (CSIRO) ABN 41 687 119 230. All rights reserved.
