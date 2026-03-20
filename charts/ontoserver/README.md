# Ontoserver Helm Chart

This chart provides flexible deployment options for [Ontoserver](https://ontoserver.csiro.au/) — a FHIR terminology server — on Kubernetes. It supports single or scaled deployments, read-only or read-write modes, optional persistence, and networking via the Kubernetes Gateway API, standard Ingress, or Traefik IngressRoute (with an optional bundled [F5 Nginx Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/)). Optional features include a Postgres sidecar, Prometheus metrics, OpenTelemetry distributed tracing, Envoy Gateway traffic policies, and External Secrets integration.

> **Prerequisites:** Depending on which features you enable, the following cluster-level components may be required — install them separately if not already present:
>
> - **Kubernetes 1.29+** — required when `ontoserver.deployment.db.enabled: true` (the default). The Postgres sidecar uses the [native sidecar init container](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) pattern (`restartPolicy: Always`), which is stable from K8s 1.29.
> - **[Envoy Gateway](https://gateway.envoyproxy.io/)** — required when `ontoserver.gateway.enabled: true` (Gateway API networking, and any Envoy traffic/security policies)
> - **[F5 Nginx Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/)** — required when `ontoserver.ingress.enabled: true` and you are **not** using the bundled `nginx-ingress` subchart (`nginx-ingress.enabled: false`)
> - **[Traefik](https://doc.traefik.io/traefik/)** with CRD support — required when `traefik.ingressRoute.enabled: true`
> - **[External Secrets Operator](https://external-secrets.io/)** — required when `ontoserver.externalSecret.enabled: true`

## Table of Contents

- [Deployment Modes](#deployment-modes)
  - [Supported configurations](#supported-configurations)
  - [Unsupported configurations](#unsupported-configurations)
  - [Production recommendations](#production-recommendations)
- [Registry Credentials (Required)](#registry-credentials-required)
  - [Option A — chart-managed secret (recommended)](#option-a--chart-managed-secret-recommended)
  - [Option B — External Secrets](#option-b--external-secrets)
  - [Option C — pre-created secret](#option-c--pre-created-secret)
- [Testing](#testing)
  - [Unit Tests](#unit-tests)
  - [Integration Tests](#integration-tests)
    - [Scaled StatefulSet integration test](#scaled-statefulset-integration-test)
- [Persistence](#persistence)
  - [Pre-provisioned PersistentVolumes](#pre-provisioned-persistentvolumes)
- [Health Checking](#health-checking)
  - [Healthcheck and HTTPS mode](#healthcheck-and-https-mode-ontoserver_insecure-false)
- [Amazon EKS](#amazon-eks)
  - [Storage](#storage)
  - [Ingress](#ingress)
  - [IRSA (IAM Roles for Service Accounts)](#irsa-iam-roles-for-service-accounts)
  - [Node Targeting](#node-targeting)
- [Azure AKS](#azure-aks)
- [Local Development (k3d / minikube)](#local-development-k3d--minikube)
  - [k3d quick-start](#k3d-quick-start)
  - [ArgoCD](#argocd)
- [Optional Feature Prerequisites](#optional-feature-prerequisites)
- [Postgres sidecar](#postgres-sidecar)
- [Configuring an external database](#configuring-an-external-database)
- [Customisation](#customisation)
- [Outbound HTTP proxy](#outbound-http-proxy)
- [Gateway API vs Ingress](#gateway-api-vs-ingress)
  - [$closure routing for scaled StatefulSet deployments](#closure-routing-for-scaled-statefulset-deployments)
- [Envoy Gateway](#envoy-gateway)
  - [Infrastructure (GatewayClass and EnvoyProxy)](#infrastructure-gatewayclass-and-envoyproxy)
  - [Traffic Policies](#traffic-policies)
- [Traefik Ingress Controller](#traefik-ingress-controller)
  - [IngressRoute vs standard Ingress](#ingressroute-vs-standard-ingress)
  - [HTTPS backend (Ontoserver TLS mode)](#https-backend-ontoserver-tls-mode)
  - [ServersTransport](#serverstransport)
  - [Traefik API version](#traefik-api-version)
- [Observability](#observability)
  - [Management Service](#management-service)
  - [Prometheus Metrics](#prometheus-metrics)
  - [OpenTelemetry Tracing](#opentelemetry-tracing)
- [External Secrets](#external-secrets)
- [Parameters](#parameters)

## Deployment Modes

The chart supports four deployment combinations controlled by `ontoserver.deployment.kind` and `ontoserver.deployment.type`:

|  | `single` | `scaled` |
|---|---|---|
| **`Deployment`** | One-replica Deployment | Multi-replica Deployment |
| **`StatefulSet`** | One-replica StatefulSet (per-pod PVCs) | Multi-replica StatefulSet (per-pod PVCs) |

**Constraints:**
- `scaled` requires `replicas` ≥ 2 (or 0 to scale to zero). `single` requires `replicas` < 2.
- `scaled` deployments cannot use the Postgres sidecar — an external database is required.
- `isReadOnly: true` is strongly recommended for all scaled deployments. Scaled read-write mode is highly experimental, has not been tested, and **must not be used in production**.
- `clusterName` sets `ontoserver.cluster.name` for auto-discovery, allowing independent scaled clusters on the same network. Defaults to `ontoserver` (the application default) when unset.
- `StatefulSet` kind always provisions PVCs via `volumeClaimTemplates`. `Deployment` kind requires `persistence.enabledForDeployment: true` to use PVCs.

### Supported configurations

| `kind` | `type` | Database | Storage | Notes |
|---|---|---|---|---|
| `Deployment` | `single` | Sidecar (`db.enabled: true`) | `ReadWriteOnce` | |
| `Deployment` | `single` | External | Any / none | |
| `Deployment` | `scaled` | External | None (ephemeral) | Each pod uses its own local ephemeral storage; indexes rebuilt from syndication feeds |
| `StatefulSet` | `single` | Sidecar | `ReadWriteOnce` | |
| `StatefulSet` | `single` | External | Any / none | |
| `StatefulSet` | `scaled` | External | `ReadWriteOnce` | Each pod gets its own PVC via `volumeClaimTemplates` |

### Unsupported configurations

> These combinations are either rejected by the chart at render time or will fail at runtime.

| `kind` | `type` | Database | Storage | Reason |
|---|---|---|---|---|
| `Deployment` | `scaled` | Sidecar | — | Hard rejected by the chart — scaled deployments require an external database |
| `Deployment` | `scaled` | External | `ReadWriteOnce` | All pods share one PVC; only one pod can mount it |
| `Deployment` | `scaled` | External | `ReadWriteMany` | All pods share the same directory; Lucene `write.lock` conflicts corrupt indexes |
| `StatefulSet` | `scaled` | Sidecar | — | Hard rejected by the chart — scaled deployments require an external database |
| `StatefulSet` | `scaled` | External | `ReadWriteMany` | All pods share the same directory; Lucene `write.lock` conflicts corrupt indexes |

**Why shared storage always fails for scaled deployments:** Ontoserver uses stateless clustering — each pod maintains its own local Lucene index cache, rebuilt on demand from syndication feeds. Indexes are not designed to be shared across processes. Lucene's `IndexWriter` acquires an exclusive `write.lock` file; concurrent access from multiple pods to the same index directory will either fail with `LockObtainFailedException` or silently corrupt the index. Any shared PVC (RWO mounted by one pod, or RWX mounted by all) violates this constraint. The correct patterns are `StatefulSet` with per-pod `ReadWriteOnce` PVCs, or `Deployment` with no persistence (ephemeral local storage per pod).

### Production recommendations

The recommended production topology separates content development from publication. Content is authored on a read-write instance, published to a syndication server, and pulled by read-only instances. See [Ontoserver's deployment planning guidance](https://ontoserver.csiro.au/site/technical-documentation/ontoserver-technical-documentation/planning-a-deployment/) for background.

| Setting | Production read-only cluster | Production read-write (content dev) | Development / local |
|---|---|---|---|
| `deployment.kind` | `StatefulSet` | `StatefulSet` | `Deployment` |
| `deployment.type` | `scaled` | `single` | `single` |
| `deployment.isReadOnly` | `true` | `false` | `false` |
| `deployment.replicas` | ≥ 2 | 1 | 1 |
| `deployment.db.enabled` | `false` | `false` | `true` (sidecar) |
| Database | External managed PostgreSQL | External managed PostgreSQL | Sidecar (in-pod) |
| `persistence.files.accessMode` | `ReadWriteOnce` (per-pod via `volumeClaimTemplates`) | `ReadWriteOnce` | None (ephemeral) |
| `healthCheckOption` | `-s` | `-f` (default) | `-l` |
| `deployment.clusterName` | Set (isolates cluster on shared networks) | — | — |

**Production read-only** — the [absolutely preferred model](https://ontoserver.csiro.au/site/technical-documentation/ontoserver-technical-documentation/planning-a-deployment/design-considerations-infrastructure-implications/horizontally-scaled-read-only-endpoint/) for a public endpoint. Instances auto-discover each other via DNS, share a single external PostgreSQL database, and each maintain their own local Lucene index on a per-pod attached disk. Per-pod attached disks are essential: a full SNOMED CT index takes hours to rebuild from scratch — without persistence, every pod restart would leave the pod unready for that entire period (with `-s`), degrading cluster capacity during rolling updates. `healthCheckOption: -s` holds a pod out of the load balancer until its startup preload completes, enabling [zero-downtime rolling updates](https://ontoserver.csiro.au/site/technical-documentation/ontoserver-technical-documentation/planning-a-deployment/design-considerations-infrastructure-implications/zero-down-time-deployments/).

**Production read-write** — single instance only (horizontal write scaling is not supported). External PostgreSQL is strongly recommended so database data is backed up and managed independently of the pod lifecycle. Attached disk preserves the Lucene index across pod restarts. This instance is typically not public-facing — content is promoted to the read-only cluster via a syndication server, optionally via a staging read-only instance for validation before publication.

**Development / local** — ephemeral storage with the sidecar PostgreSQL avoids cloud disk provisioning. The index is rebuilt from syndication feeds on each start, which is acceptable at small scale.

> **Feeds must stay available:** New instances (after a pod is rescheduled or the cluster is scaled up) rebuild their local index from the syndication feeds that originally loaded the content. If those feeds become unavailable, new instances cannot complete startup and will not become ready.

## Registry Credentials (Required)

The Ontoserver image is hosted on [quay.io](https://quay.io/repository/aehrc/ontoserver) and **requires authentication**. The chart can manage the pull secret for you.

### Option A — chart-managed secret (recommended)

Pass your quay.io credentials at install time and the chart creates the `kubernetes.io/dockerconfigjson` Secret automatically:

```bash
helm install my-ontoserver ./charts/ontoserver \
  --set ontoserver.imageCredentials.username=<quay-username> \
  --set ontoserver.imageCredentials.password=<quay-password> \
  -f your-values.yaml
```

Or in your values file:

```yaml
ontoserver:
  imageCredentials:
    registry: quay.io    # default
    username: your-quay-username
    password: your-quay-password
```

### Option B — External Secrets

Use the [External Secrets Operator](https://external-secrets.io/) to sync credentials from your secrets manager. Store the quay.io username and password as separate keys in your secret store, then use an `ExternalSecret` with a `target.template` to produce a `kubernetes.io/dockerconfigjson` Secret:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: quay-pull-secret-sync
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: my-cluster-secret-store   # your SecretStore or ClusterSecretStore
    kind: ClusterSecretStore
  target:
    name: quay-pull-secret
    creationPolicy: Owner
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {"auths":{"quay.io":{"username":"{{ .username }}","password":"{{ .password }}"}}}
  data:
    - secretKey: username
      remoteRef:
        key: quay-credentials    # secret path in your store
        property: username
    - secretKey: password
      remoteRef:
        key: quay-credentials
        property: password
```

Then reference the secret in your values:

```yaml
ontoserver:
  deployment:
    imagePullSecrets:
      - name: quay-pull-secret
```

### Option C — pre-created secret

Create the secret manually and reference it:

```bash
kubectl create secret docker-registry my-pull-secret -n my-namespace \
  --docker-server=quay.io \
  --docker-username=<quay-username> \
  --docker-password=<quay-password>
```

```yaml
ontoserver:
  deployment:
    imagePullSecrets:
      - name: my-pull-secret
```

## Testing

### Unit Tests

Unit tests render chart templates and assert on the output without requiring a cluster. They use the [`helm-unittest`](https://github.com/helm-unittest/helm-unittest) plugin.

**Install the plugin (one-time):**

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
```

**Run unit tests:**

```bash
helm unittest ./charts/ontoserver
```

### Integration Tests

Integration tests run against a live deployment using `helm test`. They require no extra plugins — just a running cluster with the chart installed.

The **metadata test** (always runs) checks the FHIR CapabilityStatement and, if `ontoserver.managementService.enabled=true`, the Spring Boot Actuator health endpoint.

The **FHIR read-only test** (runs when `ontoserver.deployment.isReadOnly=true`) verifies that write requests are rejected and that basic read access remains available.

The **FHIR read-write test** (only runs when `ontoserver.deployment.isReadOnly=false`) loads a CodeSystem, ValueSet, and ConceptMap, then exercises `$lookup`, `$validate-code`, `$expand`, `$translate`, and `$closure` operations.

The **`$closure` routing test** (only runs when `deployment.kind: StatefulSet` and `deployment.type: scaled`) validates that both pods are reachable via their headless DNS names, that `RELEASE-ontoserver-pod0-service` routes correctly to pod-0, and that the stateful closure table created via the pod-0 service is accessible in a subsequent call to both the service and pod-0 directly.

By default, completed Helm test Jobs are retained for 30 minutes via `ontoserver.tests.ttlSecondsAfterFinished: 1800`, which leaves time to inspect pod logs before Kubernetes cleans them up. Set the value to `0` to delete them immediately after completion when the cluster TTL-after-finished controller processes them.

```bash
# Install in read-write mode to enable all integration tests
helm install my-ontoserver ./charts/ontoserver \
  --set ontoserver.deployment.isReadOnly=false \
  --set ontoserver.managementService.enabled=true \
  --set ontoserver.imageCredentials.username=<quay-username> \
  --set ontoserver.imageCredentials.password=<quay-password> \
  -f your-values.yaml

# Run integration tests
helm test my-ontoserver
```

> **Note:** `helm test --logs` does not work with Job-based test hooks in Helm 3.17+. To collect test output, use kubectl label selectors after the run:
> ```bash
> kubectl logs -l job-name=my-ontoserver-ontoserver-test-metadata
> kubectl logs -l job-name=my-ontoserver-ontoserver-test-fhir-ro
> kubectl logs -l job-name=my-ontoserver-ontoserver-test-fhir-rw
> kubectl logs -l job-name=my-ontoserver-ontoserver-test-closure-scaled   # scaled StatefulSet only
> ```
> These Jobs are retained for `ontoserver.tests.ttlSecondsAfterFinished` seconds after completion. The default is 1800 seconds (30 minutes).

#### Scaled StatefulSet integration test

The `$closure` routing test requires a scaled StatefulSet deployment with an external PostgreSQL database and ≥8 GB RAM (2 Ontoserver pods + PostgreSQL). Run it locally using a [k3d](https://k3d.io/) cluster.

A complete local test procedure is documented in [`charts/ontoserver/tests/fixtures/scaled-values.yaml`](tests/fixtures/scaled-values.yaml).

## Persistence

Two persistence modes are available via `ontoserver.deployment.persistence.mode`:

- **`split`** (default) — separate PVCs for application files (`/var/onto`) and database files (`/var/lib/postgresql/data`).
- **`shared`** - a single PVC for both, with the database stored under a db/ subPath; shared mode uses the files.* persistence settings, while dbfiles.* is ignored.

For `Deployment` kind, persistence is disabled by default and opt-in via `persistence.enabledForDeployment: true`. For `StatefulSet`, PVCs are always created via `volumeClaimTemplates`.

`existingVolume.enabled: true` is supported for `Deployment` only. It is not supported for `StatefulSet`, because a StatefulSet needs a distinct volume per replica and a single pre-bound PV name cannot satisfy all generated PVCs. For StatefulSets, use dynamic provisioning via `storageClass` so each pod gets its own volume automatically. The default provisioner and storage parameters are **AKS/Azure-specific** (`disk.csi.azure.com`, `Premium_LRS`). Replace `storageClass.provided.storageProvisioner` and `storageClass.provided.storageParameters` with values appropriate for your cloud provider (e.g. `ebs.csi.aws.com` on EKS).

When `storageClass.provided.enabled: false`, set `storageClass.name` to a specific StorageClass name, or leave it empty (`name: ""`) to omit `storageClassName` from the PVC spec and let Kubernetes use the cluster default StorageClass (e.g. `local-path` on k3d/k3s, `standard` on minikube, `gp2`/`gp3` on EKS).

### Pre-provisioned PersistentVolumes

When binding a `Deployment` PVC to a pre-provisioned disk (e.g. an existing Azure Disk or EBS volume), enable the chart-managed PV alongside `existingVolume`:

**AKS (Azure Disk):**

```yaml
ontoserver:
  deployment:
    persistence:
      files:
        existingVolume:
          enabled: true
          name: my-files-pv
        pv:
          enabled: true
          diskURI: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/disks/<disk>
          csiDriver: disk.csi.azure.com
          storageSize: 1Ti
```

**EKS (EBS):**

```yaml
ontoserver:
  deployment:
    persistence:
      files:
        existingVolume:
          enabled: true
          name: my-files-pv
        pv:
          enabled: true
          diskURI: vol-0abc123def456789
          csiDriver: ebs.csi.aws.com
          storageSize: 1Ti
```

The PV name is taken from `existingVolume.name` so the PVC and PV stay in sync. `storageClassName` defaults to `RELEASE-ontoserver-files` (matching the chart-managed StorageClass). For `dbfiles` in `split` mode, the equivalent `dbfiles.pv` block creates the db-files PV named from `dbfiles.existingVolume.name`.

> **StatefulSet limitation:** Do not set `files.existingVolume.*` or `dbfiles.existingVolume.*` with `deployment.kind: StatefulSet`. The chart rejects this configuration. Use a StorageClass-backed StatefulSet instead.

> **Upgrade note:** Chart-managed PVCs are annotated with `helm.sh/resource-policy: keep`. This prevents Helm from patching the immutable `spec` fields (such as `storageClassName`) on upgrade and ensures PVCs are retained on `helm uninstall`. Delete PVCs manually if a full teardown is required.

## Health Checking

The readiness probe calls `/healthcheck.sh` with the flag set in `ontoserver.healthCheckOption`. The script queries the Spring Boot actuator health endpoint and applies additional checks based on the flag:

| Flag | Behaviour |
|------|-----------|
| *(none)* | Basic FHIR health check only |
| `-f` | *(default)* Fail if startup preload has failed or is currently running but will fail |
| `-s` | Fail if startup preload has not yet completed successfully (blocks readiness until preload finishes) |
| `-l` | Fail while the startup preload is still running |
| `-L` | Fail while any preload (including on-demand) is still running |
| `-p` | Fail if any Lucene indexes are unhealthy |

**`-f` (default)** prevents traffic reaching a pod whose startup preload has definitively failed, without blocking readiness while a preload is still in progress. Use **`-s`** if you want the pod held out of rotation until its startup preload has finished successfully — useful when serving requests against a partially-loaded terminology is undesirable.

### Healthcheck and HTTPS mode (`ONTOSERVER_INSECURE: "false"`)

> **Note:** This workaround is only needed for Ontoserver 6.24.2 and below.

All three probes (startup, liveness, readiness) call `/healthcheck.sh` inside the container. On first run, the script checks the Spring Boot actuator health endpoint (`http://localhost:18080`) and, if Ontoserver has not yet been initialised (`initialized: false`), triggers initialization by calling the FHIR metadata endpoint on the main server port.

When `ONTOSERVER_INSECURE: "false"`, the main server port is HTTPS on 8443. The script constructs the URL as `https://localhost:8443/fhir/metadata` and fetches it with `wget` — but `wget` inside the container rejects the bundled self-signed certificate, causing the initialization call to fail and the probe to exit non-zero. The pod then restarts in a loop and never becomes healthy.

The workaround is a `postStart` lifecycle hook that patches the `wget` call inside the script to add `--no-check-certificate` before any probe fires. The hook runs before `startupProbe.initialDelaySeconds` elapses, so the patched script is in place when Kubernetes issues the first probe:

```yaml
ontoserver:
  deployment:
    containerPort: 8443
    lifecycle:
      postStart:
        exec:
          command:
            - /bin/sh
            - -c
            - sed -i 's|wget -o /dev/null -q -O /dev/null|wget --no-check-certificate -o /dev/null -q -O /dev/null|' /healthcheck.sh
  config:
    ONTOSERVER_INSECURE: "false"
```

This is exactly the configuration used by the `traefik-https-backend` integration test fixture.

## Amazon EKS

The chart works on EKS with the following configuration differences from the defaults (which are AKS/Azure-oriented).

### Storage

The default `storageProvisioner` and `storageParameters` are Azure-specific. Replace them with EKS CSI drivers:

| Use case | Provisioner | accessMode | Notes |
|----------|-------------|------------|-------|
| Single instance | `ebs.csi.aws.com` | `ReadWriteOnce` | EBS CSI add-on required |
| Scaled (multi-replica) | `ebs.csi.aws.com` | `ReadWriteOnce` | Use `StatefulSet` kind — each pod gets its own EBS volume via `volumeClaimTemplates` |

> **Important:** Do **not** use a shared `ReadWriteMany` volume (e.g. EFS) across scaled replicas — each instance writes its own Lucene indexes and sharing a volume between pods will corrupt them. Use `StatefulSet` kind so each pod gets its own PVC.

You must also override the Azure-specific `storageParameters` keys to prevent them from leaking into the rendered StorageClass. See `examples/eks-values.yaml` for a complete reference.

To bind to a pre-provisioned EBS volume instead of dynamically provisioning one, use `files.pv` (and `dbfiles.pv` in split mode) — see [Pre-provisioned PersistentVolumes](#pre-provisioned-persistentvolumes).

### Ingress

With **AWS Load Balancer Controller** (recommended):

```yaml
ontoserver:
  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
  tls:
    enabled: false  # TLS terminated at the ALB
```

The bundled F5 nginx-ingress subchart also works on EKS and deploys via an NLB.

Gateway API is supported if [Envoy Gateway](https://gateway.envoyproxy.io/) is installed. AWS Load Balancer Controller also exposes a Gateway API implementation, but the Envoy-specific policies (`ClientTrafficPolicy`, `BackendTrafficPolicy`, `SecurityPolicy`) will not apply with it.

### IRSA (IAM Roles for Service Accounts)

To grant the pod AWS permissions (e.g. access to Secrets Manager or S3):

```yaml
ontoserver:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/ontoserver-role
```

To reference a pre-existing ServiceAccount without the chart creating one:

```yaml
ontoserver:
  serviceAccount:
    create: false
    name: my-existing-sa
```

### Node Targeting

```yaml
ontoserver:
  nodeSelector:
    eks.amazonaws.com/nodegroup: ontoserver-nodes
```

See [`examples/eks-values-with-alb-ingress.yaml`](examples/eks-values-with-alb-ingress.yaml) for a complete EKS reference.

## Azure AKS

AKS is the primary platform used by the chart developers. The default `storageProvisioner` (`disk.csi.azure.com`) and `storageParameters` (`Premium_LRS`, `Managed`) are Azure-specific and work out of the box on AKS without any changes.

The recommended networking setup on AKS is **Gateway API via Envoy Gateway** — see the prerequisites block at the top of this file.

```yaml
ontoserver:
  gateway:
    enabled: true
    className: envoy-gateway-class   # default — matches Envoy Gateway install
```

For automatic TLS certificate provisioning, enable cert-manager:

```yaml
ontoserver:
  tls:
    enabled: true
    certRef: ontoserver-tls
  certmanager:
    enabled: true
    clusterIssuerName: letsencrypt-prod
    email: your-email@example.com
```

For a scaled (multi-replica) deployment on AKS, use `StatefulSet` kind so each pod gets its own PVC via `volumeClaimTemplates`. Do **not** use a shared `ReadWriteMany` volume (e.g. Azure Files) across replicas — each instance writes its own Lucene indexes and sharing a volume between pods will corrupt them. An external PostgreSQL instance is required.

See [`examples/aks-values.yaml`](examples/aks-values.yaml) for a complete AKS reference.

## Local Development (k3d / minikube)

For local development or CI testing, disable the chart-managed `StorageClass` and let the cluster use its own default provisioner (`local-path` on k3d/k3s, `standard` on minikube):

```yaml
ontoserver:
  serverName: localhost
  hostNames:
    - localhost

  deployment:
    persistence:
      enabledForDeployment: true
      files:
        storageClass:
          provided:
            enabled: false   # use cluster default StorageClass
          name: ""
      dbfiles:
        storageClass:
          provided:
            enabled: false
          name: ""
```

**Networking on a local cluster — choose one:**

Option A (recommended) — Gateway API via Envoy Gateway (tested by the chart developers):
```bash
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.6.1/install.yaml
```
```yaml
ontoserver:
  gateway:
    enabled: true
    className: envoy-gateway-class
  tls:
    enabled: false
```

Option B — Traefik Ingress (k3d / k3s default, no extra install needed):
```yaml
ontoserver:
  ingress:
    enabled: true
    className: traefik
  tls:
    enabled: false
```

Option C — bundled F5 nginx-ingress subchart (works on any local cluster):
```yaml
ontoserver:
  ingress:
    enabled: true
    className: ontoserver-nginx
  tls:
    enabled: false

nginx-ingress:
  enabled: true
```

### k3d quick-start

The fastest way to get Ontoserver running locally is k3d with its built-in Traefik controller:

```bash
# 1. Create a cluster with port 80 mapped to localhost
#    (port 80 requires root on macOS/Linux; 8080 is the safe default)
k3d cluster create ontoserver --port "8080:80@loadbalancer"

# 2. Install the chart (pass your quay.io credentials)
helm install my-ontoserver . -f examples/k3d-traefik-values.yaml -n my-ontoserver --create-namespace \
  --set ontoserver.imageCredentials.username=<quay-username> \
  --set ontoserver.imageCredentials.password=<quay-password>

# 3. Wait for the pod to become ready
kubectl rollout status deployment/my-ontoserver-ontoserver

# 4. Open http://localhost:8080/fhir
```

> **Port mapping note:** When the load balancer port differs from the standard HTTP/HTTPS port (as with `8080:80` above), set `ontoserver.serverPort: "8080"` in your values file. The chart uses this to construct the Spring Boot base URLs (`ontoserver.fhir.base`, `ontoserver.formats.html.base`, `ontoserver.synd.base`) that Ontoserver embeds in responses. Without it, Ontoserver would advertise `http://localhost/fhir` instead of `http://localhost:8080/fhir`. The `k3d-traefik-values.yaml` example already sets this.

See [`examples/k3d-traefik-values.yaml`](examples/k3d-traefik-values.yaml) for the complete quick-start values file and [`examples/local-values.yaml`](examples/local-values.yaml) for a general local cluster reference.

### ArgoCD

Ready-to-use ArgoCD Application manifests are in [`examples/argocd/`](../../examples/argocd/) at the root of this repository. Reference them directly from your ArgoCD instance or use them as a starting point.

| File | How to use | Description |
|------|------------|-------------|
| [`dev-readonly.yaml`](../../examples/argocd/dev-readonly.yaml) | App-of-Apps | Read-only dev server — sidecar PostgreSQL, ephemeral storage, Varnish. No networking — reference directly from an App-of-Apps and add your own gateway/ingress. |
| [`dev-readonly-envoy-appset.yaml`](../../examples/argocd/dev-readonly-envoy-appset.yaml) | ApplicationSet | Same topology with Envoy Gateway. Hostname and namespace are parameterised — supports multiple instances from a single manifest. |

The ArgoCD examples use multi-source Applications with both the `ontoserver` and `ontoserver-extras` charts as sources, wired together so that enabling Varnish automatically routes the Ingress through it. See the [extras chart README](../../charts/ontoserver-extras/README.md#deploying-alongside-the-ontoserver-chart) for the wiring details.

> **Note:** The GitHub Actions integration workflow uses a similar k3d setup (single agent, no load balancer, Traefik disabled) to run `helm install` followed by `helm test` in both read-only and read-write modes. See [`.github/workflows/integration-tests.yml`](../../.github/workflows/integration-tests.yml) for details.

## Optional Feature Prerequisites

| Feature | Cluster Requirement |
| ------- | ------------------- |
| `ontoserver.metrics.serviceMonitor.enabled` | [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) CRDs installed |
| `ontoserver.opentelemetry.instrumentation.enabled` | [OpenTelemetry Operator](https://opentelemetry.io/docs/kubernetes/operator/) installed |
| `envoygateway.*` policies | [Envoy Gateway](https://gateway.envoyproxy.io/) CRDs installed |
| `envoygateway.gatewayServiceMonitor.enabled` | [Envoy Gateway](https://gateway.envoyproxy.io/) installed + [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) CRDs installed |
| `traefik.ingressRoute.enabled` | [Traefik](https://doc.traefik.io/traefik/) installed with CRD support (`traefik.io/v1alpha1` for v3, `traefik.containo.us/v1alpha1` for v2) |
| `ontoserver.externalSecret.enabled` | [External Secrets Operator](https://external-secrets.io/) installed |

## Postgres sidecar

When `ontoserver.deployment.db.enabled: true` (the default), a Postgres container is injected as a [native sidecar init container](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) (`restartPolicy: Always`). This requires **Kubernetes 1.29+**.

The native sidecar pattern provides a hard ordering guarantee: Kubernetes will not start the Ontoserver container until the Postgres sidecar has passed its readiness probe (`pg_isready`). This eliminates the race condition where Ontoserver would fail on startup because Postgres was not yet accepting connections — previously a one-time restart on cold pod starts.

**Startup probe behaviour:**
Ontoserver's `startupProbe` (using `healthcheck.sh`) runs after Postgres is ready, polling until Ontoserver itself is up. With a `failureThreshold` of 150 and `periodSeconds` of 2, the probe allows up to 5 minutes for Ontoserver to start — enough headroom for slow environments such as AKS. Once the startup probe passes, the `readinessProbe` kicks in immediately (default `initialDelaySeconds: 0`).

**Constraints:**
- `scaled` deployments cannot use the Postgres sidecar — an external database is required.
- `StatefulSet` kind supports the Postgres sidecar for `single` deployments only.

## Configuring an external database

If you disable the embedded sidecar (`ontoserver.deployment.db.enabled: false`), you must supply the following in `ontoserver.config`:

```yaml
spring.datasource.url: "jdbc:postgresql://<host>:<port>/<db>"
spring.datasource.username: "<user>"
```
and pass the database password via `ontoserver.secretConfig`
```yaml
spring.datasource.password: "<password>"
```

See the [Spring Boot DataSource configuration guide](https://docs.spring.io/spring-boot/docs/current/reference/html/data.html#data.sql.datasource.configuration).

## Customisation

To override the default CSS and logos under `/fhir/.well-known`, create a `ConfigMap`:

```bash
kubectl create configmap ontoserver-customization \
  --from-file=logo.png \
  --from-file=organisation_logo.png \
  --from-file=organisation.css
```

Then set:

```yaml
ontoserver.customization: "ontoserver-customization"
```

## Outbound HTTP proxy

If Ontoserver needs to route outbound internet traffic through an HTTP proxy — for example to reach SNOMED CT syndication feeds or external FHIR terminology servers — you can set the relevant environment variables via `ontoserver.config`:

```yaml
ontoserver:
  config:
    HTTP_PROXY: "http://proxy.example.com:3128"
    HTTPS_PROXY: "http://proxy.example.com:3128"
    NO_PROXY: ".svc.cluster.local,.svc,.example.com"
```

Ontoserver is a Java application and does not read the standard Linux proxy environment variables. If the proxy requires host and port to be specified separately, use the Java-style variables instead:

```yaml
ontoserver:
  config:
    HTTP_PROXY_HOST: "proxy.example.com"
    HTTP_PROXY_PORT: "3128"
    HTTPS_PROXY_HOST: "proxy.example.com"
    HTTPS_PROXY_PORT: "3128"
```

> **Note:** This is only needed when Ontoserver itself requires a specific proxy for outbound connections. If your entire cluster is behind a corporate proxy, configure the proxy at the node or container runtime level instead — pods will inherit it automatically and per-pod configuration is unnecessary.

## Gateway API vs Ingress

> **Gateway API is the recommended networking mode.** Active development of the standard Kubernetes Ingress API is suspended by the K8s community in favor of the newer Gateway API. Gateway API is the configuration used by the chart developers and unlocks the full set of Envoy Gateway traffic policies (rate limiting, request buffering, CIDR deny rules). Unless you have a specific reason to use Ingress (e.g. legacy cluster constraints), we strongly steer you toward Envoy Gateway and the Gateway API.

By default none is enabled — the chart deploys Ontoserver with no external access, suitable for internal use or testing. Enable one to expose the server:

* **Gateway API** (`ontoserver.gateway.enabled: true`) *(recommended)*: requires Gateway API CRDs and a compatible GatewayClass (e.g. [Envoy Gateway](https://gateway.envoyproxy.io/), [Traefik](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/), [Cilium](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/), or any conformant implementation). Creates `Gateway`, `HTTPRoute`, and optionally a cert-manager `Issuer` resource. The default `className` is `envoy-gateway-class` — set `ontoserver.gateway.className` to match your GatewayClass. The default listener port is `443`; some implementations use a different port (e.g. Traefik defaults to `8443` — set `ontoserver.gateway.listenerPortSecure: 8443`). TLS termination is optional: set `ontoserver.tls.enabled: true` with a certificate reference, or enable cert-manager for automatic provisioning.
* **Ingress** (`ontoserver.ingress.enabled: true`) *(deprecated)*: creates a standard `networking.k8s.io/v1` Ingress. Use the bundled F5 nginx-ingress subchart (`nginx-ingress.enabled: true`), the cluster's default controller (e.g. Traefik on k3d/k3s), or any other Ingress controller by setting `ontoserver.ingress.className` appropriately.
* **Traefik IngressRoute** (`traefik.ingressRoute.enabled: true`): creates a Traefik-native `IngressRoute` CRD resource. Use this instead of `ontoserver.ingress` when Traefik is your ingress controller **and** any backend pod exposes HTTPS/TLS. See [Traefik Ingress Controller](#traefik-ingress-controller-1) below.

Gateway API, Ingress, and IngressRoute are mutually exclusive. All three support a `backendServiceNameOverride` to route traffic through an intermediate proxy such as the Varnish cache from `ontoserver-extras`:

- Gateway: `ontoserver.gateway.backendServiceNameOverride: <release>-varnish-service`
- Ingress: `ontoserver.ingress.backendServiceNameOverride: <release>-varnish-service`
- IngressRoute: `traefik.ingressRoute.backendServiceNameOverride: <release>-varnish-service`

See the [extras chart README](../../charts/ontoserver-extras/README.md) for the full wiring instructions, including the recommended ArgoCD multi-source approach.

**Common GatewayClass configuration reference:**

| Implementation | `gateway.className` | `gateway.listenerPortSecure` | Notes |
|---|---|---|---|
| [Envoy Gateway](https://gateway.envoyproxy.io/) *(default)* | `envoy-gateway-class` | `443` | Full Envoy policy support |
| [Traefik](https://doc.traefik.io/traefik/) v3.1+ | `traefik` | `8443` | Default k3d/k3s install |
| [Cilium](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/) | `cilium` | `443` | Requires Cilium CNI with Gateway API enabled |
| AWS Load Balancer Controller | `alb` | `443` | Envoy policies will not apply |

The Envoy Gateway traffic policies (`envoygateway.*`) are specific to Envoy Gateway and should remain disabled when using other implementations.

### `$closure` routing for scaled StatefulSet deployments

The [`$closure` FHIR operation](https://www.hl7.org/fhir/conceptmap-operation-closure.html) is stateful — all requests for a given closure table must reach the same instance. For scaled StatefulSet deployments (`deployment.kind: StatefulSet` and `deployment.type: scaled`), the chart automatically creates a dedicated `RELEASE-ontoserver-pod0-service` selecting only pod-0, and renders a dedicated route matching `/fhir/$closure` before the catchall `/` rule.

For Gateway API, this is a **separate `HTTPRoute` resource** (`RELEASE-closure-route`) rather than a rule in the main `RELEASE-route`, which ensures the more-specific path takes precedence regardless of Gateway implementation. For Ingress and Traefik IngressRoute it is a path rule within the same resource.

The `$closure` route backend follows `backendServiceNameOverride` — defaulting to `RELEASE-ontoserver-pod0-service` when no override is set. If `backendServiceNameOverride` points to a proxy such as Varnish, `$closure` is also routed through it; ensure that proxy handles stateful sticky routing to a single upstream instance.

The routing is validated by the `$closure` routing integration test (`helm test`) which is automatically included for scaled StatefulSet deployments. See [Scaled StatefulSet integration test](#scaled-statefulset-integration-test) for local test instructions.

## Envoy Gateway

### Infrastructure (GatewayClass and EnvoyProxy)

Set `envoygateway.createGatewayClass: true` (requires `ontoserver.gateway.enabled: true`) to let the chart create and manage the `GatewayClass` and `EnvoyProxy` resources. This is useful when Ontoserver owns its own Gateway installation rather than sharing a cluster-wide one.

The `GatewayClass` is named after `ontoserver.gateway.className` and the `EnvoyProxy` is created in `envoygateway.controlPlaneNamespace` (default: `envoy-gateway-system`). The EnvoyProxy configures:

- Prometheus scrape annotations on the Envoy service (ports `19001` for metrics, `19000` for admin)
- A `PodDisruptionBudget` via `envoygateway.envoyProxy.pdbMinAvailable`
- Structured JSON access logging to stdout (`envoygateway.envoyProxy.accessLog.enabled`). The log format is fully configurable via `envoygateway.envoyProxy.accessLog.format` — useful for adjusting fields or disabling verbose logging in production.

### Traffic Policies

Three optional traffic policies and a data-plane ServiceMonitor can be independently enabled (all require `ontoserver.gateway.enabled: true` and Envoy Gateway CRDs):

- **ClientTrafficPolicy** (`envoygateway.clientTrafficPolicy.enabled`) — applies an HTTP idle timeout on inbound connections from clients. Optionally enables PROXY protocol (`proxyProtocol.enabled`) for upstream load balancers that send PROXY protocol headers (e.g. AWS NLB), and configures client IP detection via `clientIPDetection.xForwardedFor.numTrustedHops` (set to `0` alongside PROXY protocol to use the peer address rather than XFF headers).
- **BackendTrafficPolicy** (`envoygateway.backendTrafficPolicy.enabled`) — caps the maximum upstream request body size, enforces a local rate limit (requests per time unit), and optionally throttles specific bot user agents. Set `envoygateway.backendTrafficPolicy.blockedUserAgents` to a list of User-Agent substrings (matched as regular expressions) to rate-limit those clients to 1 request per hour — effectively blocking bots such as SemrushBot or AhrefsBot that generate large volumes of traffic:

  ```yaml
  envoygateway:
    backendTrafficPolicy:
      enabled: true
      blockedUserAgents:
        - SemrushBot
        - AhrefsBot
  ```

  Matched clients receive `429 Too Many Requests`. The global rate limit still applies to all other traffic.
- **SecurityPolicy** (`envoygateway.securityPolicy.enabled`) — enforces IP-based authorization by denying traffic from a list of CIDRs.
- **Gateway ServiceMonitor** (`envoygateway.gatewayServiceMonitor.enabled`) — creates a Prometheus `ServiceMonitor` targeting the Envoy Gateway data-plane pods (scraping `/stats/prometheus` on the `metrics` port). Set `envoygateway.controlPlaneNamespace` to the namespace where Envoy Gateway is installed (default: `envoy-gateway-system`). Requires Prometheus Operator CRDs.

## Traefik Ingress Controller

### IngressRoute vs standard Ingress

Traefik supports both the standard Kubernetes `Ingress` API (`ontoserver.ingress.enabled: true`, `className: traefik`) and its own `IngressRoute` CRD (`traefik.ingressRoute.enabled: true`). The key difference is TLS backend trust:

- **Standard Ingress** — Traefik, unlike NGINX, does **not** connect to self-signed backend TLS certificates by default. There is no way to attach a `ServersTransport` to a standard `Ingress` resource, so backend certificate trust cannot be configured through the standard API.
- **IngressRoute** — Traefik's native CRD allows a `ServersTransport` resource to be attached directly to a backend service, giving explicit control over how Traefik connects to TLS backends (CA trust, client certificates, insecure skip-verify).

Use `traefik.ingressRoute.enabled: true` whenever:
1. Traefik is your ingress controller, **and**
2. Any backend pod in the release exposes HTTPS/TLS (e.g. Ontoserver with `ONTOSERVER_INSECURE: "false"`, OntoCloak/Keycloak, or any TLS-terminating sidecar).

For HTTP backends with Traefik, the standard `ontoserver.ingress` is sufficient.

### HTTPS backend (Ontoserver TLS mode)

By default (`ONTOSERVER_INSECURE: "true"`) Ontoserver serves plain HTTP on port 8080. Setting `ONTOSERVER_INSECURE: "false"` restores Ontoserver's out-of-box behaviour: HTTPS on port **8443** using its bundled self-signed keystore. You must also set `ontoserver.deployment.containerPort: 8443` so the Kubernetes Service routes traffic to the correct container port.

The client-to-Traefik leg remains plain HTTP via the `web` entrypoint; TLS is only on the Traefik-to-Ontoserver backend leg.

> **Important — probe patch required (Ontoserver 6.24.2 and below):** When `ONTOSERVER_INSECURE: "false"`, the container's `/healthcheck.sh` uses `wget` to trigger FHIR initialization via `https://localhost:8443`. Because the certificate is self-signed, `wget` rejects it and the startup probe fails permanently. A `postStart` lifecycle hook is required to patch the script before the first probe fires. See [Healthcheck and HTTPS mode](#healthcheck-and-https-mode-ontoserver_insecure-false) for the full explanation.

```yaml
ontoserver:
  deployment:
    containerPort: 8443   # Ontoserver's HTTPS port
    lifecycle:
      postStart:
        exec:
          command:
            - /bin/sh
            - -c
            - sed -i 's|wget -o /dev/null -q -O /dev/null|wget --no-check-certificate -o /dev/null -q -O /dev/null|' /healthcheck.sh
  config:
    ONTOSERVER_INSECURE: "false"

traefik:
  ingressRoute:
    enabled: true
    entryPoints:
      - web               # client → Traefik over plain HTTP
    backendPort: 80       # Kubernetes Service port (Service maps 80 → containerPort 8443)
    backendScheme: https  # Traefik → Ontoserver over HTTPS
    serversTransport:
      enabled: true
      insecureSkipVerify: true   # trust Ontoserver's self-signed certificate
```

### ServersTransport

When `traefik.ingressRoute.serversTransport.enabled: true`, the chart creates a `ServersTransport` resource in the same namespace as the `IngressRoute`. The `backendPort` value is always the **Kubernetes Service port** (default `80`), not the container port. Two trust modes are supported:

**Option A — Skip verification (self-signed certificates):**

```yaml
traefik:
  ingressRoute:
    enabled: true
    backendPort: 80       # Kubernetes Service port
    backendScheme: https
    serversTransport:
      enabled: true
      insecureSkipVerify: true
```

**Option B — CA-signed certificate (provide the CA):**

```yaml
traefik:
  ingressRoute:
    enabled: true
    backendPort: 80       # Kubernetes Service port
    backendScheme: https
    serversTransport:
      enabled: true
      insecureSkipVerify: false
      rootCAsSecrets:
        - my-backend-ca-secret   # Secret with key tls.crt containing the CA certificate
```

### Traefik API version

The templates use `traefik.io/v1alpha1` (Traefik v3). For Traefik v2, change the `apiVersion` in `templates/traefik-ingressroute.yaml` and `templates/traefik-serverstransport.yaml` to `traefik.containo.us/v1alpha1`.

## Observability

### Management Service

Set `ontoserver.managementService.enabled: true` to create a dedicated `ClusterIP` service exposing the Spring Boot Actuator on port 18080. This is a prerequisite for Prometheus scraping.

### Prometheus Metrics

Set `ontoserver.metrics.serviceMonitor.enabled: true` to create a Prometheus `ServiceMonitor` that scrapes `/actuator/prometheus` from the management service. Requires both `managementService.enabled: true` and the Prometheus Operator CRDs installed in the cluster.

### OpenTelemetry Tracing

Set `ontoserver.opentelemetry.instrumentation.enabled: true` to create an OpenTelemetry `Instrumentation` resource for Java auto-instrumentation. The chart automatically adds the `instrumentation.opentelemetry.io/inject-java` pod annotation on the Ontoserver pod. An exporter endpoint (`ontoserver.opentelemetry.instrumentation.exporter.endpoint`) is required. Requires the OpenTelemetry Operator installed in the cluster.

## External Secrets

Set `ontoserver.externalSecret.enabled: true` to create an `ExternalSecret` resource that syncs secrets from an external store (e.g. AWS Secrets Manager, Azure Key Vault, HashiCorp Vault) into a Kubernetes Secret, which is then injected as environment variables into the Ontoserver pod.

Required fields:
- `ontoserver.externalSecret.secretStoreRef.name` — name of the `SecretStore` or `ClusterSecretStore`.
- At least one of `ontoserver.externalSecret.data` or `ontoserver.externalSecret.dataFrom`.

Example using individual key mappings:

```yaml
ontoserver:
  externalSecret:
    enabled: true
    secretStoreRef:
      name: my-cluster-secret-store
      kind: ClusterSecretStore
    data:
      - secretKey: spring.datasource.password
        remoteRef:
          key: /myapp/db
          property: password
```

Requires the [External Secrets Operator](https://external-secrets.io/) installed in the cluster.

## Parameters

### Deployment

| Name                                                                                        | Description                                                                                                                                                                                                                   | Value                             |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `ontoserver.deployment.kind`                                                                | Kind of controller (Deployment or StatefulSet)                                                                                                                                                                                | `Deployment`                      |
| `ontoserver.deployment.type`                                                                | single|scaled deployment topology                                                                                                                                                                                             | `single`                          |
| `ontoserver.deployment.image`                                                               | Container image for OntoServer                                                                                                                                                                                                | `quay.io/aehrc/ontoserver:ctsa-6` |
| `ontoserver.deployment.imagePullPolicy`                                                     | Image pull policy                                                                                                                                                                                                             | `IfNotPresent`                    |
| `ontoserver.deployment.containerPort`                                                       | Container port Ontoserver listens on. Use 8080 for HTTP (ONTOSERVER_INSECURE=true) or 8443 for HTTPS (ONTOSERVER_INSECURE=false).                                                                                             | `8080`                            |
| `ontoserver.deployment.lifecycle`                                                           | Container lifecycle hooks (postStart / preStop). Passed through as-is to the container spec.                                                                                                                                  | `{}`                              |
| `ontoserver.deployment.imagePullSecrets`                                                    | Additional pre-created image pull secrets to attach to the pod (merged with the chart-managed pull secret when imageCredentials are set)                                                                                      | `[]`                              |
| `ontoserver.deployment.isReadOnly`                                                          | Ontoserver in read‑only mode - keep it true for scaled                                                                                                                                                                        | `true`                            |
| `ontoserver.deployment.replicas`                                                            | Number of replicas - min 2 for scaled deployment - can be set to 0                                                                                                                                                            | `1`                               |
| `ontoserver.deployment.clusterName`                                                         | Cluster name for auto-discovery in scaled deployments (overrides the default "ontoserver" set in application.properties); ignored for single deployments                                                                      | `""`                              |
| `ontoserver.deployment.annotations`                                                         | Deployment/Statefulset manifest annotations                                                                                                                                                                                   | `{}`                              |
| `ontoserver.deployment.labels`                                                              | Deployment/Statefulset manifest labels                                                                                                                                                                                        | `{}`                              |
| `ontoserver.deployment.podAnnotations`                                                      | Pod annotations                                                                                                                                                                                                               | `{}`                              |
| `ontoserver.deployment.podLabels`                                                           | Pod labels                                                                                                                                                                                                                    | `{}`                              |
| `ontoserver.deployment.deploymentStrategy`                                                  | K8s update strategy when using Deployment Kind                                                                                                                                                                                | `RollingUpdate`                   |
| `ontoserver.deployment.startupProbe.initialDelaySeconds`                                    | Startup probe initial delay                                                                                                                                                                                                   | `5`                               |
| `ontoserver.deployment.startupProbe.periodSeconds`                                          | Startup probe period                                                                                                                                                                                                          | `2`                               |
| `ontoserver.deployment.startupProbe.failureThreshold`                                       | Startup probe failure threshold                                                                                                                                                                                               | `150`                             |
| `ontoserver.deployment.startupProbe.timeoutSeconds`                                         | Startup probe timeout                                                                                                                                                                                                         | `5`                               |
| `ontoserver.deployment.livenessProbe.initialDelaySeconds`                                   | Liveness probe initial delay                                                                                                                                                                                                  | `15`                              |
| `ontoserver.deployment.livenessProbe.periodSeconds`                                         | Liveness probe period                                                                                                                                                                                                         | `5`                               |
| `ontoserver.deployment.livenessProbe.failureThreshold`                                      | Liveness probe failure threshold                                                                                                                                                                                              | `10`                              |
| `ontoserver.deployment.livenessProbe.timeoutSeconds`                                        | Liveness probe timeout                                                                                                                                                                                                        | `5`                               |
| `ontoserver.deployment.readinessProbe.initialDelaySeconds`                                  | Readiness probe initial delay                                                                                                                                                                                                 | `0`                               |
| `ontoserver.deployment.readinessProbe.periodSeconds`                                        | Readiness probe period                                                                                                                                                                                                        | `5`                               |
| `ontoserver.deployment.readinessProbe.failureThreshold`                                     | Readiness probe failure threshold                                                                                                                                                                                             | `3`                               |
| `ontoserver.deployment.readinessProbe.timeoutSeconds`                                       | Readiness probe timeout                                                                                                                                                                                                       | `5`                               |
| `ontoserver.deployment.persistence.enabledForDeployment`                                    | Enable PVC on Deployment                                                                                                                                                                                                      | `false`                           |
| `ontoserver.deployment.persistence.mode`                                                    | shared | split - Use one or separate PV for db and lucene files                                                                                                                                                               | `split`                           |
| `ontoserver.deployment.persistence.files.accessMode`                                        | PVC access mode. Use ReadWriteOnce for single instances and StatefulSet scaled deployments (each pod gets its own PVC via volumeClaimTemplates). Shared volumes across pods are not supported — Lucene indexes are pod-local. | `ReadWriteOnce`                   |
| `ontoserver.deployment.persistence.files.storageSize`                                       | Requested storage size for the Ontoserver files volume                                                                                                                                                                        | `10Gi`                            |
| `ontoserver.deployment.persistence.files.existingVolume.enabled`                            | Bind to existing PV (Deployment only; not supported for StatefulSet)                                                                                                                                                          | `false`                           |
| `ontoserver.deployment.persistence.files.existingVolume.name`                               | Name of existing PV                                                                                                                                                                                                           | `""`                              |
| `ontoserver.deployment.persistence.files.pv.enabled`                                        | Create a PersistentVolume for the files PVC backed by a pre-provisioned disk (requires existingVolume.enabled and existingVolume.name)                                                                                        | `false`                           |
| `ontoserver.deployment.persistence.files.pv.diskURI`                                        | CSI volumeHandle — cloud-specific disk identifier (required when enabled, e.g. Azure disk resource ID or EBS volume ID)                                                                                                       | `""`                              |
| `ontoserver.deployment.persistence.files.pv.csiDriver`                                      | CSI driver (required when enabled, e.g. disk.csi.azure.com or ebs.csi.aws.com)                                                                                                                                                | `""`                              |
| `ontoserver.deployment.persistence.files.pv.storageClassName`                               | StorageClass name (defaults to RELEASE-ontoserver-files)                                                                                                                                                                      | `""`                              |
| `ontoserver.deployment.persistence.files.storageClass.name`                                 | StorageClass name to use when provided.enabled is false; leave empty to use the cluster default StorageClass                                                                                                                  | `default`                         |
| `ontoserver.deployment.persistence.files.storageClass.provided.enabled`                     | Use provided storageClass                                                                                                                                                                                                     | `true`                            |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageProvisioner`          | CSI driver - the default is AKS/Azure specific, replace for other clouds (e.g. ebs.csi.aws.com for EKS)                                                                                                                       | `disk.csi.azure.com`              |
| `ontoserver.deployment.persistence.files.storageClass.provided.reclaimPolicy`               | Storage Reclaim Policy                                                                                                                                                                                                        | `Retain`                          |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageParameters.skuName`   | Storage SKU name (AKS/Azure specific)                                                                                                                                                                                         | `Premium_LRS`                     |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageParameters.kind`      | Storage kind (AKS/Azure specific)                                                                                                                                                                                             | `Managed`                         |
| `ontoserver.deployment.persistence.files.storageClass.provided.allowVolumeExpansion`        | Allow volume expansion                                                                                                                                                                                                        | `true`                            |
| `ontoserver.deployment.persistence.dbfiles.accessMode`                                      | PVC access mode. Use ReadWriteOnce; only relevant for single-instance deployments with sidecar db (scaled deployments require external PostgreSQL and do not use dbfiles).                                                    | `ReadWriteOnce`                   |
| `ontoserver.deployment.persistence.dbfiles.storageSize`                                     | Requested storage size for the database files volume                                                                                                                                                                          | `10Gi`                            |
| `ontoserver.deployment.persistence.dbfiles.existingVolume.enabled`                          | Bind to existing PV (Deployment only; not supported for StatefulSet)                                                                                                                                                          | `false`                           |
| `ontoserver.deployment.persistence.dbfiles.existingVolume.name`                             | Name of existing PV                                                                                                                                                                                                           | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.enabled`                                      | Create a PersistentVolume for the db-files PVC backed by a pre-provisioned disk (requires existingVolume.enabled and existingVolume.name; only used in split mode with db.enabled)                                            | `false`                           |
| `ontoserver.deployment.persistence.dbfiles.pv.diskURI`                                      | CSI volumeHandle — cloud-specific disk identifier (required when enabled, e.g. Azure disk resource ID or EBS volume ID)                                                                                                       | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.csiDriver`                                    | CSI driver (required when enabled, e.g. disk.csi.azure.com or ebs.csi.aws.com)                                                                                                                                                | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.storageClassName`                             | StorageClass name (defaults to RELEASE-ontoserver-db-files)                                                                                                                                                                   | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.storageClass.name`                               | StorageClass name to use when provided.enabled is false; leave empty to use the cluster default StorageClass                                                                                                                  | `default`                         |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.enabled`                   | Use provided storageClass                                                                                                                                                                                                     | `true`                            |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageProvisioner`        | CSI driver - the default is AKS/Azure specific, replace for other clouds (e.g. ebs.csi.aws.com for EKS)                                                                                                                       | `disk.csi.azure.com`              |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.reclaimPolicy`             | Storage Reclaim Policy                                                                                                                                                                                                        | `Retain`                          |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageParameters.skuName` | Storage SKU name (AKS/Azure specific)                                                                                                                                                                                         | `Premium_LRS`                     |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageParameters.kind`    | Storage kind (AKS/Azure specific)                                                                                                                                                                                             | `Managed`                         |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.allowVolumeExpansion`      | Allow volume expansion                                                                                                                                                                                                        | `true`                            |
| `ontoserver.deployment.podDisruptionBudget.enabled`                                         | Enable PDB for scaled deployments                                                                                                                                                                                             | `true`                            |
| `ontoserver.deployment.podDisruptionBudget.minAvailable`                                    | Minimum pods available - If you set this, maxUnavailable will be ignored                                                                                                                                                      | `1`                               |
| `ontoserver.deployment.db.enabled`                                                          | Enable Postgres sidecar                                                                                                                                                                                                       | `true`                            |
| `ontoserver.deployment.db.postgresVersion`                                                  | Version of Postgres                                                                                                                                                                                                           | `16`                              |

### Registry Credentials

| Name                                   | Description                                                                            | Value     |
| -------------------------------------- | -------------------------------------------------------------------------------------- | --------- |
| `ontoserver.imageCredentials.registry` | Registry hostname (default quay.io)                                                    | `quay.io` |
| `ontoserver.imageCredentials.username` | quay.io username; when set with password the chart creates a pull secret automatically | `""`      |
| `ontoserver.imageCredentials.password` | quay.io password; set via --set or populate via External Secrets                       | `""`      |

### Server

| Name                    | Description                                                                                                      | Value           |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------- | --------------- |
| `ontoserver.serverName` | Server hostname - must match a hostName at ontoserver.hostNames                                                  | `localhost`     |
| `ontoserver.serverPort` | Non-standard port exposed to clients (e.g. 8080 when k3d maps 8080:80). Leave empty for standard ports (80/443). | `""`            |
| `ontoserver.hostNames`  | Hostnames for ingress/gateway                                                                                    | `["localhost"]` |
| `ontoserver.timeZone`   | Server time zone                                                                                                 | `UTC`           |
| `ontoserver.language`   | Locale/language                                                                                                  | `en_US`         |

### Resources

| Name                                              | Description       | Value   |
| ------------------------------------------------- | ----------------- | ------- |
| `ontoserver.resources.ontoserver.requests.cpu`    | CPU request       | `2`     |
| `ontoserver.resources.ontoserver.requests.memory` | Memory request    | `4G`    |
| `ontoserver.resources.ontoserver.limits.cpu`      | CPU limit         | `2`     |
| `ontoserver.resources.ontoserver.limits.memory`   | Memory limit      | `4G`    |
| `ontoserver.resources.ontoserver.initialHeapSize` | Java initial heap | `2800m` |
| `ontoserver.resources.ontoserver.maxHeapSize`     | Java max heap     | `2800m` |
| `ontoserver.resources.db.requests.cpu`            | DB CPU request    | `1`     |
| `ontoserver.resources.db.requests.memory`         | DB memory request | `1G`    |
| `ontoserver.resources.db.limits.cpu`              | DB CPU limit      | `1`     |
| `ontoserver.resources.db.limits.memory`           | DB memory limit   | `1G`    |

### TLS and Networking

| Name                                            | Description                                                                                                                                                                                                                                                        | Value                 |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------- |
| `ontoserver.healthCheckOption`                  | Flag passed to the readiness probe healthcheck.sh; controls what startup/preload conditions must be met before the pod becomes ready (-f: fail if preload failed, -s: wait for successful preload, -l/-L: block while preload runs, -p: fail on unhealthy indexes) | `-f`                  |
| `ontoserver.certmanager.enabled`                | Enable cert-manager (requires cert-manager operator and gateway.enabled)                                                                                                                                                                                           | `false`               |
| `ontoserver.certmanager.clusterIssuerName`      | ClusterIssuer name or prefix for Geteway's Issuer                                                                                                                                                                                                                  | `letsencrypt`         |
| `ontoserver.certmanager.email`                  | Notification email for ACME                                                                                                                                                                                                                                        | `noreply@example.com` |
| `ontoserver.tls.enabled`                        | Enable TLS Termination (requires a TLS secret referenced by certRef)                                                                                                                                                                                               | `false`               |
| `ontoserver.tls.certRef`                        | Reference to Secret containing TLS Certificate                                                                                                                                                                                                                     | `ontoserver-tls`      |
| `ontoserver.gateway.enabled`                    | Enable Gateway API (requires Gateway API CRDs)                                                                                                                                                                                                                     | `false`               |
| `ontoserver.gateway.listenerPortSecure`         | Secure listener port -  Depends on the gateway class - Traefik is 8443                                                                                                                                                                                             | `443`                 |
| `ontoserver.gateway.annotations`                | Gateway annotations                                                                                                                                                                                                                                                | `{}`                  |
| `ontoserver.gateway.infrastructureAnnotations`  | Infrastructure annotations                                                                                                                                                                                                                                         | `{}`                  |
| `ontoserver.gateway.className`                  | GatewayClass name                                                                                                                                                                                                                                                  | `envoy-gateway-class` |
| `ontoserver.gateway.requestTimeout`             | Request timeout duration                                                                                                                                                                                                                                           | `120s`                |
| `ontoserver.gateway.backendServiceNameOverride` | Override HTTPRoute backend service name (e.g. for varnish proxy)                                                                                                                                                                                                   | `""`                  |
| `ontoserver.ingress.enabled`                    | Enable Ingress                                                                                                                                                                                                                                                     | `false`               |
| `ontoserver.ingress.annotations`                | Ingress annotations                                                                                                                                                                                                                                                | `{}`                  |
| `ontoserver.ingress.className`                  | IngressClass name                                                                                                                                                                                                                                                  | `ontoserver-nginx`    |
| `ontoserver.ingress.backendServiceNameOverride` | Override Ingress backend service name (e.g. to route through the Varnish service from ontoserver-extras)                                                                                                                                                           | `""`                  |

### Observability

| Name                                                         | Description                                                                                        | Value                                  |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `ontoserver.managementService.enabled`                       | Enable management service (exposes Spring Boot actuator on port 18080)                             | `false`                                |
| `ontoserver.metrics.serviceMonitor.enabled`                  | Enable Prometheus ServiceMonitor (requires managementService.enabled and Prometheus Operator CRDs) | `false`                                |
| `ontoserver.tests.ttlSecondsAfterFinished`                   | Time to retain Helm test Jobs after completion so logs remain available                            | `1800`                                 |
| `ontoserver.opentelemetry.instrumentation.enabled`           | Enable OpenTelemetry Java auto-instrumentation (requires OpenTelemetry Operator)                   | `false`                                |
| `ontoserver.opentelemetry.instrumentation.image`             | Auto-instrumentation agent image                                                                   | `otel/autoinstrumentation-java:latest` |
| `ontoserver.opentelemetry.instrumentation.serviceName`       | OTel service name (defaults to releaseName/releaseName-ontoserver)                                 | `""`                                   |
| `ontoserver.opentelemetry.instrumentation.propagators`       | Trace context propagators                                                                          | `tracecontext,baggage,b3multi`         |
| `ontoserver.opentelemetry.instrumentation.excludedClasses`   | Classes to exclude from instrumentation                                                            | `ca.uhn.fhir.*Interceptor*`            |
| `ontoserver.opentelemetry.instrumentation.exporter.type`     | Exporter type (zipkin, otlp, etc.)                                                                 | `zipkin`                               |
| `ontoserver.opentelemetry.instrumentation.exporter.endpoint` | Exporter endpoint URL (required when enabled)                                                      | `""`                                   |

### Miscellaneous

| Name                                    | Description                                                                                                                                            | Value   |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------- |
| `ontoserver.tolerations`                | Pod tolerations                                                                                                                                        | `[]`    |
| `ontoserver.nodeSelector`               | Pod node selector (e.g. for EKS node group targeting)                                                                                                  | `{}`    |
| `ontoserver.serviceAccount.create`      | Create a ServiceAccount for the pod (required for IRSA on EKS)                                                                                         | `false` |
| `ontoserver.serviceAccount.name`        | ServiceAccount name. When create: true defaults to <release>-ontoserver. When create: false and name is set, references an existing ServiceAccount.    | `""`    |
| `ontoserver.serviceAccount.annotations` | ServiceAccount annotations (e.g. eks.amazonaws.com/role-arn for IRSA). Only used when create: true.                                                    | `{}`    |
| `ontoserver.customization`              | The name of a ConfigMap containing custom logo and CSS files to be deployed with the application                                                       | `""`    |
| `ontoserver.config.ONTOSERVER_INSECURE` | Disable Ontoserver's inbound TLS listener — set to "true" to serve plain HTTP, "false" (or omit) to serve HTTPS using the bundled self-signed keystore | `true`  |
| `ontoserver.secretConfig`               | Secret-backed Ontoserver config entries                                                                                                                | `{}`    |

### External Secrets

| Name                                            | Description                                                         | Value                |
| ----------------------------------------------- | ------------------------------------------------------------------- | -------------------- |
| `ontoserver.externalSecret.enabled`             | Enable ExternalSecret resource (requires External Secrets Operator) | `false`              |
| `ontoserver.externalSecret.refreshInterval`     | How often the external secret is synced                             | `1h`                 |
| `ontoserver.externalSecret.secretStoreRef.name` | Name of the SecretStore or ClusterSecretStore                       | `""`                 |
| `ontoserver.externalSecret.secretStoreRef.kind` | Kind of the secret store (SecretStore or ClusterSecretStore)        | `ClusterSecretStore` |
| `ontoserver.externalSecret.data`                | List of individual secret key mappings                              | `[]`                 |
| `ontoserver.externalSecret.dataFrom`            | Bulk secret mappings (extract entire secrets as env vars)           | `[]`                 |

### Envoy Gateway

| Name                                                                              | Description                                                                                                                      | Value                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `envoygateway.controlPlaneNamespace`                                              | Namespace where Envoy Gateway control plane is installed                                                                         | `envoy-gateway-system`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `envoygateway.createGatewayClass`                                                 | Create and manage a GatewayClass and EnvoyProxy resource for this release (requires ontoserver.gateway.enabled)                  | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.envoyProxy.name`                                                    | Name of the EnvoyProxy resource                                                                                                  | `default`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `envoygateway.envoyProxy.replicas`                                                | Number of Envoy proxy pod replicas                                                                                               | `2`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `envoygateway.envoyProxy.pdbMinAvailable`                                         | Minimum available pods for the EnvoyProxy PodDisruptionBudget                                                                    | `1`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `envoygateway.envoyProxy.accessLog.enabled`                                       | Enable structured JSON access logging to stdout                                                                                  | `true`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `envoygateway.envoyProxy.accessLog.format`                                        | Envoy access log format string (single-line JSON template)                                                                       | `{"timestamp":"%START_TIME%","authority":"%REQ(:AUTHORITY)%","bytes_received":"%BYTES_RECEIVED%","bytes_sent":"%BYTES_SENT%","traceparent":"%REQ(TRACEPARENT)%","duration":"%DURATION%","method":"%REQ(:METHOD)%","path":"%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%","protocol":"%PROTOCOL%","referer":"%REQ(REFERER)%","request_id":"%REQ(X-REQUEST-ID)%","requested_server_name":"%REQUESTED_SERVER_NAME%","response_code":"%RESPONSE_CODE%","upstream_cluster":"%UPSTREAM_CLUSTER%","user_agent":"%REQ(USER-AGENT)%","x_forwarded_for":"%REQ(X-FORWARDED-FOR)%"}` |
| `envoygateway.gatewayServiceMonitor.enabled`                                      | Enable Prometheus ServiceMonitor for Envoy Gateway data plane (requires ontoserver.gateway.enabled and Prometheus Operator CRDs) | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.clientTrafficPolicy.enabled`                                        | Enable Envoy ClientTrafficPolicy (requires ontoserver.gateway.enabled)                                                           | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.clientTrafficPolicy.idleTimeout`                                    | HTTP idle timeout                                                                                                                | `300s`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `envoygateway.clientTrafficPolicy.proxyProtocol.enabled`                          | Enable PROXY protocol on the Envoy listener (required when upstream load balancer sends PROXY protocol headers, e.g. AWS NLB)    | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.clientTrafficPolicy.clientIPDetection.xForwardedFor.numTrustedHops` | Number of trusted XFF hops for client IP detection (0 = use direct peer/PROXY protocol address; omitted when null)               | `nil`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `envoygateway.backendTrafficPolicy.enabled`                                       | Enable Envoy BackendTrafficPolicy (requires ontoserver.gateway.enabled)                                                          | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.backendTrafficPolicy.requestBufferLimit`                            | Max request body size                                                                                                            | `1Gi`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `envoygateway.backendTrafficPolicy.rateLimit.requests`                            | Rate limit requests per unit                                                                                                     | `50`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `envoygateway.backendTrafficPolicy.rateLimit.unit`                                | Rate limit unit (Second, Minute, Hour)                                                                                           | `Second`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `envoygateway.backendTrafficPolicy.blockedUserAgents`                             | List of User-Agent patterns (regex) to throttle to 1 req/hour — use to block crawlers and bots (e.g. SemrushBot, AhrefsBot)     | `[]`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `envoygateway.securityPolicy.enabled`                                             | Enable Envoy SecurityPolicy (requires ontoserver.gateway.enabled)                                                                | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.securityPolicy.defaultAction`                                       | Default authorization action (Allow or Deny)                                                                                     | `Allow`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.securityPolicy.deniedCIDRs`                                         | List of CIDRs to deny                                                                                                            | `[]`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

### Traefik Ingress Controller

| Name                                                        | Description                                                                                                                 | Value           |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `traefik.ingressRoute.enabled`                              | Enable Traefik IngressRoute (use instead of ontoserver.ingress when Traefik is the ingress controller and backends use TLS) | `false`         |
| `traefik.ingressRoute.annotations`                          | IngressRoute annotations                                                                                                    | `{}`            |
| `traefik.ingressRoute.entryPoints`                          | Traefik entryPoints to bind (e.g. web, websecure)                                                                           | `["websecure"]` |
| `traefik.ingressRoute.backendPort`                          | Backend service port                                                                                                        | `80`            |
| `traefik.ingressRoute.backendScheme`                        | Backend scheme override — set to "https" when the backend service uses TLS                                                  | `""`            |
| `traefik.ingressRoute.backendServiceNameOverride`           | Override IngressRoute backend service name (e.g. to route through the Varnish service from ontoserver-extras)               | `""`            |
| `traefik.ingressRoute.serversTransport.enabled`             | Enable ServersTransport — required when the backend exposes HTTPS/TLS so Traefik can trust the backend certificate          | `false`         |
| `traefik.ingressRoute.serversTransport.insecureSkipVerify`  | Skip TLS certificate verification for the backend (use true for self-signed certificates)                                   | `false`         |
| `traefik.ingressRoute.serversTransport.rootCAsSecrets`      | List of Secret names containing root CA certificates used to verify the backend TLS certificate                             | `[]`            |
| `traefik.ingressRoute.serversTransport.certificatesSecrets` | List of Secret names containing client certificates for mutual TLS with the backend                                         | `[]`            |

### Nginx Ingress Controller

| Name                                           | Description                        | Value              |
| ---------------------------------------------- | ---------------------------------- | ------------------ |
| `nginx-ingress.enabled`                        | Enable F5 nginx-ingress-controller | `false`            |
| `nginx-ingress.controller.ingressClass.create` | Create a custom IngressClass       | `true`             |
| `nginx-ingress.controller.ingressClass.name`   | Name of the custom IngressClass    | `ontoserver-nginx` |
| `nginx-ingress.controller.ingressClassByName`  | Lookup IngressClasses by name      | `true`             |

Table generated with Readme Generator For Helm: [https://github.com/bitnami/readme-generator-for-helm](https://github.com/bitnami/readme-generator-for-helm)

---

Copyright &copy; 2026 Commonwealth Scientific and Industrial Research Organisation (CSIRO) ABN 41 687 119 230. All rights reserved.
