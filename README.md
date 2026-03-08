# Ontoserver Deployment

[![Unit Tests](https://github.com/aehrc/ontoserver-deploy/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/aehrc/ontoserver-deploy/actions/workflows/unit-tests.yml)
[![Integration Tests](https://github.com/aehrc/ontoserver-deploy/actions/workflows/integration-tests.yml/badge.svg)](https://github.com/aehrc/ontoserver-deploy/actions/workflows/integration-tests.yml)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/package/helm/ontoserver/ontoserver)](https://artifacthub.io/packages/helm/ontoserver/ontoserver)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/package/helm/ontoserver/ontoserver-extras)](https://artifacthub.io/packages/helm/ontoserver/ontoserver-extras)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/package/helm/ontoserver/ontoserver-indexer)](https://artifacthub.io/packages/helm/ontoserver/ontoserver-indexer)

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

### ArgoCD Examples

Ready-to-use ArgoCD Application manifests are in [`examples/argocd/`](examples/argocd/):

| File | How to use | Description |
|------|------------|-------------|
| [`dev-readonly.yaml`](examples/argocd/dev-readonly.yaml) | App-of-Apps inner app | Read-only dev server — sidecar PostgreSQL, ephemeral storage, Varnish. Expects a `quay-pull-secret` in the destination namespace (see below). No networking config — add your own gateway/ingress. |
| [`app-of-apps.yaml`](examples/argocd/app-of-apps.yaml) | App-of-Apps outer wrapper | Deploys `dev-readonly.yaml` from Git. Add a second source pointing to a path in your private repo that creates the `quay-pull-secret`. |
| [`dev-readonly-envoy-appset.yaml`](examples/argocd/dev-readonly-envoy-appset.yaml) | ApplicationSet | Two-instance setup: read/write StatefulSet (content development) + scaled read-only StatefulSet (production serving). Envoy Gateway, cert-manager TLS, external PostgreSQL, per-pod attached disks, Varnish with `$closure` routing. Hostname, namespace, and database URL are parameterised per instance. |

#### Image pull credentials for ArgoCD

The `dev-readonly.yaml` and `dev-readonly-envoy-appset.yaml` examples use
`deployment.imagePullSecrets` to reference a pre-existing `kubernetes.io/dockerconfigjson`
Secret named `quay-pull-secret`.  Credentials must **not** be stored inline in the
Application manifest.  Create the secret in the destination namespace using whichever
mechanism your cluster provides:

- **ExternalSecret** — use [External Secrets Operator](https://external-secrets.io/) to sync from your secrets manager (see `charts/ontoserver/README.md` for an example ExternalSecret)
- **SealedSecret** — encrypt with [Sealed Secrets](https://sealed-secrets.netlify.app/) and commit to your private cluster-config repo
- **Manual** — `kubectl create secret docker-registry quay-pull-secret --docker-server=quay.io --docker-username=… --docker-password=… -n <namespace>`

In an App-of-Apps, supply the credentials as a second `source` in your outer Application pointing to a path in your own (private) repository, as shown in [`app-of-apps.yaml`](examples/argocd/app-of-apps.yaml).

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

Copyright &copy; 2026 Commonwealth Scientific and Industrial Research Organisation (CSIRO) ABN 41 687 119 230. All rights reserved.
