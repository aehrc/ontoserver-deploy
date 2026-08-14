# Ontoserver Helm Chart

This chart provides flexible deployment options for [Ontoserver](https://ontoserver.csiro.au/) — a FHIR terminology server — on Kubernetes. It supports single or scaled deployments, read-only or read-write modes, optional persistence, and networking via the Kubernetes Gateway API, standard Ingress, or Traefik IngressRoute. Optional features include a Postgres sidecar, Prometheus metrics, OpenTelemetry distributed tracing, Envoy Gateway traffic policies, and External Secrets integration.

> **Prerequisites:** Depending on which features you enable, the following cluster-level components may be required — install them separately if not already present:
>
> - **Kubernetes 1.29+** — required when `ontoserver.deployment.db.enabled: true` (the default). The Postgres sidecar uses the [native sidecar init container](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) pattern (`restartPolicy: Always`), which is stable from K8s 1.29.
> - **[Envoy Gateway](https://gateway.envoyproxy.io/)** — required when `ontoserver.gateway.enabled: true` (Gateway API networking, and any Envoy traffic/security policies)
> - **An Ingress controller** — required when `ontoserver.ingress.enabled: true`. The chart does not install one (the bundled `nginx-ingress` subchart was removed in 0.4.0); point `ontoserver.ingress.className` at a controller you already run.
> - **[Traefik](https://doc.traefik.io/traefik/)** with CRD support — required when `traefik.ingressRoute.enabled: true`
> - **[External Secrets Operator](https://external-secrets.io/) 0.16.0+** — required when `ontoserver.externalSecret.enabled: true`. The version floor is real: the chart uses `external-secrets.io/v1`, which does not exist before 0.16.0. See [External Secrets](#external-secrets).

## Table of Contents

- [Deployment Modes](#deployment-modes)
  - [Supported configurations](#supported-configurations)
  - [Unsupported configurations](#unsupported-configurations)
  - [Production recommendations](#production-recommendations)
- [Registry Credentials (Required)](#registry-credentials-required)
  - [Option A — chart-managed secret (recommended)](#option-a--chart-managed-secret-recommended)
  - [Option B — External Secrets](#option-b--external-secrets)
  - [Option C — pre-created secret](#option-c--pre-created-secret)
- [Configuration changes and pod restarts](#configuration-changes-and-pod-restarts)
- [Testing](#testing)
  - [Unit Tests](#unit-tests)
  - [Integration Tests](#integration-tests)
    - [Scaled StatefulSet integration test](#scaled-statefulset-integration-test)
    - [CI matrix](#ci-matrix)
- [Persistence](#persistence)
  - [Pre-provisioned PersistentVolumes](#pre-provisioned-persistentvolumes)
- [Update strategy](#update-strategy)
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
- [Release name length](#release-name-length)
- [Labels](#labels)
- [Security context](#security-context)
  - [What was verified](#what-was-verified)
  - [Hardened configuration](#hardened-configuration)
  - [What is not supported non-root](#what-is-not-supported-non-root)
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
| **`Deployment`** | One-replica Deployment | Multi-replica Deployment (read-only) |
| **`StatefulSet`** | One-replica StatefulSet (per-pod PVCs) | Multi-replica StatefulSet (per-pod PVCs, read-only) |

> ### ⚠️ Scaled deployments are read-only. Scaled read-write is not supported.
>
> This is not a chart limitation and there is no flag to override it. **Ontoserver forces read-only
> on any scaled deployment**: setting `ontoserver.deployment.scaled` makes the server reject writes
> regardless of what else is configured, so a scaled read-write server is not a topology that exists.
> The chart therefore refuses to render `type: scaled` with `isReadOnly: false` rather than deploy
> something that cannot work, and rejects any `ontoserver.config` or `ontoserver.secretConfig` entry
> that attempts to re-enable writes on a scaled deployment.
>
> Load content with a **single-instance read-write** deployment, then publish it to a syndication
> server and serve it from a **scaled read-only** cluster. See
> [Production recommendations](#production-recommendations).

**Constraints:**
- `scaled` requires `replicas` ≥ 2 (or 0 to scale to zero). `single` requires `replicas` < 2.
- `scaled` deployments cannot use the Postgres sidecar — an external database is required.
- `isReadOnly: true` is **required** for all scaled deployments — the chart refuses to render otherwise, and there is no opt-out. Ontoserver itself forces read-only whenever the deployment is scaled, so a scaled read-write server does not exist to configure. Each replica also maintains its own Lucene index on its own PVC, so content written through the round-robin Service is indexed only on the replica that served the write; requests that land on any other replica then fail. Integration tests confirm this on a scaled install: `ValueSet/$expand` and `CodeSystem/$validate-code` return HTTP 500 while the resources are present in the shared database and `$lookup` and `$translate` succeed. To ingest content, use a single-instance read-write deployment, then serve it scaled and read-only.
- `$closure` remains available in scaled read-only mode. It is a stateful operation, so it must always be routed to one specific pod — the chart provisions `<release>-ontoserver-pod0-service` for that and the `$closure` integration test verifies the routing.
- `clusterName` sets `ontoserver.cluster.name` for auto-discovery, allowing independent scaled clusters on the same network. Defaults to `ontoserver` (the application default) when unset.
- `StatefulSet` kind always provisions PVCs via `volumeClaimTemplates`. `Deployment` kind requires `persistence.enabledForDeployment: true` to use PVCs.
- The `PodDisruptionBudget` is rendered **only for `scaled`** deployments. A single instance owns its Lucene index on a ReadWriteOnce PVC and must be replaced rather than kept available during a disruption, so a PDB there would block node drains without protecting anything. Set exactly one of `minAvailable` or `maxUnavailable` — both accept a whole number or a percentage string (`"25%"`), and the chart fails if both or neither are set. `minAvailable: 1` is the default, so clear it (`minAvailable: null`) when you want `maxUnavailable`.
- `podManagementPolicy` (StatefulSet only) defaults to `Parallel`. See [StatefulSet rolling updates and `podManagementPolicy`](#statefulset-rolling-updates-and-podmanagementpolicy) — `Parallel` can leave a multi-replica install with no ready endpoint mid-update.

### StatefulSet rolling updates and `podManagementPolicy`

`ontoserver.deployment.podManagementPolicy` defaults to `Parallel`, which is what makes an initial scale-up fast: all replicas start at once rather than waiting for each pod's Lucene index preload in turn. The cost is that during a *rolling update* the controller also does not wait for a replacement pod to become Ready before replacing the next one. On a multi-replica install every pod can therefore be terminated within seconds of each other, and the Service is left with no ready endpoint until the first replacement passes its readiness probe — long enough with `healthCheckOption: -s` to return 503s to clients. A `PodDisruptionBudget` does not prevent this: a PDB only gates the Eviction API (node drains, `kubectl drain`), not StatefulSet-controller-driven pod replacement.

Set `podManagementPolicy: OrderedReady` to make the controller wait for each pod to be Ready before moving to the next, which keeps at least one ready endpoint throughout the update. The trade-off is that startup and scale-up are serialized too, so a cluster whose pods need a long index preload takes proportionally longer to come up.

```yaml
ontoserver:
  deployment:
    kind: StatefulSet
    type: scaled
    replicas: 3
    podManagementPolicy: OrderedReady
```

> **`podManagementPolicy` is immutable on an existing StatefulSet.** `helm upgrade` against a live release will fail with a field-is-immutable error. To adopt it on an already-deployed release, delete the StatefulSet while leaving the pods (and their PVCs) running, then upgrade so the chart recreates it:
>
> ```sh
> kubectl delete statefulset <release>-statefulset --cascade=orphan
> helm upgrade <release> ... --set ontoserver.deployment.podManagementPolicy=OrderedReady
> ```
>
> The orphaned pods keep serving traffic and are adopted by the recreated StatefulSet, which matches them by selector and ordinal name. Because only `podManagementPolicy` changes and the pod template does not, the adopted pods should be treated as current and left running — watch `kubectl get pods -w` through the upgrade to confirm. The first rolling update after this is the one that honours the new policy.

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
| *any* | `scaled` | *any* | *any* | **Read-write is not supported when scaled.** Hard rejected by the chart, and Ontoserver forces read-only on a scaled deployment regardless. There is no opt-in flag |
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

### Option B — External Secrets (chart-native)

Use the [External Secrets Operator](https://external-secrets.io/) to sync credentials from your secrets manager. Set the keys that locate your quay.io credentials in the store:

```yaml
ontoserver:
  externalSecret:
    secretStoreRef:
      name: my-cluster-secret-store   # your SecretStore or ClusterSecretStore
    imagePullSecret:
      data:
        username:
          key: quay-credentials    # secret path in your store
          property: username       # property within the secret (omit if the secret IS the value)
        password:
          key: quay-credentials
          property: password
```

The chart creates an `ExternalSecret` that syncs the credentials and produces a `kubernetes.io/dockerconfigjson` Secret, which is automatically added to `imagePullSecrets` on the pod.

To use a different store for the pull secret than for other external secrets, set `imagePullSecret.secretStoreRef.name` (and optionally `.kind`):

```yaml
ontoserver:
  externalSecret:
    imagePullSecret:
      secretStoreRef:
        name: another-store
        kind: SecretStore
      data:
        username:
          key: quay-credentials
          property: username
        password:
          key: quay-credentials
          property: password
```

Both `data.username.key` and `data.password.key` must be set together — setting only one is a validation error.

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

## Configuration changes and pod restarts

Ontoserver reads its configuration as environment variables, and a container resolves those
once at start. A `helm upgrade` that changes only a Secret therefore updates the Secret object
and leaves the pod template untouched — Kubernetes sees nothing to roll out, and the running
pods keep the old value indefinitely.

The chart closes that gap with checksum annotations on the pod template, so a configuration
change forces a rollout:

| Setting | Rolls pods on change | How |
|---|---|---|
| `ontoserver.config` | Yes | Rendered directly as env values in the pod template |
| `ontoserver.secretConfig` | Yes | `checksum/secret-config` annotation |
| `ontoserver.externalSecret.data` / `.dataFrom` / `.secretStoreRef` | Yes | `checksum/external-secret` annotation |
| `ontoserver.existingSecretConfig` (the Secret's contents) | **No** | Not owned or readable by this chart |
| Value rotated in the external store behind an ExternalSecret | **No** | External Secrets rewrites the target Secret; the chart sees no change |
| `ontoserver.imageCredentials` / `imagePullSecrets` | No, by design | Used only by the kubelet at image-pull time |
| `ontoserver.customization` (the ConfigMap's contents) | No | User-supplied ConfigMap, mounted as a volume |

For the cases marked **No**, restart explicitly after the change:

```bash
kubectl rollout restart statefulset/<release>-ontoserver   # or deployment/<release>-ontoserver
```

The checksums hash the *values*, not the rendered Secret manifest. Hashing the manifest — the
pattern shown in the Helm documentation — would fold in the `helm.sh/chart` label and so
restart every pod on any chart version bump, which is expensive here because Ontoserver
re-opens its Lucene index on start.

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

#### CI matrix

`.github/workflows/integration-tests.yml` runs the chart against a throwaway k3d cluster on
every push, in five modes:

| Mode | Covers |
|---|---|
| `read-only` | Metadata + FHIR read-only test hooks; write rejection |
| `read-write` | Metadata + FHIR read-write hooks; `$lookup`, `$expand`, `$validate-code`, `$translate`, `$closure` |
| `traefik-https-backend` | Traefik IngressRoute + ServersTransport to Ontoserver's own TLS listener |
| `gateway` | Gateway API: `Gateway`, `HTTPRoute` and all three Envoy Gateway traffic policies, end-to-end through Envoy |
| `scaled` | Scaled StatefulSet, external PostgreSQL, `$closure` pinned to pod-0 |

The `gateway` mode installs [Envoy Gateway](https://gateway.envoyproxy.io/) (pinned) — whose
release manifest also carries the upstream Gateway API CRDs — and asserts that the `Gateway`
reaches `Programmed=True`, that the `HTTPRoute` reaches both `Accepted=True` and
`ResolvedRefs=True`, and that the `ClientTrafficPolicy`, `BackendTrafficPolicy` and
`SecurityPolicy` are each accepted by the controller. Those conditions are the part unit tests
cannot reach: helm-unittest checks the rendered YAML, but only a real controller rejects a
listener whose protocol and `tls` block disagree, a `sectionName` that matches no listener, or a
`backendRefs` naming a Service that does not exist.

To reproduce it locally:

```bash
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.8.3/install.yaml
kubectl wait --for=condition=Available --timeout=5m -n envoy-gateway-system deployment/envoy-gateway

helm install ontoserver-gw ./charts/ontoserver \
  -f charts/ontoserver/tests/fixtures/gateway-values.yaml \
  --set ontoserver.imageCredentials.username=<quay-username> \
  --set ontoserver.imageCredentials.password=<quay-password> \
  --wait

kubectl wait --for=condition=Programmed gateway/ontoserver-gw-gw --timeout=5m
ENVOY_SVC=$(kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=ontoserver-gw-gw \
  -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n envoy-gateway-system "svc/$ENVOY_SVC" 18081:80 &
curl -s -H 'Host: ontoserver.gateway-test.local' http://localhost:18081/fhir/metadata
```

The fixture sets `ontoserver.gateway.allowPlaintext: true` because it uses an HTTP listener to
avoid needing cert-manager or a pre-created TLS Secret. Do not copy that into a real deployment
— see [Gateway API vs Ingress](#gateway-api-vs-ingress).

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

## Update strategy

For a `Deployment`, `ontoserver.deployment.deploymentStrategy` defaults to `RollingUpdate` — but the chart **substitutes `Recreate`** when persistence is enabled on a volume whose access mode is `ReadWriteOnce` or `ReadWriteOncePod`.

This is not a preference. `RollingUpdate` brings the replacement pod up *before* tearing the old one down, and a `ReadWriteOnce` disk can only be attached to one node at a time. If the replacement is scheduled onto a different node it waits indefinitely:

```
Warning  FailedAttachVolume  Multi-Attach error for volume "pvc-..."
         Volume is already used by pod(s) <old pod>
```

The old pod is never torn down, so the rollout never completes without manual intervention. This was reproduced on a live cluster, not inferred. It also **blocks PVC expansion** — a resize sits in `Resizing` until the volume detaches, then completes.

| Configuration | Effective strategy |
| --- | --- |
| No persistence | as requested (`RollingUpdate` by default) |
| Persistence, `ReadWriteOnce` / `ReadWriteOncePod` | **`Recreate`** |
| Persistence, `ReadWriteMany` (Azure Files, NFS) | as requested |
| `split` mode where *either* volume is exclusive | **`Recreate`** |
| `deployment.kind: StatefulSet` | unaffected — not a Deployment |

`ReadWriteMany` is excluded deliberately: it can be attached to several nodes at once, so it rolls without incident and those users keep zero-downtime upgrades. The sidecar's `dbfiles` access mode is only consulted when the sidecar is actually enabled, so an external-database deployment is not penalised for a value that has no effect.

The practical consequence of `Recreate` is a **brief outage on every upgrade** — the old pod is fully terminated before the new one starts. With a warm Lucene index, expect the startup probe's usual delay. Run a scaled `StatefulSet` if you need upgrades without downtime, since each replica then owns its own volume.

### Upgrading an existing release onto this behaviour

Kubernetes defaults `spec.strategy.rollingUpdate` on any Deployment created with `RollingUpdate`, and it refuses to hold that block alongside `type: Recreate`. Switching an existing release therefore has to remove the defaulted block in the same operation. How that goes depends on how you apply manifests — verified on a live cluster, per row:

| How you deploy | Switching to `Recreate` |
| --- | --- |
| `helm upgrade` | **works** — Helm's three-way merge removes the defaulted block |
| `kubectl apply` (client-side) | **works** |
| `kubectl apply --server-side` (some ArgoCD configurations) | **fails**: `spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy 'type' is 'Recreate'` |

If you hit the server-side apply failure, none of the obvious workarounds help: `--force-conflicts` still fails because this is validation rather than a field conflict, an explicit `rollingUpdate: null` in the manifest is dropped before it reaches the server, and removing the block on its own is immediately re-defaulted while the type is still `RollingUpdate`. What works is one atomic patch, after which server-side apply is clean:

```bash
kubectl patch deployment <release>-ontoserver-deployment -n <namespace> \
  --type=merge -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
```

Deleting the Deployment and letting it be recreated also works. The PVC is annotated `helm.sh/resource-policy: keep`, so the index survives either way.

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

An NGINX ingress controller installed separately also works on EKS and typically fronts itself with an NLB.

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

Option C — an NGINX controller you install yourself (works on any local cluster). The chart used to
bundle this as a subchart; that was removed in 0.4.0, so install the controller first:
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
  tls:
    enabled: false
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
>
> `serverPort` defaults to empty, which is correct for anything served on 80/443. Chart versions 0.4.0 and 0.4.1 shipped a default of `"8080"`, so installs on those versions that never set `serverPort` published `host:8080` in their CapabilityStatement and canonical URLs. Upgrading past 0.4.1 restores the empty default and the port disappears from those URLs — set `serverPort: "8080"` explicitly if you were relying on it.

See [`examples/k3d-traefik-values.yaml`](examples/k3d-traefik-values.yaml) for the complete quick-start values file and [`examples/local-values.yaml`](examples/local-values.yaml) for a general local cluster reference.

### Examples

Additional examples for specific infrastructure and GitOps workflows are available:

- [**Cloud & Networking Examples**](./examples/) — AKS, EKS, and local cluster values files (included in this chart).
- [**ArgoCD Manifests**](https://github.com/aehrc/ontoserver-deploy/tree/master/examples/argocd) — Ready-to-use Application and ApplicationSet manifests (GitHub).
- [**Kustomize Overrides**](https://github.com/aehrc/ontoserver-deploy/tree/master/examples/kustomize) — Advanced post-processing examples, such as adding a `priorityClassName` (GitHub).

See the [top-level examples directory](https://github.com/aehrc/ontoserver-deploy/tree/master/examples) for a complete overview.

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

## Release name length

**Keep the release name to 33 characters or fewer.** The chart validates this and fails at render time rather than part-way through an install.

Helm's own cap is 53 characters, which is not low enough. Every resource name is the release name plus a suffix, and Kubernetes limits differ by kind — each of the following was checked against a live API server rather than inferred:

| Name | Limit | Effective release-name budget |
| --- | --- | --- |
| `<release>-ontoserver-clustering-service` (Service) | **63** — Service names are DNS *labels* | **33** |
| `<release>-statefulset` (StatefulSet) | **63** | 51 |
| `<release>-ontoserver-deployment` (Deployment) | 253 — DNS subdomain | no practical limit |
| `<release>-ontoserver-files-<release>-statefulset-0` (PVC) | 253 — DNS subdomain | no practical limit |

The Service names are what bind. Note the PVC row in particular: it looks like the tightest case, because the release name appears in it *twice* — a 38-character release name produces a 108-character PVC name — but PVC names are DNS subdomains, and a 108-character one was created and bound without complaint.

Without the check, an over-long release name produces a **partially installed release**: Helm creates everything it can and the API server rejects one Service.

## Labels

Every resource the chart creates carries the standard Kubernetes labels:

| Label | Value |
| --- | --- |
| `app.kubernetes.io/name` | `ontoserver` (the chart name) |
| `app.kubernetes.io/instance` | the Helm release name |
| `app.kubernetes.io/managed-by` | `Helm` |
| `app.kubernetes.io/part-of` | `ontoserver` |
| `app.kubernetes.io/version` | the chart `appVersion` (the Ontoserver release, e.g. `ctsa-6`) |
| `helm.sh/chart` | `<chart name>-<chart version>` |

Some resources add `app.kubernetes.io/component` to distinguish their role — `clustering`, `headless`, `closure`, `management`, `metrics`, `gateway-metrics` or `test`.

Ontoserver pods and everything that selects them (Services, the PodDisruptionBudget) additionally carry the release-scoped label `app: <release>-ontoserver`. **That label is the workload selector and cannot change**: `.spec.selector` on a Deployment or StatefulSet is immutable, so altering it would break `helm upgrade` on an existing release. The standard labels above are metadata only and are deliberately kept out of every selector.

When selecting these resources from outside the chart (Kustomize patches, `kubectl -l`, network policies), prefer `app.kubernetes.io/name=ontoserver`, which does not vary with the release name. See [`examples/kustomize`](https://github.com/aehrc/ontoserver-deploy/tree/master/examples/kustomize) for a worked example.

Extra labels can be added via `ontoserver.deployment.labels` (on the workload) and `ontoserver.deployment.podLabels` (on the pods).

## Security context

By default the chart sets **no** `securityContext` at all, so pods run with whatever the image and the cluster's admission policy give them — which for `quay.io/aehrc/ontoserver` means **uid 0 (root)**. Hardening is opt-in through three values:

| Value | Applies to |
| --- | --- |
| `ontoserver.deployment.podSecurityContext` | the pod (`runAsUser`, `runAsNonRoot`, `fsGroup`, `seccompProfile`, …) |
| `ontoserver.deployment.containerSecurityContext` | the Ontoserver container |
| `ontoserver.deployment.db.containerSecurityContext` | the Postgres sidecar |
| `ontoserver.deployment.automountServiceAccountToken` | the pod — safe to set `false`; Ontoserver never calls the Kubernetes API (scaled clustering uses DNS) |
| `ontoserver.deployment.extraVolumes` / `extraVolumeMounts` | the pod and the Ontoserver container — needed to supply the writable `/tmp` that `readOnlyRootFilesystem` requires |

All default to unset, so **upgrading an existing release changes nothing** and rolls no pods. That is deliberate rather than timid: these charts have always run as root, and a default securityContext would break existing releases in ways the chart cannot detect — see the failures below, each of which is a hard crash at startup, not a warning.

### What was verified

The constraints below were established by running the images this chart ships (`quay.io/aehrc/ontoserver:ctsa-6` and `postgres:16`) under each candidate setting, not inferred from the manifests.

| Configuration | Result |
| --- | --- |
| root, as the chart ships today | healthy |
| uid 7531, no writable `/var/onto` | **crash** — `InvalidIndexFolderException: The folder /var/onto/lucene could not be created!` |
| uid 7531, writable `/var/onto` | healthy |
| uid 7531 + `readOnlyRootFilesystem` + writable `/tmp` | healthy |
| uid 7531 + `readOnlyRootFilesystem`, no writable `/tmp` | **crash** — `openFile(/tmp/spring.log) … Read-only file system` |
| uid 7531 + `ONTOSERVER_INSECURE: "false"` | **crash** — `keytool error: /keystore.p12 (Permission denied)` |
| Postgres sidecar as uid 999, owned data dir | ready |
| Postgres sidecar as uid 999, `fsGroup`-style data dir | **crash** — `FATAL: data directory … has wrong ownership` |

Useful facts that follow from this:

- The image contains a dedicated **`ontoserver` user, uid 7531** — it is clearly intended to be runnable as non-root, but the image does not default to it.
- `/var/onto` in the image is `root:root 0755`, so a non-root pod **must** get a writable `/var/onto` from somewhere. Enabling persistence plus `fsGroup` is the supported way.
- `/tmp` is **load-bearing**, not just a log destination. A running server was observed writing `spring.log`, `hsperfdata`, Tomcat's `docbase`/work directories and 16 `downlaod-*` scratch files there (the typo is upstream's). Any read-only-root configuration has to give it a real writable `/tmp`.

### Hardened configuration

Verified end to end against the images. A test (`tests/security_context_test.yaml`) renders exactly this fixture, so it cannot silently drift.

```yaml
ontoserver:
  deployment:
    podSecurityContext:
      runAsNonRoot: true
      runAsUser: 7531        # the `ontoserver` user present in the image
      runAsGroup: 7531
      fsGroup: 7531          # makes the files PVC writable by that user
      seccompProfile:
        type: RuntimeDefault
    containerSecurityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
    automountServiceAccountToken: false
    # Required by readOnlyRootFilesystem — see "What was verified" on why /tmp is load-bearing.
    extraVolumes:
      - name: tmp
        emptyDir: {}
    extraVolumeMounts:
      - name: tmp
        mountPath: /tmp
    db:
      enabled: false         # required — see below
    persistence:
      enabledForDeployment: true   # required — supplies a writable /var/onto
  config:
    ONTOSERVER_INSECURE: "true"    # required — see below
```

`readOnlyRootFilesystem` and the `/tmp` `emptyDir` are a **pair** — enabling the first without the second crashes the pod at startup. The test asserts both together so the recipe cannot ship half-applied.

### What is not supported non-root

Two combinations cannot be made to work with the chart as it stands. Each fails closed — the pod crashes at startup rather than running degraded — so you will find out immediately, but it is cheaper to read it here.

1. **The Postgres sidecar** (`ontoserver.deployment.db.enabled: true`) together with a non-root Ontoserver. The postgres entrypoint refuses to start unless it **owns** its data directory, and `fsGroup` only sets *group* ownership. Ontoserver needs uid 7531 to write `/var/onto` while Postgres needs uid 999 to own its data dir — and in the default `shared` persistence mode both live on the same volume. Use an [external database](#configuring-an-external-database), which production deployments need anyway.

   The sidecar's own `containerSecurityContext` is still useful for `allowPrivilegeEscalation: false` and dropping capabilities; it is just the non-root part that conflicts.

2. **Ontoserver's own HTTPS mode** (`ONTOSERVER_INSECURE: "false"`, see [Healthcheck and HTTPS mode](#healthcheck-and-https-mode-ontoserver_insecure-false)). `/run.sh` generates a self-signed keystore at `/keystore.p12` — in the root-owned `/` — so `keytool` fails with `Permission denied`. Terminate TLS at the ingress or gateway instead, which is the chart's default posture.

This configuration has been run on a cluster (AKS, Azure Disk `managed-csi` PVC, external PostgreSQL, Gatekeeper auditing), not only rendered. Confirmed there: the pod runs as `uid=7531`, `fsGroup` makes the volume group-writable (`/var/onto` becomes `root:7531 drwxrwsr-x`) and `/var/onto/lucene` is created owned by `ontoserver`; both `helm test` suites pass including the read-write one; and a full NCTS preload of SNOMED CT AU and LOINC installs and serves `$lookup`, ECL `$expand` and `$validate-code` normally.

`readOnlyRootFilesystem` was validated on a cluster in a second run: the pod reached Ready in ~50s with **0 restarts**, `touch /probe` inside the container fails with `Read-only file system`, `/fhir/metadata` and a `CodeSystem` search both return HTTP 200, and both `helm test` suites pass. That run also confirmed on a real cluster what the image probe showed — `/tmp` fills with `spring.log`, `hsperfdata`, Tomcat's work directories and a pile of `downlaod-*` scratch files, so the `emptyDir` is doing real work.

Against the AKS built-in policy set, the full recipe above — **including `readOnlyRootFilesystem`** — reports **zero** violations of `allowedUsersGroups`, `noPrivilegeEscalation` or `readOnlyRootFilesystem` for the namespace. Every pod in it satisfies all three: the Ontoserver pod (uid 7531), the chart's own `helm test` hooks (uid 100), the CloudNativePG Postgres it used as its external database (uid 26), and an OpenTelemetry Collector.

Two notes on reading a Gatekeeper result at all: the policies were in `dryrun` mode, so they audit without blocking, which is what makes the audit a *measurement* of hardening rather than a gate. And an audit is only meaningful if its `status.auditTimestamp` **post-dates the pod** — the first reading taken here predated it by 7 seconds and was discarded.

> **Still validate before rolling this out.** Two things remain unverified and are worth checking against your own deployment:
>
> - **An existing PVC with data on it.** Kubernetes relabels the volume it mounts, and a large pre-existing Lucene index can take a long time to `chown` — the validation above used a freshly provisioned, empty volume, so it says nothing about that delay.
> - **A mounted `ontoserver.customization` ConfigMap**, which was not part of the tested configuration.
>
> Also note that enabling persistence changes the Deployment update strategy — see [Update strategy](#update-strategy). That is unrelated to the security context, but you will meet it on the same upgrade.

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

* **Gateway API** (`ontoserver.gateway.enabled: true`) *(recommended)*: requires Gateway API CRDs and a compatible GatewayClass (e.g. [Envoy Gateway](https://gateway.envoyproxy.io/), [Traefik](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/), [Cilium](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/), or any conformant implementation). Creates `Gateway`, `HTTPRoute`, and optionally a cert-manager `Issuer` resource. The default `className` is `envoy-gateway-class` — set `ontoserver.gateway.className` to match your GatewayClass. The default listener port is `443`; some implementations use a different port (e.g. Traefik defaults to `8443` — set `ontoserver.gateway.listenerPortSecure: 8443`). Set `ontoserver.tls.enabled: true` with a certificate reference in `ontoserver.tls.certRef`, optionally adding `ontoserver.certmanager.enabled: true` to have cert-manager issue and populate that Secret automatically.

  TLS is required for the Gateway path unless you explicitly opt out. Gateway API rejects an HTTPS listener that carries no `certificateRefs`, so with `ontoserver.tls.enabled: false` the chart renders an **HTTP** listener on `ontoserver.gateway.listenerPortPlain` (default `80`) instead. Because that serves Ontoserver unencrypted, it must be requested deliberately via `ontoserver.gateway.allowPlaintext: true`; otherwise the chart fails to render with an explanatory error. Use it for local development, or where TLS is terminated upstream by a load balancer or service mesh — never on an internet-facing instance.
> **Upgrading from 0.3.x:** the bundled `nginx-ingress` subchart was removed in **0.4.0**. If your values file still has a `nginx-ingress:` block the chart will **fail to render** with instructions — deliberately, because the key would otherwise be accepted silently and `helm upgrade` would quietly stop deploying your ingress controller, taking the service offline with no error. Install a controller separately, point `ontoserver.ingress.className` at its IngressClass, and delete the block.

* **Ingress** (`ontoserver.ingress.enabled: true`) *(deprecated)*: creates a standard `networking.k8s.io/v1` Ingress. The chart does not install a controller — use the cluster's default (e.g. Traefik on k3d/k3s) or any controller you install yourself, and set `ontoserver.ingress.className` to match its IngressClass.
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

#### The literal `$` in the path, and percent-encoding

`$` is a legal URI path character, and the API server accepts it in an Ingress `path` under all three `pathType` values. Controllers differ in how they *match* it, though — tested against the two controllers this chart can drive, routing `/fhir/$closure` to a dedicated backend and everything else to a catchall:

| Client sends | F5 NGINX Ingress 2.1.0 | Traefik IngressRoute |
| --- | --- | --- |
| `/fhir/$closure` | dedicated backend ✅ | dedicated backend ✅ |
| `/fhir/%24closure` (percent-encoded) | dedicated backend ✅ | **catchall ❌** |

> **Traefik caveat.** Traefik matches `PathPrefix` against the *encoded* path, so `%24closure` does not match `` PathPrefix(`/fhir/$closure`) `` and falls through to the catchall rule — which load-balances across every pod and therefore breaks the stateful closure table. NGINX decodes before matching, so both forms work there.
>
> Percent-encoding `$` is unusual but legal, and some HTTP client libraries do it when building URLs. If your clients might, either have them send the literal `$`, or add a second Traefik rule matching `` PathPrefix(`/fhir/%24closure`) `` to the same backend. The failure is silent — requests succeed, and only the closure results are wrong.

**Not verified:** AWS ALB and Azure AGIC. Both translate Ingress paths into their own matching engines, and neither was available to test. If you use either, confirm `/fhir/$closure` reaches `RELEASE-ontoserver-pod0-service` before relying on `$closure` in a scaled deployment — the `helm test` closure suite exercises the Services directly and so passes even when the ingress path does not match.

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
- **BackendTrafficPolicy** (`envoygateway.backendTrafficPolicy.enabled`) — caps the maximum upstream request body size, enforces a local rate limit (requests per time unit), and optionally throttles specific bot user agents. Set `envoygateway.backendTrafficPolicy.rateLimitUserAgents` to a list of User-Agent substrings (matched as regular expressions) to rate-limit those clients to 1 request per hour — effectively blocking bots such as SemrushBot or AhrefsBot that generate large volumes of traffic:

  ```yaml
  envoygateway:
    backendTrafficPolicy:
      enabled: true
      rateLimitUserAgents:
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

> **Requires External Secrets Operator 0.16.0 or later.** The chart emits `apiVersion: external-secrets.io/v1`, which first appears in ESO **0.16.0** — where it is also the storage version. On 0.15.x and earlier the API does not exist and the resource is rejected outright (`no matches for kind "ExternalSecret" in version "external-secrets.io/v1"`). Verified against the CRD bundles for both releases. If you are pinned to an older ESO, manage the `ExternalSecret` outside the chart and use [`ontoserver.existingSecretConfig`](#parameters) to reference the Secret it produces.

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

| Name                                                                                        | Description                                                                                                                                                                                                                                                                                                                                                                            | Value                             |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `ontoserver.deployment.kind`                                                                | Kind of controller (Deployment or StatefulSet)                                                                                                                                                                                                                                                                                                                                         | `Deployment`                      |
| `ontoserver.deployment.type`                                                                | single|scaled deployment topology                                                                                                                                                                                                                                                                                                                                                      | `single`                          |
| `ontoserver.deployment.image`                                                               | Container image for OntoServer                                                                                                                                                                                                                                                                                                                                                         | `quay.io/aehrc/ontoserver:ctsa-6` |
| `ontoserver.deployment.imagePullPolicy`                                                     | Image pull policy                                                                                                                                                                                                                                                                                                                                                                      | `IfNotPresent`                    |
| `ontoserver.deployment.containerPort`                                                       | Container port Ontoserver listens on. Use 8080 for HTTP (ONTOSERVER_INSECURE=true) or 8443 for HTTPS (ONTOSERVER_INSECURE=false).                                                                                                                                                                                                                                                      | `8080`                            |
| `ontoserver.deployment.lifecycle`                                                           | Container lifecycle hooks (postStart / preStop). Passed through as-is to the container spec.                                                                                                                                                                                                                                                                                           | `{}`                              |
| `ontoserver.deployment.imagePullSecrets`                                                    | Additional pre-created image pull secrets to attach to the pod (merged with the chart-managed pull secret when imageCredentials are set)                                                                                                                                                                                                                                               | `[]`                              |
| `ontoserver.deployment.isReadOnly`                                                          | Ontoserver in read‑only mode. Must be true when type is scaled — Ontoserver forces read-only on a scaled deployment regardless of this setting.                                                                                                                                                                                                                                        | `true`                            |
| `ontoserver.deployment.replicas`                                                            | Number of replicas - min 2 for scaled deployment - can be set to 0                                                                                                                                                                                                                                                                                                                     | `1`                               |
| `ontoserver.deployment.podManagementPolicy`                                                 | StatefulSet pod management policy (Parallel or OrderedReady); ignored when kind is Deployment. Parallel starts and replaces pods without waiting for Ready, so a multi-replica rolling update can leave the Service with no ready endpoint; OrderedReady waits for each pod to become Ready first. Immutable on a live StatefulSet - see the README for the --cascade=orphan recreate. | `Parallel`                        |
| `ontoserver.deployment.clusterName`                                                         | Cluster name for auto-discovery in scaled deployments (overrides the default "ontoserver" set in application.properties); ignored for single deployments                                                                                                                                                                                                                               | `""`                              |
| `ontoserver.deployment.annotations`                                                         | Deployment/Statefulset manifest annotations                                                                                                                                                                                                                                                                                                                                            | `{}`                              |
| `ontoserver.deployment.labels`                                                              | Deployment/Statefulset manifest labels                                                                                                                                                                                                                                                                                                                                                 | `{}`                              |
| `ontoserver.deployment.podAnnotations`                                                      | Pod annotations                                                                                                                                                                                                                                                                                                                                                                        | `{}`                              |
| `ontoserver.deployment.podLabels`                                                           | Pod labels                                                                                                                                                                                                                                                                                                                                                                             | `{}`                              |
| `ontoserver.deployment.podSecurityContext`                                                  | Pod-level securityContext, passed through as-is (e.g. runAsNonRoot, runAsUser, fsGroup, seccompProfile)                                                                                                                                                                                                                                                                                | `{}`                              |
| `ontoserver.deployment.containerSecurityContext`                                            | Container-level securityContext for the Ontoserver container, passed through as-is (e.g. allowPrivilegeEscalation, capabilities, readOnlyRootFilesystem)                                                                                                                                                                                                                               | `{}`                              |
| `ontoserver.deployment.automountServiceAccountToken`                                        | Mount the ServiceAccount token into the pod. Ontoserver does not call the Kubernetes API — scaled clustering uses DNS, not the API — so false is safe. Leave unset (null) for the cluster default.                                                                                                                                                                                     | `nil`                             |
| `ontoserver.deployment.extraVolumes`                                                        | Extra pod volumes, e.g. `[{name: tmp, emptyDir: {}}]`                                                                                                                                                                                                                                                                                                                                  | `[]`                              |
| `ontoserver.deployment.extraVolumeMounts`                                                   | Extra mounts for the Ontoserver container, e.g. `[{name: tmp, mountPath: /tmp}]`                                                                                                                                                                                                                                                                                                       | `[]`                              |
| `ontoserver.deployment.deploymentStrategy`                                                  | K8s update strategy when using Deployment Kind. Forced to Recreate when a ReadWriteOnce volume is mounted.                                                                                                                                                                                                                                                                             | `RollingUpdate`                   |
| `ontoserver.deployment.startupProbe.initialDelaySeconds`                                    | Startup probe initial delay                                                                                                                                                                                                                                                                                                                                                            | `5`                               |
| `ontoserver.deployment.startupProbe.periodSeconds`                                          | Startup probe period                                                                                                                                                                                                                                                                                                                                                                   | `2`                               |
| `ontoserver.deployment.startupProbe.failureThreshold`                                       | Startup probe failure threshold                                                                                                                                                                                                                                                                                                                                                        | `150`                             |
| `ontoserver.deployment.startupProbe.timeoutSeconds`                                         | Startup probe timeout                                                                                                                                                                                                                                                                                                                                                                  | `5`                               |
| `ontoserver.deployment.livenessProbe.initialDelaySeconds`                                   | Liveness probe initial delay                                                                                                                                                                                                                                                                                                                                                           | `15`                              |
| `ontoserver.deployment.livenessProbe.periodSeconds`                                         | Liveness probe period                                                                                                                                                                                                                                                                                                                                                                  | `5`                               |
| `ontoserver.deployment.livenessProbe.failureThreshold`                                      | Liveness probe failure threshold                                                                                                                                                                                                                                                                                                                                                       | `10`                              |
| `ontoserver.deployment.livenessProbe.timeoutSeconds`                                        | Liveness probe timeout                                                                                                                                                                                                                                                                                                                                                                 | `5`                               |
| `ontoserver.deployment.readinessProbe.initialDelaySeconds`                                  | Readiness probe initial delay                                                                                                                                                                                                                                                                                                                                                          | `0`                               |
| `ontoserver.deployment.readinessProbe.periodSeconds`                                        | Readiness probe period                                                                                                                                                                                                                                                                                                                                                                 | `5`                               |
| `ontoserver.deployment.readinessProbe.failureThreshold`                                     | Readiness probe failure threshold                                                                                                                                                                                                                                                                                                                                                      | `3`                               |
| `ontoserver.deployment.readinessProbe.timeoutSeconds`                                       | Readiness probe timeout                                                                                                                                                                                                                                                                                                                                                                | `5`                               |
| `ontoserver.deployment.persistence.enabledForDeployment`                                    | Enable PVC on Deployment                                                                                                                                                                                                                                                                                                                                                               | `false`                           |
| `ontoserver.deployment.persistence.mode`                                                    | shared | split - Use one or separate PV for db and lucene files                                                                                                                                                                                                                                                                                                                        | `split`                           |
| `ontoserver.deployment.persistence.files.accessMode`                                        | PVC access mode. Use ReadWriteOnce for single instances and StatefulSet scaled deployments (each pod gets its own PVC via volumeClaimTemplates). Shared volumes across pods are not supported — Lucene indexes are pod-local.                                                                                                                                                          | `ReadWriteOnce`                   |
| `ontoserver.deployment.persistence.files.storageSize`                                       | Requested storage size for the Ontoserver files volume                                                                                                                                                                                                                                                                                                                                 | `10Gi`                            |
| `ontoserver.deployment.persistence.files.existingVolume.enabled`                            | Bind to existing PV (Deployment only; not supported for StatefulSet)                                                                                                                                                                                                                                                                                                                   | `false`                           |
| `ontoserver.deployment.persistence.files.existingVolume.name`                               | Name of existing PV                                                                                                                                                                                                                                                                                                                                                                    | `""`                              |
| `ontoserver.deployment.persistence.files.pv.enabled`                                        | Create a PersistentVolume for the files PVC backed by a pre-provisioned disk (requires existingVolume.enabled and existingVolume.name)                                                                                                                                                                                                                                                 | `false`                           |
| `ontoserver.deployment.persistence.files.pv.diskURI`                                        | CSI volumeHandle — cloud-specific disk identifier (required when enabled, e.g. Azure disk resource ID or EBS volume ID)                                                                                                                                                                                                                                                                | `""`                              |
| `ontoserver.deployment.persistence.files.pv.csiDriver`                                      | CSI driver (required when enabled, e.g. disk.csi.azure.com or ebs.csi.aws.com)                                                                                                                                                                                                                                                                                                         | `""`                              |
| `ontoserver.deployment.persistence.files.pv.storageClassName`                               | StorageClass name (defaults to RELEASE-ontoserver-files)                                                                                                                                                                                                                                                                                                                               | `""`                              |
| `ontoserver.deployment.persistence.files.storageClass.name`                                 | StorageClass name to use when provided.enabled is false; leave empty to use the cluster default StorageClass                                                                                                                                                                                                                                                                           | `default`                         |
| `ontoserver.deployment.persistence.files.storageClass.provided.enabled`                     | Use provided storageClass                                                                                                                                                                                                                                                                                                                                                              | `true`                            |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageProvisioner`          | CSI driver - the default is AKS/Azure specific, replace for other clouds (e.g. ebs.csi.aws.com for EKS)                                                                                                                                                                                                                                                                                | `disk.csi.azure.com`              |
| `ontoserver.deployment.persistence.files.storageClass.provided.reclaimPolicy`               | Storage Reclaim Policy                                                                                                                                                                                                                                                                                                                                                                 | `Retain`                          |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageParameters.skuName`   | Storage SKU name (AKS/Azure specific)                                                                                                                                                                                                                                                                                                                                                  | `Premium_LRS`                     |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageParameters.kind`      | Storage kind (AKS/Azure specific)                                                                                                                                                                                                                                                                                                                                                      | `Managed`                         |
| `ontoserver.deployment.persistence.files.storageClass.provided.allowVolumeExpansion`        | Allow volume expansion                                                                                                                                                                                                                                                                                                                                                                 | `true`                            |
| `ontoserver.deployment.persistence.dbfiles.accessMode`                                      | PVC access mode. Use ReadWriteOnce; only relevant for single-instance deployments with sidecar db (scaled deployments require external PostgreSQL and do not use dbfiles).                                                                                                                                                                                                             | `ReadWriteOnce`                   |
| `ontoserver.deployment.persistence.dbfiles.storageSize`                                     | Requested storage size for the database files volume                                                                                                                                                                                                                                                                                                                                   | `10Gi`                            |
| `ontoserver.deployment.persistence.dbfiles.existingVolume.enabled`                          | Bind to existing PV (Deployment only; not supported for StatefulSet)                                                                                                                                                                                                                                                                                                                   | `false`                           |
| `ontoserver.deployment.persistence.dbfiles.existingVolume.name`                             | Name of existing PV                                                                                                                                                                                                                                                                                                                                                                    | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.enabled`                                      | Create a PersistentVolume for the db-files PVC backed by a pre-provisioned disk (requires existingVolume.enabled and existingVolume.name; only used in split mode with db.enabled)                                                                                                                                                                                                     | `false`                           |
| `ontoserver.deployment.persistence.dbfiles.pv.diskURI`                                      | CSI volumeHandle — cloud-specific disk identifier (required when enabled, e.g. Azure disk resource ID or EBS volume ID)                                                                                                                                                                                                                                                                | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.csiDriver`                                    | CSI driver (required when enabled, e.g. disk.csi.azure.com or ebs.csi.aws.com)                                                                                                                                                                                                                                                                                                         | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.storageClassName`                             | StorageClass name (defaults to RELEASE-ontoserver-db-files)                                                                                                                                                                                                                                                                                                                            | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.storageClass.name`                               | StorageClass name to use when provided.enabled is false; leave empty to use the cluster default StorageClass                                                                                                                                                                                                                                                                           | `default`                         |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.enabled`                   | Use provided storageClass                                                                                                                                                                                                                                                                                                                                                              | `true`                            |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageProvisioner`        | CSI driver - the default is AKS/Azure specific, replace for other clouds (e.g. ebs.csi.aws.com for EKS)                                                                                                                                                                                                                                                                                | `disk.csi.azure.com`              |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.reclaimPolicy`             | Storage Reclaim Policy                                                                                                                                                                                                                                                                                                                                                                 | `Retain`                          |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageParameters.skuName` | Storage SKU name (AKS/Azure specific)                                                                                                                                                                                                                                                                                                                                                  | `Premium_LRS`                     |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageParameters.kind`    | Storage kind (AKS/Azure specific)                                                                                                                                                                                                                                                                                                                                                      | `Managed`                         |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.allowVolumeExpansion`      | Allow volume expansion                                                                                                                                                                                                                                                                                                                                                                 | `true`                            |
| `ontoserver.deployment.podDisruptionBudget.enabled`                                         | Enable PDB for scaled deployments                                                                                                                                                                                                                                                                                                                                                      | `true`                            |
| `ontoserver.deployment.podDisruptionBudget.minAvailable`                                    | Minimum pods that must stay available. Whole number (1) or percentage string ("50%"). Mutually exclusive with maxUnavailable — clear this one (minAvailable: null) to use that instead.                                                                                                                                                                                                | `1`                               |
| `ontoserver.deployment.podDisruptionBudget.maxUnavailable`                                  | Maximum pods that may be unavailable. Whole number (1) or percentage string ("25%"). Mutually exclusive with minAvailable, which is set by default.                                                                                                                                                                                                                                    | `""`                              |
| `ontoserver.deployment.podDisruptionBudget.unhealthyPodEvictionPolicy`                      | IfHealthyBudget or AlwaysAllow. Empty uses the cluster default (IfHealthyBudget).                                                                                                                                                                                                                                                                                                      | `""`                              |
| `ontoserver.deployment.db.enabled`                                                          | Enable Postgres sidecar                                                                                                                                                                                                                                                                                                                                                                | `true`                            |
| `ontoserver.deployment.db.postgresVersion`                                                  | Version of Postgres                                                                                                                                                                                                                                                                                                                                                                    | `16`                              |
| `ontoserver.deployment.db.containerSecurityContext`                                         | Container-level securityContext for the Postgres sidecar, passed through as-is. Kept separate from the Ontoserver container's because the two differ: the postgres image entrypoint requires uid 999 (it refuses to run as root) and initdb needs its data directory writable.                                                                                                         | `{}`                              |

### Registry Credentials

| Name                                   | Description                                                                            | Value     |
| -------------------------------------- | -------------------------------------------------------------------------------------- | --------- |
| `ontoserver.imageCredentials.registry` | Registry hostname (default quay.io)                                                    | `quay.io` |
| `ontoserver.imageCredentials.username` | quay.io username; when set with password the chart creates a pull secret automatically | `""`      |
| `ontoserver.imageCredentials.password` | quay.io password; set via --set or populate via External Secrets                       | `""`      |

### Server

| Name                    | Description                                                                                                                         | Value           |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `ontoserver.serverName` | Server hostname - must match a hostName at ontoserver.hostNames                                                                     | `localhost`     |
| `ontoserver.serverPort` | Non-standard port exposed to clients (e.g. 8080 when port-forwarding or k3d maps 8080:80). Leave empty for standard ports (80/443). | `""`            |
| `ontoserver.hostNames`  | Hostnames for ingress/gateway                                                                                                       | `["localhost"]` |
| `ontoserver.timeZone`   | Server time zone                                                                                                                    | `UTC`           |
| `ontoserver.language`   | Locale/language                                                                                                                     | `en_US`         |

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
| `ontoserver.gateway.listenerPortPlain`          | Plaintext listener port, used only when tls.enabled is false and allowPlaintext is true                                                                                                                                                                            | `80`                  |
| `ontoserver.gateway.allowPlaintext`             | Permit a plaintext HTTP listener when tls.enabled is false. Off by default so a public Gateway cannot be left unencrypted by accident; enable for local development or when TLS terminates upstream                                                                | `false`               |
| `ontoserver.gateway.annotations`                | Gateway annotations                                                                                                                                                                                                                                                | `{}`                  |
| `ontoserver.gateway.infrastructureAnnotations`  | Infrastructure annotations                                                                                                                                                                                                                                         | `{}`                  |
| `ontoserver.gateway.className`                  | GatewayClass name                                                                                                                                                                                                                                                  | `envoy-gateway-class` |
| `ontoserver.gateway.requestTimeout`             | Request timeout duration                                                                                                                                                                                                                                           | `120s`                |
| `ontoserver.gateway.closureRequestTimeout`      | Request timeout for the $closure route. Empty means use requestTimeout.                                                                                                                                                                                            | `300s`                |
| `ontoserver.gateway.backendServiceNameOverride` | Override HTTPRoute backend service name (e.g. for varnish proxy)                                                                                                                                                                                                   | `""`                  |
| `ontoserver.ingress.enabled`                    | Enable Ingress                                                                                                                                                                                                                                                     | `false`               |
| `ontoserver.ingress.annotations`                | Ingress annotations                                                                                                                                                                                                                                                | `{}`                  |
| `ontoserver.ingress.className`                  | IngressClass name                                                                                                                                                                                                                                                  | `ontoserver-nginx`    |
| `ontoserver.ingress.backendServiceNameOverride` | Override Ingress backend service name (e.g. to route through the Varnish service from ontoserver-extras)                                                                                                                                                           | `""`                  |

### Observability

| Name                                                         | Description                                                                                                                                                   | Value                                  |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `ontoserver.managementService.enabled`                       | Enable management service (exposes Spring Boot actuator on port 18080)                                                                                        | `false`                                |
| `ontoserver.metrics.serviceMonitor.enabled`                  | Enable Prometheus ServiceMonitor (requires managementService.enabled and Prometheus Operator CRDs)                                                            | `false`                                |
| `ontoserver.metrics.serviceMonitor.labels`                   | Extra labels for Prometheus's serviceMonitorSelector to match                                                                                                 | `{}`                                   |
| `ontoserver.metrics.serviceMonitor.interval`                 | Scrape interval. Empty uses the Prometheus global default.                                                                                                    | `""`                                   |
| `ontoserver.metrics.serviceMonitor.scrapeTimeout`            | Scrape timeout. Must be less than interval. Empty uses the Prometheus default.                                                                                | `""`                                   |
| `ontoserver.metrics.serviceMonitor.namespaceSelector`        | Namespaces to search for the management Service. Empty means the release namespace only, which is correct unless Prometheus restricts discovery by namespace. | `[]`                                   |
| `ontoserver.tests.ttlSecondsAfterFinished`                   | Time to retain Helm test Jobs after completion so logs remain available                                                                                       | `1800`                                 |
| `ontoserver.opentelemetry.instrumentation.enabled`           | Enable OpenTelemetry Java auto-instrumentation (requires OpenTelemetry Operator)                                                                              | `false`                                |
| `ontoserver.opentelemetry.instrumentation.image`             | Auto-instrumentation agent image                                                                                                                              | `otel/autoinstrumentation-java:latest` |
| `ontoserver.opentelemetry.instrumentation.serviceName`       | OTel service name (defaults to releaseName/releaseName-ontoserver)                                                                                            | `""`                                   |
| `ontoserver.opentelemetry.instrumentation.propagators`       | Trace context propagators                                                                                                                                     | `tracecontext,baggage,b3multi`         |
| `ontoserver.opentelemetry.instrumentation.excludedClasses`   | Classes to exclude from instrumentation                                                                                                                       | `ca.uhn.fhir.*Interceptor*`            |
| `ontoserver.opentelemetry.instrumentation.metricsExporter`   | OTEL_METRICS_EXPORTER for the Java agent (e.g. otlp for JVM heap and GC metrics, or none to disable)                                                          | `none`                                 |
| `ontoserver.opentelemetry.instrumentation.logsExporter`      | OTEL_LOGS_EXPORTER for the Java agent (e.g. otlp, or none to disable)                                                                                         | `none`                                 |
| `ontoserver.opentelemetry.instrumentation.exporter.type`     | Trace exporter type (OTEL_TRACES_EXPORTER - zipkin, otlp, etc.)                                                                                               | `zipkin`                               |
| `ontoserver.opentelemetry.instrumentation.exporter.endpoint` | Exporter endpoint URL (required when enabled)                                                                                                                 | `""`                                   |

### Miscellaneous

| Name                                    | Description                                                                                                                                                                                       | Value   |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `ontoserver.tolerations`                | Pod tolerations                                                                                                                                                                                   | `[]`    |
| `ontoserver.nodeSelector`               | Pod node selector (e.g. for EKS node group targeting)                                                                                                                                             | `{}`    |
| `ontoserver.serviceAccount.create`      | Create a ServiceAccount for the pod (required for IRSA on EKS)                                                                                                                                    | `false` |
| `ontoserver.serviceAccount.name`        | ServiceAccount name. When create: true defaults to <release>-ontoserver. When create: false and name is set, references an existing ServiceAccount.                                               | `""`    |
| `ontoserver.serviceAccount.annotations` | ServiceAccount annotations (e.g. eks.amazonaws.com/role-arn for IRSA). Only used when create: true.                                                                                               | `{}`    |
| `ontoserver.customization`              | The name of a ConfigMap containing custom logo and CSS files to be deployed with the application                                                                                                  | `""`    |
| `ontoserver.config.ONTOSERVER_INSECURE` | Disable Ontoserver's inbound TLS listener — set to "true" to serve plain HTTP, "false" (or omit) to serve HTTPS using the bundled self-signed keystore                                            | `true`  |
| `ontoserver.secretConfig`               | Secret-backed Ontoserver config entries — chart creates a Secret from these key/value pairs                                                                                                       | `{}`    |
| `ontoserver.existingSecretConfig`       | Name of a pre-existing Secret whose keys are injected as environment variables — use this instead of secretConfig when managing secrets outside the chart (e.g. ArgoCD + kubectl, Sealed Secrets) | `""`    |

### External Secrets

| Name                                            | Description                                                         | Value                |
| ----------------------------------------------- | ------------------------------------------------------------------- | -------------------- |
| `ontoserver.externalSecret.enabled`             | Enable ExternalSecret resource (requires External Secrets Operator) | `false`              |
| `ontoserver.externalSecret.refreshInterval`     | How often the external secret is synced                             | `1h`                 |
| `ontoserver.externalSecret.secretStoreRef.name` | Name of the SecretStore or ClusterSecretStore                       | `""`                 |
| `ontoserver.externalSecret.secretStoreRef.kind` | Kind of the secret store (SecretStore or ClusterSecretStore)        | `ClusterSecretStore` |
| `ontoserver.externalSecret.data`                | List of individual secret key mappings                              | `[]`                 |
| `ontoserver.externalSecret.dataFrom`            | Bulk secret mappings (extract entire secrets as env vars)           | `[]`                 |

### External Secrets — Image Pull Secret

| Name                                                               | Description                                                                                              | Value      |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ---------- |
| `ontoserver.externalSecret.imagePullSecret.secretStoreRef.name`    | Override secret store name for pull secret (falls back to ontoserver.externalSecret.secretStoreRef.name) | `""`       |
| `ontoserver.externalSecret.imagePullSecret.secretStoreRef.kind`    | Override secret store kind (falls back to ontoserver.externalSecret.secretStoreRef.kind)                 | `""`       |
| `ontoserver.externalSecret.imagePullSecret.data.username.key`      | Secret store path containing the quay.io username                                                        | `""`       |
| `ontoserver.externalSecret.imagePullSecret.data.username.property` | Property within the secret (for stores with multiple fields per key)                                     | `username` |
| `ontoserver.externalSecret.imagePullSecret.data.password.key`      | Secret store path containing the quay.io password                                                        | `""`       |
| `ontoserver.externalSecret.imagePullSecret.data.password.property` | Property within the secret                                                                               | `password` |

### Envoy Gateway

| Name                                                                              | Description                                                                                                                          | Value                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `envoygateway.controlPlaneNamespace`                                              | Namespace where Envoy Gateway control plane is installed                                                                             | `envoy-gateway-system`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `envoygateway.createGatewayClass`                                                 | Create and manage a GatewayClass and EnvoyProxy resource for this release (requires ontoserver.gateway.enabled)                      | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.envoyProxy.name`                                                    | Name of the EnvoyProxy resource                                                                                                      | `default`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `envoygateway.envoyProxy.replicas`                                                | Number of Envoy proxy pod replicas                                                                                                   | `2`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `envoygateway.envoyProxy.pdbMinAvailable`                                         | Minimum available pods for the EnvoyProxy PodDisruptionBudget                                                                        | `1`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `envoygateway.envoyProxy.accessLog.enabled`                                       | Enable structured JSON access logging to stdout                                                                                      | `true`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `envoygateway.envoyProxy.accessLog.format`                                        | Envoy access log format string (single-line JSON template)                                                                           | `{"timestamp":"%START_TIME%","authority":"%REQ(:AUTHORITY)%","bytes_received":"%BYTES_RECEIVED%","bytes_sent":"%BYTES_SENT%","traceparent":"%REQ(TRACEPARENT)%","duration":"%DURATION%","method":"%REQ(:METHOD)%","path":"%REQ(X-ENVOY-ORIGINAL-PATH?:PATH)%","protocol":"%PROTOCOL%","referer":"%REQ(REFERER)%","request_id":"%REQ(X-REQUEST-ID)%","requested_server_name":"%REQUESTED_SERVER_NAME%","response_code":"%RESPONSE_CODE%","upstream_cluster":"%UPSTREAM_CLUSTER%","user_agent":"%REQ(USER-AGENT)%","x_forwarded_for":"%REQ(X-FORWARDED-FOR)%"}` |
| `envoygateway.gatewayServiceMonitor.enabled`                                      | Enable Prometheus ServiceMonitor for Envoy Gateway data plane (requires ontoserver.gateway.enabled and Prometheus Operator CRDs)     | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.clientTrafficPolicy.enabled`                                        | Enable Envoy ClientTrafficPolicy (requires ontoserver.gateway.enabled)                                                               | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.clientTrafficPolicy.idleTimeout`                                    | HTTP idle timeout                                                                                                                    | `300s`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `envoygateway.clientTrafficPolicy.proxyProtocol.enabled`                          | Enable PROXY protocol on the Envoy listener (required when upstream load balancer sends PROXY protocol headers, e.g. AWS NLB)        | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.clientTrafficPolicy.clientIPDetection.xForwardedFor.numTrustedHops` | Number of trusted XFF hops for client IP detection (0 = use direct peer/PROXY protocol address; omitted when null)                   | `nil`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `envoygateway.backendTrafficPolicy.enabled`                                       | Enable Envoy BackendTrafficPolicy (requires ontoserver.gateway.enabled)                                                              | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.backendTrafficPolicy.requestBufferLimit`                            | Max request body size                                                                                                                | `1Gi`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `envoygateway.backendTrafficPolicy.rateLimit.requests`                            | Rate limit requests per unit                                                                                                         | `50`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `envoygateway.backendTrafficPolicy.rateLimit.unit`                                | Rate limit unit (Second, Minute, Hour)                                                                                               | `Second`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `envoygateway.backendTrafficPolicy.rateLimitUserAgents`                           | List of User-Agent substrings to rate-limit aggressively (1 req/hour). Matched as regular expressions against the User-Agent header. | `[]`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `envoygateway.securityPolicy.enabled`                                             | Enable Envoy SecurityPolicy (requires ontoserver.gateway.enabled)                                                                    | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.securityPolicy.defaultAction`                                       | Default authorization action (Allow or Deny)                                                                                         | `Allow`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.securityPolicy.deniedCIDRs`                                         | List of CIDRs to deny                                                                                                                | `[]`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

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

