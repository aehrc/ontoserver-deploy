# Traefik HTTPS Backend Integration Test — Design Spec

**Date:** 2026-03-16
**Status:** Approved

## Background

A real-world deployment (HKM DEV, EKS + Traefik + ALB) surfaced a key difference between Traefik and NGINX: Traefik does **not** connect to HTTPS backends with self-signed certificates by default. A `ServersTransport` resource must explicitly configure TLS trust. The `traefik-ingressroute.yaml` and `traefik-serverstransport.yaml` templates added in commit `7e81fde` address this. This spec describes an integration test that validates those templates end-to-end.

## Goal

Add a CI integration test that proves Traefik can successfully proxy requests to an Ontoserver backend that serves HTTPS with its built-in self-signed certificate, using a `ServersTransport` with `insecureSkipVerify: true`.

## Scope

- **In scope:** Extending `.github/workflows/integration-tests.yml` with a `traefik-https-backend` matrix entry; a new fixture values file.
- **Out of scope:** Testing `rootCAsSecrets`, mutual TLS, TLS termination at the ingress (IngressRoute `spec.tls`), or changes to the Traefik templates themselves.

## Design

### 1. Matrix parameterization

Three new boolean fields are added to the matrix schema alongside the existing fields. Existing entries retain their current behaviour unchanged.

| Field | read-only | read-write | traefik-https-backend |
|---|---|---|---|
| `name` | `read-only` | `read-write` | `traefik-https-backend` |
| `release` | `ontoserver-ro` | `ontoserver-rw` | `ontoserver-traefik` |
| `isReadOnly` | `"true"` | `"false"` | `"true"` |
| `expectedHook` | `ontoserver-ro-ontoserver-test-fhir-ro` | `ontoserver-rw-ontoserver-test-fhir-rw` | `""` |
| `unexpectedHook` | `ontoserver-ro-ontoserver-test-fhir-rw` | `ontoserver-rw-ontoserver-test-fhir-ro` | `""` |
| `runHelmTest` | `true` | `true` | `false` |
| `verifyTraefikRoute` | `false` | `false` | `true` |

**Important:** `runHelmTest` and `verifyTraefikRoute` must be explicitly set on **all three** matrix entries. In GitHub Actions, a matrix field absent from an entry evaluates to `""` (falsy), so omitting these fields from the existing `read-only` and `read-write` entries would silently skip their `helm test` steps and break the existing test suite.

### 2. k3d cluster and Traefik v3 installation

The k3d creation step is **unchanged** — `--disable=traefik@server:0` remains for all matrix entries. The bundled k3s Traefik is always disabled.

**Why not use the k3s-bundled Traefik:** k3s ships Traefik v2, which uses `traefik.containo.us/v1alpha1`. The chart templates use `traefik.io/v1alpha1` (Traefik v3). Applying the chart against Traefik v2 CRDs would fail with `no matches for kind "IngressRoute" in version "traefik.io/v1alpha1"`.

**Preferred resolution:** A dedicated "Install Traefik v3" step runs after cluster creation, conditional on `matrix.mode.verifyTraefikRoute`:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik \
  --namespace kube-system \
  --version <pin to a stable Traefik v3 chart version, e.g. 30.0.0 — verify latest stable at implementation time> \
  --set ports.web.expose.default=true \
  --set ports.web.exposedPort=80 \
  --wait --timeout 2m
```

**No `allowCrossNamespace` flag needed.** The chart deploys both the IngressRoute and the ServersTransport into the same Helm release namespace (default: `default`). The `serversTransport:` field in the IngressRoute template is an unqualified name string, which Traefik resolves relative to the IngressRoute's own namespace. Since both resources land in the same namespace, this is a same-namespace reference. Traefik installed in `kube-system` watching resources in `default` is standard behaviour that does not require cross-namespace resolution. The `allowCrossNamespace` flag would only be needed if the IngressRoute in one namespace referenced a ServersTransport in a different namespace — which this test does not do.

**Version pinning:** Use a concrete chart version string (e.g. `30.0.0`). An unpinned version would silently upgrade on each CI run, risking undetected breaking changes. The pinned version should be recorded in the workflow file and updated intentionally.

### 3. Fixture values file

New file: `charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml`

```yaml
ontoserver:
  hostNames:
    - ontoserver.traefik-test.local
  serverName: ontoserver.traefik-test.local
  config:
    # ONTOSERVER_INSECURE=true makes Ontoserver serve plain HTTP (disables its inbound TLS
    # listener). The chart default is "true" for convenience in cluster-internal deployments.
    # Setting to "false" restores Ontoserver's out-of-box behaviour: HTTPS on port 8080
    # using its bundled self-signed keystore at /keystore.p12.
    #
    # Note: values.yaml documents this flag as "Disable TLS verification for outgoing
    # connections", which is incomplete. Per Ontoserver documentation: "By default,
    # Ontoserver will run using SSL/TLS. To disable SSL/TLS, add ONTOSERVER_INSECURE=true."
    # The flag controls the server's inbound TLS listener; the values.yaml comment should
    # be corrected as a follow-up.
    ONTOSERVER_INSECURE: "false"

