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

Two boolean fields are added to the matrix schema. Existing entries retain their current behaviour via defaults.

| Field | read-only | read-write | traefik-https-backend |
|---|---|---|---|
| `disableTraefik` | `true` | `true` | `false` |
| `runHelmTest` | `true` | `true` | `false` |
| `verifyTraefikRoute` | `false` | `false` | `true` |
| `expectedHook` | (existing value) | (existing value) | `""` |
| `unexpectedHook` | (existing value) | (existing value) | `""` |

### 2. k3d cluster

The k3d creation step conditionally adds `--k3s-arg "--disable=traefik@server:0"` only when `matrix.mode.disableTraefik == true`. For the Traefik entry the flag is omitted so that k3s's built-in Traefik runs.

**CRD compatibility note:** k3s ships Traefik v2, which uses `traefik.containo.us/v1alpha1`. The chart templates use `traefik.io/v1alpha1` (Traefik v3). This must be verified at implementation time. If the bundled Traefik version does not support `traefik.io/v1alpha1`, the CI job must either install a newer Traefik or the test must use a Traefik Helm chart installation with a pinned v3 version.

### 3. Fixture values file

New file: `charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml`

```yaml
ontoserver:
  hostNames:
    - ontoserver.traefik-test.local
  serverName: ontoserver.traefik-test.local
  config:
    ONTOSERVER_INSECURE: "false"   # re-enables Ontoserver's default HTTPS (self-signed /keystore.p12)

traefik:
  ingressRoute:
    enabled: true
    entryPoints:
      - web            # client → Traefik over plain HTTP; TLS is backend-only in this test
    backendPort: 80    # Kubernetes Service port (routes to container port 8080, which serves HTTPS)
    backendScheme: https
    serversTransport:
      enabled: true
      insecureSkipVerify: true   # trust Ontoserver's built-in self-signed certificate
```

The matrix entry passes this file via `--values` to the Helm install step.

### 4. Helm install

The existing install step passes `--values` with the fixture file when `matrix.mode.verifyTraefikRoute == true`, in addition to the per-entry resource sizing flags already present.

`ONTOSERVER_INSECURE` is not passed via `--set` for this entry (the fixture file overrides the chart default of `"true"` to `"false"`), so Ontoserver boots with its bundled self-signed keystore at `/keystore.p12` and serves HTTPS on container port 8080.

### 5. Verification step

`helm test` is skipped for this entry (`if: matrix.mode.runHelmTest`) because the existing test hook jobs use `http://` URLs and would fail against an HTTPS backend.

A dedicated step runs when `matrix.mode.verifyTraefikRoute == true`:

```
1. kubectl port-forward -n kube-system svc/traefik 18080:80 &
2. sleep 2
3. curl -sf -H "Host: ontoserver.traefik-test.local" \
         http://localhost:18080/fhir/metadata \
   | grep '"resourceType":"CapabilityStatement"'
```

This validates the full path: curl → Traefik (port-forward) → ServersTransport (insecureSkipVerify) → Ontoserver HTTPS (self-signed cert).

### 6. Diagnostics

The existing "Diagnose failed install" and "Collect test logs" steps cover all matrix entries. The "Collect test logs" step gains one additional line for the Traefik entry:

```
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50 || true
```

This can be made conditional on `matrix.mode.verifyTraefikRoute` or included unconditionally (the command is a no-op when Traefik is not running).

## Files changed

| File | Change |
|---|---|
| `.github/workflows/integration-tests.yml` | Add matrix fields; parameterize k3d step; add conditional verify step; add Traefik log line |
| `charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml` | New fixture values file |

## Open question (resolve at implementation)

Verify the Traefik CRD API group in the k3s-bundled Traefik version used by the k3d cluster. If it is `traefik.containo.us/v1alpha1` (v2) rather than `traefik.io/v1alpha1` (v3), the CI job will need to install Traefik v3 via Helm before running the chart install.
