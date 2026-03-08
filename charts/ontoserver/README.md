# Ontoserver Helm Chart

This chart provides flexible deployment options for [Ontoserver](https://ontoserver.csiro.au/) — a FHIR terminology server — on Kubernetes. It supports single or scaled deployments, read-only or read-write modes, optional persistence, and networking via the Kubernetes Gateway API or standard Ingress (with an optional bundled [F5 Nginx Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/)). Optional features include a Postgres sidecar, Prometheus metrics, OpenTelemetry distributed tracing, Envoy Gateway traffic policies, and External Secrets integration.

> **Prerequisites:** Depending on which features you enable, the following cluster-level components may be required — install them separately if not already present:
>
> - **Kubernetes 1.29+** — required when `ontoserver.deployment.db.enabled: true` (the default). The Postgres sidecar uses the [native sidecar init container](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/) pattern (`restartPolicy: Always`), which is stable from K8s 1.29.
> - **[Envoy Gateway](https://gateway.envoyproxy.io/)** — required when `ontoserver.gateway.enabled: true` (Gateway API networking, and any Envoy traffic/security policies)
> - **[F5 Nginx Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/)** — required when `ontoserver.ingress.enabled: true` and you are **not** using the bundled `nginx-ingress` subchart (`nginx-ingress.enabled: false`)
> - **[External Secrets Operator](https://external-secrets.io/)** — required when `ontoserver.externalSecrets.enabled: true`

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

The **FHIR read-write test** (only runs when `ontoserver.deployment.isReadOnly=false`) loads a CodeSystem, ValueSet, and ConceptMap, then exercises `$lookup`, `$validate-code`, `$expand`, and `$translate` operations.

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
> kubectl logs -l job-name=my-ontoserver-ontoserver-test-fhir-rw
> ```

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
kubectl create secret docker-registry my-pull-secret \
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

## Persistence

Two persistence modes are available via `ontoserver.deployment.persistence.mode`:

- **`split`** (default) — separate PVCs for application files (`/var/onto`) and database files (`/var/lib/postgresql/data`).
- **`shared`** — a single PVC for both, with the database stored under a `db/` subPath.

For `Deployment` kind, persistence is disabled by default and opt-in via `persistence.enabledForDeployment: true`. For `StatefulSet`, PVCs are always created.

Each PVC can bind to an existing PersistentVolume (`existingVolume.enabled: true`) or provision a new one using a chart-managed `StorageClass` (`storageClass.provided.enabled: true`). The default provisioner and storage parameters are **AKS/Azure-specific** (`disk.csi.azure.com`, `Premium_LRS`). Replace `storageClass.provided.storageProvisioner` and `storageClass.provided.storageParameters` with values appropriate for your cloud provider (e.g. `ebs.csi.aws.com` on EKS).

When `storageClass.provided.enabled: false`, set `storageClass.name` to a specific StorageClass name, or leave it empty (`name: ""`) to omit `storageClassName` from the PVC spec and let Kubernetes use the cluster default StorageClass (e.g. `local-path` on k3d/k3s, `standard` on minikube, `gp2`/`gp3` on EKS).

### Pre-provisioned PersistentVolumes

When binding to a pre-provisioned disk (e.g. an existing Azure Disk or EBS volume), enable the chart-managed PV alongside `existingVolume`:

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
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v1.3.1/install.yaml
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

> **Note:** The GitHub Actions CI integration tests use a similar k3d setup (single agent, no load balancer, Traefik disabled) to run `helm install` followed by `helm test`. See [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) for details.

## Parameters

### Deployment

| Name                                                                                        | Description                                                                                                                                                                        | Value                             |
| ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `ontoserver.deployment.kind`                                                                | Kind of controller (Deployment or StatefulSet)                                                                                                                                     | `Deployment`                      |
| `ontoserver.deployment.type`                                                                | single|scaled deployment topology                                                                                                                                                  | `single`                          |
| `ontoserver.deployment.image`                                                               | Container image for OntoServer                                                                                                                                                     | `quay.io/aehrc/ontoserver:ctsa-6` |
| `ontoserver.deployment.imagePullPolicy`                                                     | Image pull policy                                                                                                                                                                  | `IfNotPresent`                    |
| `ontoserver.deployment.imagePullSecrets`                                                    | Additional pre-created image pull secrets to attach to the pod (merged with the chart-managed pull secret when imageCredentials are set)                                           | `[]`                              |
| `ontoserver.deployment.isReadOnly`                                                          | Ontoserver in read‑only mode - keep it true for scaled                                                                                                                             | `true`                            |
| `ontoserver.deployment.replicas`                                                            | Number of replicas - min 2 for scaled deployment - can be set to 0                                                                                                                 | `1`                               |
| `ontoserver.deployment.clusterName`                                                         | Cluster name for auto-discovery in scaled deployments (overrides the default "ontoserver" set in application.properties); ignored for single deployments                           | `""`                              |
| `ontoserver.deployment.annotations`                                                         | Deployment/Statefulset manifest annotations                                                                                                                                        | `{}`                              |
| `ontoserver.deployment.labels`                                                              | Deployment/Statefulset manifest labels                                                                                                                                             | `{}`                              |
| `ontoserver.deployment.podAnnotations`                                                      | Pod annotations                                                                                                                                                                    | `{}`                              |
| `ontoserver.deployment.podLabels`                                                           | Pod labels                                                                                                                                                                         | `{}`                              |
| `ontoserver.deployment.deploymentStrategy`                                                  | K8s update strategy when using Deployment Kind                                                                                                                                     | `RollingUpdate`                   |
| `ontoserver.deployment.startupProbe.initialDelaySeconds`                                    | Startup probe initial delay                                                                                                                                                        | `5`                               |
| `ontoserver.deployment.startupProbe.periodSeconds`                                          | Startup probe period                                                                                                                                                               | `2`                               |
| `ontoserver.deployment.startupProbe.failureThreshold`                                       | Startup probe failure threshold                                                                                                                                                    | `150`                             |
| `ontoserver.deployment.startupProbe.timeoutSeconds`                                         | Startup probe timeout                                                                                                                                                              | `5`                               |
| `ontoserver.deployment.livenessProbe.initialDelaySeconds`                                   | Liveness probe initial delay                                                                                                                                                       | `15`                              |
| `ontoserver.deployment.livenessProbe.periodSeconds`                                         | Liveness probe period                                                                                                                                                              | `5`                               |
| `ontoserver.deployment.livenessProbe.failureThreshold`                                      | Liveness probe failure threshold                                                                                                                                                   | `10`                              |
| `ontoserver.deployment.livenessProbe.timeoutSeconds`                                        | Liveness probe timeout                                                                                                                                                             | `5`                               |
| `ontoserver.deployment.readinessProbe.initialDelaySeconds`                                  | Readiness probe initial delay                                                                                                                                                      | `0`                               |
| `ontoserver.deployment.readinessProbe.periodSeconds`                                        | Readiness probe period                                                                                                                                                             | `5`                               |
| `ontoserver.deployment.readinessProbe.failureThreshold`                                     | Readiness probe failure threshold                                                                                                                                                  | `3`                               |
| `ontoserver.deployment.readinessProbe.timeoutSeconds`                                       | Readiness probe timeout                                                                                                                                                            | `5`                               |
| `ontoserver.deployment.persistence.enabledForDeployment`                                    | Enable PVC on Deployment                                                                                                                                                           | `false`                           |
| `ontoserver.deployment.persistence.mode`                                                    | shared | split - Use one or separate PV for db and lucene files                                                                                                                    | `split`                           |
| `ontoserver.deployment.persistence.files.accessMode`                                        | PVC access mode. Use ReadWriteMany (e.g. EFS on EKS) for scaled deployments.                                                                                                       | `ReadWriteOnce`                   |
| `ontoserver.deployment.persistence.files.existingVolume.enabled`                            | Bind to existing PV                                                                                                                                                                | `false`                           |
| `ontoserver.deployment.persistence.files.existingVolume.name`                               | Name of existing PV                                                                                                                                                                | `""`                              |
| `ontoserver.deployment.persistence.files.pv.enabled`                                        | Create a PersistentVolume for the files PVC backed by a pre-provisioned disk (requires existingVolume.enabled and existingVolume.name)                                             | `false`                           |
| `ontoserver.deployment.persistence.files.pv.diskURI`                                        | CSI volumeHandle — cloud-specific disk identifier (required when enabled, e.g. Azure disk resource ID or EBS volume ID)                                                            | `""`                              |
| `ontoserver.deployment.persistence.files.pv.csiDriver`                                      | CSI driver (required when enabled, e.g. disk.csi.azure.com or ebs.csi.aws.com)                                                                                                     | `""`                              |
| `ontoserver.deployment.persistence.files.pv.storageSize`                                    | Storage capacity                                                                                                                                                                   | `10Gi`                            |
| `ontoserver.deployment.persistence.files.pv.storageClassName`                               | StorageClass name (defaults to RELEASE-ontoserver-files)                                                                                                                           | `""`                              |
| `ontoserver.deployment.persistence.files.storageClass.name`                                 | StorageClass name to use when provided.enabled is false; leave empty to use the cluster default StorageClass                                                                       | `default`                         |
| `ontoserver.deployment.persistence.files.storageClass.provided.enabled`                     | Use provided storageClass                                                                                                                                                          | `true`                            |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageProvisioner`          | CSI driver - the default is AKS/Azure specific, replace for other clouds (e.g. ebs.csi.aws.com for EKS)                                                                            | `disk.csi.azure.com`              |
| `ontoserver.deployment.persistence.files.storageClass.provided.reclaimPolicy`               | Storage Reclaim Policy                                                                                                                                                             | `Retain`                          |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageParameters.skuName`   | Storage SKU name (AKS/Azure specific)                                                                                                                                              | `Premium_LRS`                     |
| `ontoserver.deployment.persistence.files.storageClass.provided.storageParameters.kind`      | Storage kind (AKS/Azure specific)                                                                                                                                                  | `Managed`                         |
| `ontoserver.deployment.persistence.files.storageClass.provided.allowVolumeExpansion`        | Allow volume expansion                                                                                                                                                             | `true`                            |
| `ontoserver.deployment.persistence.dbfiles.accessMode`                                      | PVC access mode. Use ReadWriteMany (e.g. EFS on EKS) for scaled deployments.                                                                                                       | `ReadWriteOnce`                   |
| `ontoserver.deployment.persistence.dbfiles.existingVolume.enabled`                          | Bind to existing PV                                                                                                                                                                | `false`                           |
| `ontoserver.deployment.persistence.dbfiles.existingVolume.name`                             | Name of existing PV                                                                                                                                                                | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.enabled`                                      | Create a PersistentVolume for the db-files PVC backed by a pre-provisioned disk (requires existingVolume.enabled and existingVolume.name; only used in split mode with db.enabled) | `false`                           |
| `ontoserver.deployment.persistence.dbfiles.pv.diskURI`                                      | CSI volumeHandle — cloud-specific disk identifier (required when enabled, e.g. Azure disk resource ID or EBS volume ID)                                                            | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.csiDriver`                                    | CSI driver (required when enabled, e.g. disk.csi.azure.com or ebs.csi.aws.com)                                                                                                     | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.pv.storageSize`                                  | Storage capacity                                                                                                                                                                   | `10Gi`                            |
| `ontoserver.deployment.persistence.dbfiles.pv.storageClassName`                             | StorageClass name (defaults to RELEASE-ontoserver-db-files)                                                                                                                        | `""`                              |
| `ontoserver.deployment.persistence.dbfiles.storageClass.name`                               | StorageClass name to use when provided.enabled is false; leave empty to use the cluster default StorageClass                                                                       | `default`                         |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.enabled`                   | Use provided storageClass                                                                                                                                                          | `true`                            |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageProvisioner`        | CSI driver - the default is AKS/Azure specific, replace for other clouds (e.g. ebs.csi.aws.com for EKS)                                                                            | `disk.csi.azure.com`              |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.reclaimPolicy`             | Storage Reclaim Policy                                                                                                                                                             | `Retain`                          |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageParameters.skuName` | Storage SKU name (AKS/Azure specific)                                                                                                                                              | `Premium_LRS`                     |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.storageParameters.kind`    | Storage kind (AKS/Azure specific)                                                                                                                                                  | `Managed`                         |
| `ontoserver.deployment.persistence.dbfiles.storageClass.provided.allowVolumeExpansion`      | Allow volume expansion                                                                                                                                                             | `true`                            |
| `ontoserver.deployment.podDisruptionBudget.enabled`                                         | Enable PDB for scaled deployments                                                                                                                                                  | `true`                            |
| `ontoserver.deployment.podDisruptionBudget.minAvailable`                                    | Minimum pods available - If you set this, maxUnavailable will be ignored                                                                                                           | `1`                               |
| `ontoserver.deployment.db.enabled`                                                          | Enable Postgres sidecar                                                                                                                                                            | `true`                            |
| `ontoserver.deployment.db.postgresVersion`                                                  | Version of Postgres                                                                                                                                                                | `16`                              |

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

| Name                                               | Description       | Value   |
| -------------------------------------------------- | ----------------- | ------- |
| `ontoserver.resources.ontoserver.requests.cpu`     | CPU request       | `2`     |
| `ontoserver.resources.ontoserver.requests.memory`  | Memory request    | `4G`    |
| `ontoserver.resources.ontoserver.requests.storage` | Storage request   | `10G`   |
| `ontoserver.resources.ontoserver.limits.cpu`       | CPU limit         | `2`     |
| `ontoserver.resources.ontoserver.limits.memory`    | Memory limit      | `4G`    |
| `ontoserver.resources.ontoserver.initialHeapSize`  | Java initial heap | `2800m` |
| `ontoserver.resources.ontoserver.maxHeapSize`      | Java max heap     | `2800m` |
| `ontoserver.resources.db.requests.cpu`             | DB CPU request    | `1`     |
| `ontoserver.resources.db.requests.memory`          | DB memory request | `1G`    |
| `ontoserver.resources.db.requests.storage`         | Storage request   | `10G`   |
| `ontoserver.resources.db.limits.cpu`               | DB CPU limit      | `1`     |
| `ontoserver.resources.db.limits.memory`            | DB memory limit   | `1G`    |

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

### Observability

| Name                                                         | Description                                                                                        | Value                                  |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `ontoserver.managementService.enabled`                       | Enable management service (exposes Spring Boot actuator on port 18080)                             | `false`                                |
| `ontoserver.metrics.serviceMonitor.enabled`                  | Enable Prometheus ServiceMonitor (requires managementService.enabled and Prometheus Operator CRDs) | `false`                                |
| `ontoserver.opentelemetry.instrumentation.enabled`           | Enable OpenTelemetry Java auto-instrumentation (requires OpenTelemetry Operator)                   | `false`                                |
| `ontoserver.opentelemetry.instrumentation.image`             | Auto-instrumentation agent image                                                                   | `otel/autoinstrumentation-java:latest` |
| `ontoserver.opentelemetry.instrumentation.serviceName`       | OTel service name (defaults to releaseName/releaseName-ontoserver)                                 | `""`                                   |
| `ontoserver.opentelemetry.instrumentation.propagators`       | Trace context propagators                                                                          | `tracecontext,baggage,b3multi`         |
| `ontoserver.opentelemetry.instrumentation.excludedClasses`   | Classes to exclude from instrumentation                                                            | `ca.uhn.fhir.*Interceptor*`            |
| `ontoserver.opentelemetry.instrumentation.exporter.type`     | Exporter type (zipkin, otlp, etc.)                                                                 | `zipkin`                               |
| `ontoserver.opentelemetry.instrumentation.exporter.endpoint` | Exporter endpoint URL (required when enabled)                                                      | `""`                                   |

### Miscellaneous

| Name                                    | Description                                                                                                                                         | Value   |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `ontoserver.tolerations`                | Pod tolerations                                                                                                                                     | `[]`    |
| `ontoserver.nodeSelector`               | Pod node selector (e.g. for EKS node group targeting)                                                                                               | `{}`    |
| `ontoserver.serviceAccount.create`      | Create a ServiceAccount for the pod (required for IRSA on EKS)                                                                                      | `false` |
| `ontoserver.serviceAccount.name`        | ServiceAccount name. When create: true defaults to <release>-ontoserver. When create: false and name is set, references an existing ServiceAccount. | `""`    |
| `ontoserver.serviceAccount.annotations` | ServiceAccount annotations (e.g. eks.amazonaws.com/role-arn for IRSA). Only used when create: true.                                                 | `{}`    |
| `ontoserver.customization`              | The name of a ConfigMap containing custom logo and CSS files to be deployed with the application                                                    | `""`    |
| `ontoserver.config.ONTOSERVER_INSECURE` | Disable TLS verification for outgoing connections                                                                                                   | `true`  |
| `ontoserver.secretConfig`               | Secret-backed Ontoserver config entries                                                                                                             | `{}`    |

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
| `envoygateway.securityPolicy.enabled`                                             | Enable Envoy SecurityPolicy (requires ontoserver.gateway.enabled)                                                                | `false`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.securityPolicy.defaultAction`                                       | Default authorization action (Allow or Deny)                                                                                     | `Allow`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `envoygateway.securityPolicy.deniedCIDRs`                                         | List of CIDRs to deny                                                                                                            | `[]`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

### Nginx Ingress Controller

| Name                                           | Description                        | Value              |
| ---------------------------------------------- | ---------------------------------- | ------------------ |
| `nginx-ingress.enabled`                        | Enable F5 nginx-ingress-controller | `false`            |
| `nginx-ingress.controller.ingressClass.create` | Create a custom IngressClass       | `true`             |
| `nginx-ingress.controller.ingressClass.name`   | Name of the custom IngressClass    | `ontoserver-nginx` |
| `nginx-ingress.controller.ingressClassByName`  | Lookup IngressClasses by name      | `true`             |

## Optional Feature Prerequisites

| Feature | Cluster Requirement |
| ------- | ------------------- |
| `ontoserver.metrics.serviceMonitor.enabled` | [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) CRDs installed |
| `ontoserver.opentelemetry.instrumentation.enabled` | [OpenTelemetry Operator](https://opentelemetry.io/docs/kubernetes/operator/) installed |
| `envoygateway.*` policies | [Envoy Gateway](https://gateway.envoyproxy.io/) CRDs installed |
| `envoygateway.gatewayServiceMonitor.enabled` | [Envoy Gateway](https://gateway.envoyproxy.io/) installed + [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) CRDs installed |
| `ontoserver.externalSecret.enabled` | [External Secrets Operator](https://external-secrets.io/) installed |

Table generated with Readme Generator For Helm: [https://github.com/bitnami/readme-generator-for-helm](https://github.com/bitnami/readme-generator-for-helm)


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

> **Gateway API is the recommended networking mode.** It is the configuration used by the chart developers and unlocks the full set of Envoy Gateway traffic policies (rate limiting, request buffering, CIDR deny rules). Unless you have a specific reason to use Ingress, prefer Gateway API.

By default neither is enabled — the chart deploys Ontoserver with no external access, suitable for internal use or testing. Enable one to expose the server:

* **Gateway API** (`ontoserver.gateway.enabled: true`) *(recommended)*: requires Gateway API CRDs and a compatible GatewayClass (e.g. [Envoy Gateway](https://gateway.envoyproxy.io/), [Traefik](https://doc.traefik.io/traefik/routing/providers/kubernetes-gateway/), [Cilium](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/), or any conformant implementation). Creates `Gateway`, `HTTPRoute`, and optionally a cert-manager `Issuer` resource. The default `className` is `envoy-gateway-class` — set `ontoserver.gateway.className` to match your GatewayClass. The default listener port is `443`; some implementations use a different port (e.g. Traefik defaults to `8443` — set `ontoserver.gateway.listenerPortSecure: 8443`). TLS termination is optional: set `ontoserver.tls.enabled: true` with a certificate reference, or enable cert-manager for automatic provisioning.
* **Ingress** (`ontoserver.ingress.enabled: true`): creates a standard `networking.k8s.io/v1` Ingress. Use the bundled F5 nginx-ingress subchart (`nginx-ingress.enabled: true`), the cluster's default controller (e.g. Traefik on k3d/k3s), or any other Ingress controller by setting `ontoserver.ingress.className` appropriately.

Gateway API and Ingress are mutually exclusive. Set `ontoserver.gateway.backendServiceNameOverride` to route traffic through an intermediate proxy (e.g. a Varnish cache) instead of the Ontoserver service directly.

**Common GatewayClass configuration reference:**

| Implementation | `gateway.className` | `gateway.listenerPortSecure` | Notes |
|---|---|---|---|
| [Envoy Gateway](https://gateway.envoyproxy.io/) *(default)* | `envoy-gateway-class` | `443` | Full Envoy policy support |
| [Traefik](https://doc.traefik.io/traefik/) v3.1+ | `traefik` | `8443` | Default k3d/k3s install |
| [Cilium](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/) | `cilium` | `443` | Requires Cilium CNI with Gateway API enabled |
| AWS Load Balancer Controller | `alb` | `443` | Envoy policies will not apply |

The Envoy Gateway traffic policies (`envoygateway.*`) are specific to Envoy Gateway and should remain disabled when using other implementations.

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
- **BackendTrafficPolicy** (`envoygateway.backendTrafficPolicy.enabled`) — caps the maximum upstream request body size and enforces a local rate limit (requests per time unit).
- **SecurityPolicy** (`envoygateway.securityPolicy.enabled`) — enforces IP-based authorization by denying traffic from a list of CIDRs.
- **Gateway ServiceMonitor** (`envoygateway.gatewayServiceMonitor.enabled`) — creates a Prometheus `ServiceMonitor` targeting the Envoy Gateway data-plane pods (scraping `/stats/prometheus` on the `metrics` port). Set `envoygateway.controlPlaneNamespace` to the namespace where Envoy Gateway is installed (default: `envoy-gateway-system`). Requires Prometheus Operator CRDs.

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

---

Copyright © 2025 Commonwealth Scientific and Industrial Research Organisation (CSIRO) ABN 41 687 119 230. All rights reserved.
