# ontoserver-indexer

A Helm chart that runs a one-shot Kubernetes Job to index a terminology code system and publish the result to an [Ontoserver](https://ontoserver.csiro.au) syndication server and/or write it to a PersistentVolumeClaim.

Supported code systems:

- **SNOMED CT** (any edition, via RF2 FULL or SNAPSHOT release packages)
- **LOINC** (via the LOINC distribution ZIP)

## Introduction

This chart wraps the Ontoserver `indexCodeSystemDebug` CLI tool. It retrieves one or more source files (via HTTPS or from a mounted volume), builds a Lucene index, and either pushes the packaged index as a syndication feed entry so that Ontoserver instances can pull it on startup or via the syndication API, or writes it directly to a PersistentVolumeClaim, or both.

The Job terminates after a single run. Helm's `ttlSecondsAfterFinished` removes it automatically. Re-indexing requires a fresh `helm install` (or `helm upgrade --install` with a unique release name).

## Registry Credentials

The default image (`quay.io/aehrc/ontoserver`) requires authentication. Pull credentials must be supplied via one of two methods:

**Inline credentials** — provide `image.credentials.username` and `image.credentials.password`; the chart creates a `kubernetes.io/dockerconfigjson` Secret automatically:
```yaml
image:
  credentials:
    registry: quay.io   # default
    username: my-quay-user
    password: my-quay-password   # use --set or External Secrets
```

**Pre-existing Secret** — if you have already created an `imagePullSecret`, reference it instead:
```yaml
image:
  imagePullSecrets:
    - name: my-pull-secret
```

Both can be combined — the chart-created secret is appended to the list.

## Prerequisites

- Kubernetes 1.21+
- Helm 3.2+
- quay.io credentials (or an existing imagePullSecret) — required to pull `quay.io/aehrc/ontoserver`
- Either a syndication server with a configured feed, or a PersistentVolumeClaim for local output (or both)
- Network access from the cluster to any HTTPS source file URLs and to the syndication server (if used)

## Installing the Chart

```bash
helm install snomed-au-index ./charts/ontoserver-indexer \
  -f charts/ontoserver-indexer/examples/snomed-au.yaml \
  --set auth.oauth2.secretRef=your-secret \
  --set image.credentials.username=your-quay-username \
  --set image.credentials.password=your-quay-password \
  --namespace indexing --create-namespace
```

See the [`examples/`](examples/) directory for example value files for SNOMED CT AU and LOINC.

## Code System Support

### SNOMED CT

Provide one or more RF2 ZIP URLs under `rf2.files`. Set `rf2.kind` to `FULL` (recommended for first-time indexing) or `SNAPSHOT`. The `codeSystem.version` must be the full SNOMED CT version URI, e.g. `http://snomed.info/sct/32506021000036107/version/20231130`.

Language display names are controlled by `languageRefsets.forModule` — a map of SNOMED CT module ID to comma-separated language refset IDs.

For editions where multiple SNOMED CT modules have different release dates, `resolveSkew` can be set to a reference edition date to align them.

### LOINC

Set `codeSystem.url` to `http://loinc.org` and `codeSystem.version` to the plain version number (e.g. `2.76`). Provide the LOINC distribution ZIP URL under `rf2.files`. `rf2.kind` is not required and will be ignored.

LOINC distributions require registration at [loinc.org](https://loinc.org/downloads/). Store the download URL in a pre-signed location accessible from within the cluster.

## Authentication

The chart supports OAuth2 client credentials and HTTP Basic authentication for the syndication server. Both modes can supply credentials either via an existing Secret or inline in values (the chart then creates a Secret).

Only one authentication method may be configured at a time. If neither is configured, requests to the syndication server are unauthenticated.

**OAuth2 — existing Secret:**
```yaml
auth:
  oauth2:
    secretRef: my-oauth-secret   # must have keys: clientId, clientSecret
```

**OAuth2 — inline (chart creates a Secret):**
```yaml
auth:
  oauth2:
    clientId: my-client-id
    clientSecret: my-client-secret
```

**Basic auth — existing Secret:**
```yaml
auth:
  basic:
    secretRef: my-basic-secret   # must have keys: username, password
```

## Security Labels

Syndication entries can carry Ontoserver permission labels that restrict access to users holding matching OAuth2 scopes. Labels follow the pattern `<category>.read` / `<category>.write` and use codes from `http://ontoserver.csiro.au/CodeSystem/ontoserver-permissions`. Resource-level security requires `ontoserver.security.enabled=fine` on the Ontoserver instance.

```yaml
syndication:
  securityLabels:
    - restricted.read
```

See the [Ontoserver security model](https://ontoserver.csiro.au/docs/6.24.1/security-model.html) for details.

## Source Files from a Volume

RF2 and LOINC distribution files can be read from a mounted volume instead of (or in addition to) HTTPS URLs. Set `input.pvcName` to the name of an existing PVC and use `file://` URIs in `rf2.files` that point into the mount path:

```yaml
input:
  pvcName: my-release-share   # PVC mounted read-only at /input
  mountPath: /input           # default; override if needed

rf2:
  files:
    - file:///input/SnomedCT_AU_20231130.zip
```

The PVC is mounted read-only. Any PVC accessible from the cluster works — Azure Files CSI, NFS, or a pre-populated ReadOnlyMany volume.

> **Note on `azureFile` inline volumes:** The in-tree `azureFile` Kubernetes volume type is deprecated as of Kubernetes 1.21 and removed in 1.26. Use the Azure Files CSI driver instead (`storageClassName: azurefile-csi`), which exposes the share as a PVC and is compatible with this chart.

## Local Output (PVC)

By default the chart publishes the index directly to a syndication server. For release pipelines that need the index archive as a file (e.g. to upload to Azure Files or an object store), use `output.path` and optionally `output.pvcName`.

When `output.pvcName` is set, the chart mounts the named PersistentVolumeClaim at `/output` inside the container. Set `output.path` to the desired destination within that mount. A syndication server is not required when `output.path` is provided — you can use one, both, or neither:

**PVC only (no syndication push):**
```yaml
output:
  pvcName: my-azure-fileshare   # existing PVC backed by Azure Files or similar
  path: /output/snomed-au-20231130.zip
```

**Both — write locally and push to syndication:**
```yaml
syndication:
  endpoint: https://your-syndication-server
  feed: snomed-au
  entryTitle: "SNOMED CT AU November 2023"

output:
  pvcName: my-azure-fileshare
  path: /output/snomed-au-20231130.zip
```

The PVC must be created before running the chart. Example for Azure Files:

```bash
kubectl create secret generic azure-files-secret \
  --from-literal=azurestorageaccountname=myaccount \
  --from-literal=azurestorageaccountkey=mykey

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-azure-fileshare
spec:
  accessModes: [ReadWriteMany]
  storageClassName: azurefile-csi
  resources:
    requests:
      storage: 10Gi
EOF
```

## Scheduling on Spot / Preemptible Nodes

Indexing jobs are CPU and memory intensive but tolerant of interruption (a failed Job can simply be re-run). Use `tolerations` to target Azure spot or other preemptible node pools:

```yaml
tolerations:
  - key: "kubernetes.azure.com/scalesetpriority"
    operator: "Equal"
    value: "spot"
    effect: "NoSchedule"
```

## Monitoring

After installing, the NOTES output prints the namespace-qualified commands to follow the Job:

```
kubectl logs -f job/<release-name> -n <namespace>
kubectl get job <release-name> -n <namespace>
```

## Parameters

### Image parameters

| Name                         | Description                                                                                                        | Value                      |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------ | -------------------------- |
| `image.repository`           | Container image repository for the Ontoserver indexer                                                              | `quay.io/aehrc/ontoserver` |
| `image.tag`                  | Container image tag                                                                                                | `ctsa-6`                   |
| `image.imagePullSecrets`     | List of pre-existing imagePullSecret names to attach to the pod                                                    | `[]`                       |
| `image.credentials.registry` | Registry hostname for the chart-managed pull secret                                                                | `quay.io`                  |
| `image.credentials.username` | Registry username; required to pull from quay.io/aehrc/ontoserver — chart creates an imagePullSecret automatically | `""`                       |
| `image.credentials.password` | Registry password; set via --set or populate via External Secrets                                                  | `""`                       |

### Job parameters

| Name                          | Description                                                             | Value  |
| ----------------------------- | ----------------------------------------------------------------------- | ------ |
| `job.name`                    | Override for the Kubernetes Job name; defaults to the Helm release name | `""`   |
| `job.activeDeadlineSeconds`   | Maximum duration in seconds before the Job is forcibly terminated       | `7200` |
| `job.ttlSecondsAfterFinished` | Seconds after Job completion before it is automatically deleted         | `3600` |

### Resources parameters

| Name                 | Description                                                                                           | Value |
| -------------------- | ----------------------------------------------------------------------------------------------------- | ----- |
| `resources.memoryGb` | Memory in gigabytes for the indexer pod; sets both the JVM -Xmx flag and the Kubernetes request/limit | `20`  |
| `resources.cpu`      | CPU units for the indexer pod; sets both the Kubernetes request and limit                             | `4`   |

### Code system parameters

| Name                 | Description                                                                                                                  | Value |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ----- |
| `codeSystem.url`     | FHIR CodeSystem URL to index (e.g. http://snomed.info/sct/32506021000036107 for SNOMED CT AU, or http://loinc.org for LOINC) | `""`  |
| `codeSystem.version` | Version URI of the code system (SNOMED CT: full version URI; LOINC: plain version number e.g. 2.76)                          | `""`  |

### RF2 source parameters

| Name        | Description                                                                                               | Value  |
| ----------- | --------------------------------------------------------------------------------------------------------- | ------ |
| `rf2.kind`  | RF2 release type for SNOMED CT — FULL or SNAPSHOT; ignored for LOINC                                      | `FULL` |
| `rf2.files` | List of source file URLs — HTTPS or file:// URIs — for RF2 ZIPs (SNOMED CT) or the LOINC distribution ZIP | `nil`  |

### Syndication parameters

| Name                         | Description                                                                                                  | Value |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------ | ----- |
| `syndication.endpoint`       | Base URL of the syndication server to publish the index to; required unless output.path is set               | `""`  |
| `syndication.tokenEndpoint`  | OAuth2 token endpoint URL for authenticating with the syndication server                                     | `""`  |
| `syndication.feed`           | Feed identifier on the syndication server; required when syndication.endpoint is set                         | `""`  |
| `syndication.entryTitle`     | Human-readable title of the entry created in the syndication feed; required when syndication.endpoint is set | `""`  |
| `syndication.entryFileName`  | Custom filename for the syndication entry archive; defaults to index-[version].zip if omitted                | `""`  |
| `syndication.securityLabels` | Ontoserver permission labels controlling read/write access to this entry (e.g. restricted.read)              | `[]`  |

### Output parameters

| Name             | Description                                                                                                                                          | Value |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| `output.pvcName` | Name of an existing PersistentVolumeClaim to mount at /output for writing the index archive locally                                                  | `""`  |
| `output.path`    | Container path for the -o flag to write the index archive locally (e.g. /output/snomed-au-20231130.zip); required unless syndication.endpoint is set | `""`  |

### Input parameters

| Name              | Description                                                                                                          | Value    |
| ----------------- | -------------------------------------------------------------------------------------------------------------------- | -------- |
| `input.pvcName`   | Name of an existing PersistentVolumeClaim containing source RF2 or LOINC files; mounted read-only at input.mountPath | `""`     |
| `input.mountPath` | Container path at which to mount the input PVC                                                                       | `/input` |

### Auth parameters

| Name                       | Description                                                                                | Value |
| -------------------------- | ------------------------------------------------------------------------------------------ | ----- |
| `auth.oauth2.secretRef`    | Name of an existing Secret with keys clientId and clientSecret for OAuth2 authentication   | `""`  |
| `auth.oauth2.clientId`     | OAuth2 client ID; chart creates a Secret — mutually exclusive with auth.oauth2.secretRef   | `""`  |
| `auth.oauth2.clientSecret` | OAuth2 client secret; required when auth.oauth2.clientId is set                            | `""`  |
| `auth.basic.secretRef`     | Name of an existing Secret with keys username and password for basic authentication        | `""`  |
| `auth.basic.username`      | Basic auth username; chart creates a Secret — mutually exclusive with auth.basic.secretRef | `""`  |
| `auth.basic.password`      | Basic auth password; required when auth.basic.username is set                              | `""`  |

### SNOMED CT language refsets

| Name                        | Description                                                                                       | Value |
| --------------------------- | ------------------------------------------------------------------------------------------------- | ----- |
| `languageRefsets.forModule` | Map of SNOMED CT module ID to comma-separated language refset IDs used for display name selection | `{}`  |

### Scheduling

| Name          | Description                                                                  | Value |
| ------------- | ---------------------------------------------------------------------------- | ----- |
| `tolerations` | Pod tolerations for scheduling on tainted nodes such as Azure spot instances | `[]`  |

### SNOMED CT advanced

| Name          | Description                                                                         | Value |
| ------------- | ----------------------------------------------------------------------------------- | ----- |
| `resolveSkew` | SNOMED CT edition date used to resolve skew between module versions (e.g. 20231130) | `""`  |

### Sentry parameters

| Name                 | Description                                                               | Value     |
| -------------------- | ------------------------------------------------------------------------- | --------- |
| `sentry.dsn`         | Sentry DSN for error reporting; leave empty to disable Sentry integration | `""`      |
| `sentry.environment` | Sentry environment tag attached to error reports                          | `Indexer` |
| `sentry.serverName`  | Sentry server name tag attached to error reports                          | `""`      |

<!-- Parameters section managed by Bitnami readme-generator-for-helm -->