traefik:
  ingressRoute:
    enabled: true
    entryPoints:
      - web              # client → Traefik over plain HTTP; HTTPS is only on the backend side
    backendPort: 80      # Kubernetes Service port. Traefik opens a TLS connection over the TCP
                         # stream to Service port 80. kube-proxy forwards that TCP stream to the
                         # container on port 8080, where Ontoserver answers the TLS handshake.
                         # Use port 80 (not 8080): the Service only exposes port 80.
    backendScheme: https
    serversTransport:
      enabled: true
      insecureSkipVerify: true   # trust Ontoserver's built-in self-signed certificate
```

### 4. Helm install

The install step conditionally appends `--values ./charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml` when `matrix.mode.verifyTraefikRoute == true`. All other flags (`--set ontoserver.deployment.isReadOnly`, resource sizing) are unchanged.

### 5. Step conditionality and guards

Three existing steps need guards:

| Step | Change |
|---|---|
| "Run integration tests" (`helm test`) | Add `if: matrix.mode.runHelmTest` |
| "Verify mode-specific test hook rendered" | Add `if: matrix.mode.runHelmTest` — without this guard, `kubectl get job ""` is an invalid command that will fail the job |
| "Collect test logs" `expectedHook` log lines | **Must** guard on `matrix.mode.runHelmTest` — `kubectl describe job ""` and `kubectl logs -l job-name=` with an empty value produce API errors. The existing `\|\| true` suppresses exit codes but not the error output; explicit guarding is required. |

**Why `helm test` is skipped for this entry:** The existing test hooks (`test-metadata-job.yaml`, `test-fhir-ro-job.yaml`) hardcode `BASE_URL="http://..."` pointing at the ClusterIP Service. With `ONTOSERVER_INSECURE: "false"`, Ontoserver serves HTTPS on port 8080. A plain HTTP request to the Service's port 80 (which NATs to HTTPS port 8080) will fail with an SSL handshake error. Enabling `runHelmTest` for this entry would require new HTTPS-aware test hook templates, which is out of scope for this test.

### 6. Verification step

A dedicated step runs when `matrix.mode.verifyTraefikRoute == true`. The `kubectl rollout status` is omitted — the preceding `helm install traefik ... --wait` already guarantees Traefik is fully ready before this step runs.

```bash
# Open a local port to Traefik's web entrypoint
kubectl port-forward -n kube-system svc/traefik 18080:80 &

# Wait for port-forward to be ready with a retry loop (more reliable than a fixed sleep)
for i in $(seq 15); do
  curl -s http://localhost:18080/ >/dev/null 2>&1 && break
  sleep 1
done

# Verify the full proxy path: curl → Traefik → ServersTransport → Ontoserver HTTPS
curl -sf \
  -H "Host: ontoserver.traefik-test.local" \
  http://localhost:18080/fhir/metadata \
| grep '"resourceType":"CapabilityStatement"'
```

This validates: Traefik receives the request → matches the IngressRoute rule → initiates an HTTPS connection to the Service via ServersTransport (`insecureSkipVerify: true`) → Ontoserver responds over HTTPS → response reaches the curl client.

### 7. Diagnostics

The existing "Diagnose failed install" (`if: failure()`) and "Collect test logs" (`if: always()`) steps apply to all matrix entries. The "Collect test logs" step gains one additional line conditional on `matrix.mode.verifyTraefikRoute`:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50 || true
```

### 8. CI trigger note

The `integration-tests.yml` workflow currently triggers on `push: branches: [main]` only. The new matrix entry will not run in CI until the branch is merged to `main`. To validate the new job before merging, temporarily add a `pull_request` trigger on the feature branch, or run the workflow manually via `workflow_dispatch`.

## Files changed

| File | Change |
|---|---|
| `.github/workflows/integration-tests.yml` | Add matrix fields; add "Install Traefik v3" step; add `if:` guards; add conditional verify step; add Traefik log line |
| `charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml` | New fixture values file |
