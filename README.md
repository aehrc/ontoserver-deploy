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
helm install my-ontoserver oci://ghcr.io/aehrc/ontoserver --version <version> -f your-values.yaml
helm install my-ontoserver-extras oci://ghcr.io/aehrc/ontoserver-extras --version <version> -f your-extras-values.yaml
helm install my-indexer oci://ghcr.io/aehrc/ontoserver-indexer --version <version> -f your-indexer-values.yaml
```

See each chart's README for full configuration reference:
- [`charts/ontoserver/README.md`](charts/ontoserver/README.md) — platform-specific examples (AKS, EKS, local k3d)
- [`charts/ontoserver-extras/README.md`](charts/ontoserver-extras/README.md)
- [`charts/ontoserver-indexer/README.md`](charts/ontoserver-indexer/README.md) — SNOMED CT and LOINC indexing examples
- [`charts/README.md`](charts/README.md) — chart release and publishing instructions

### Releasing Charts

Maintainer-facing release instructions live in [`charts/README.md`](charts/README.md).
Use that document for chart tag formats, workflow triggers, and post-release checks.

### ArgoCD Examples

Example ArgoCD manifests are in [`examples/argocd/`](examples/argocd/):

> **Production note:** The examples source charts directly from this Git repository for simplicity. For production deployments, replace the Git source with a released chart version from the Helm repository — this gives you pinned, immutable versions and faster ArgoCD sync:
> ```yaml
> - repoURL: https://aehrc.github.io/ontoserver-deploy
>   chart: ontoserver
>   targetRevision: 0.1.0
> # or OCI
> - repoURL: oci://ghcr.io/aehrc
>   chart: ontoserver
>   targetRevision: 0.1.0
> ```

| File | How to use | Description |
|------|------------|-------------|
| [`dev-readonly.yaml`](examples/argocd/dev-readonly.yaml) | App-of-Apps inner app | Ready to use. Read-only dev server — sidecar PostgreSQL, ephemeral storage, Varnish. Expects a `quay-pull-secret` in the destination namespace (see below). No networking config — add your own gateway/ingress. |
| [`app-of-apps.yaml`](examples/argocd/app-of-apps.yaml) | App-of-Apps outer wrapper | Requires customisation. Deploys `dev-readonly.yaml` from Git. Add a second source pointing to a path in your private repo that creates the `quay-pull-secret`. |
| [`dev-readonly-envoy-appset.yaml`](examples/argocd/dev-readonly-envoy-appset.yaml) | ApplicationSet | Requires customisation. Two-instance setup: read/write StatefulSet (content development) + scaled read-only StatefulSet (production serving). Envoy Gateway, cert-manager TLS, external PostgreSQL, per-pod attached disks, Varnish with `$closure` routing. Hostname, namespace, and database URL are parameterised per instance. |

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

> **Note:** cert-manager is not compatible with `ingress.className: alb`. AWS ALB only supports TLS via ACM certificate ARNs — it cannot use Kubernetes TLS secrets that cert-manager creates. Use `alb.ingress.kubernetes.io/certificate-arn` instead, or switch to nginx ingress.

## Docker

[`docker/`](docker/) contains Docker Compose and container image sources:

- [`docker/ontocache/`](docker/ontocache/) — Nginx caching proxy for Ontoserver
- [`docker/varnish-exporter/`](docker/varnish-exporter/) — Varnish + Prometheus exporter image (published to `ghcr.io/aehrc/varnish-exporter`)

## Azure Infrastructure

[`azure/`](azure/) contains Terraform configurations for provisioning AKS clusters and supporting Azure resources.

---

Copyright &copy; 2026 Commonwealth Scientific and Industrial Research Organisation (CSIRO) ABN 41 687 119 230. All rights reserved.
