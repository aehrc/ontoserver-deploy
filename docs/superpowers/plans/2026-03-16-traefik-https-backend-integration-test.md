# Traefik HTTPS Backend Integration Test Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the GitHub Actions integration test matrix with a `traefik-https-backend` job that proves Traefik's ServersTransport correctly proxies requests to an Ontoserver backend serving HTTPS with a self-signed certificate.

**Architecture:** A new matrix entry in `integration-tests.yml` installs Traefik v3 via Helm (with CRDs), deploys the Ontoserver chart with `ONTOSERVER_INSECURE: false` (re-enabling its default HTTPS listener), and verifies the full request path through the IngressRoute via `kubectl port-forward` + `curl`. A new fixture values file encapsulates all Traefik-specific Helm values. Existing matrix entries are unchanged except for two new backfilled boolean fields.

**Tech Stack:** GitHub Actions, k3d/k3s, Helm 3, Traefik v3 Helm chart (`traefik/traefik` v39.0.5), `kubectl port-forward`, `curl`

---

## Chunk 1: Fixture values file

### Task 1: Create and verify the fixture values file

**Files:**
- Create: `charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml`

Background: Ontoserver serves HTTPS by default using a bundled self-signed keystore at `/keystore.p12`. The chart default sets `ONTOSERVER_INSECURE: "true"` which disables this and makes Ontoserver serve plain HTTP. Setting it to `"false"` restores the HTTPS listener. The IngressRoute is configured to use the `web` (HTTP) Traefik entrypoint on the client side; TLS only happens on the backend side (Traefik → Ontoserver). `backendPort: 80` is the Kubernetes Service port (not the container port 8080); Traefik sends TLS ClientHello to the Service on port 80, kube-proxy NATs the TCP stream to the container on port 8080, where Ontoserver answers the TLS handshake.

- [ ] **Step 1: Write the fixture file**

```yaml
# charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml
#
# Integration test fixture for the Traefik HTTPS backend scenario.
# Ontoserver serves HTTPS on port 8080 using its bundled self-signed keystore.
# Traefik connects to the HTTPS backend via ServersTransport (insecureSkipVerify).
#
# Used by: .github/workflows/integration-tests.yml (traefik-https-backend matrix entry)
ontoserver:
  hostNames:
    - ontoserver.traefik-test.local
  serverName: ontoserver.traefik-test.local
  config:
    # ONTOSERVER_INSECURE=true disables Ontoserver's inbound TLS listener (serves plain HTTP).
    # The chart default is "true" for convenience in cluster-internal deployments.
    # Setting to "false" restores Ontoserver's out-of-box behaviour: HTTPS on port 8080
    # using its bundled self-signed keystore at /keystore.p12.
    #
    # Note: values.yaml documents this flag as "Disable TLS verification for outgoing
    # connections", which is incomplete. Per Ontoserver documentation: "By default,
    # Ontoserver will run using SSL/TLS. To disable SSL/TLS, add ONTOSERVER_INSECURE=true."
    ONTOSERVER_INSECURE: "false"

traefik:
  ingressRoute:
    enabled: true
    entryPoints:
      - web              # client → Traefik over plain HTTP; HTTPS is only on the backend side
    backendPort: 80      # Kubernetes Service port. Traefik opens a TLS connection over the TCP
                         # stream to Service port 80. kube-proxy NATs the stream to container
                         # port 8080, where Ontoserver answers the TLS handshake.
                         # Must be 80 (not 8080): the Service only exposes port 80.
    backendScheme: https
    serversTransport:
      enabled: true
      insecureSkipVerify: true   # trust Ontoserver's built-in self-signed certificate
```

- [ ] **Step 2: Verify the fixture renders valid IngressRoute and ServersTransport**

First, build chart dependencies if not already done:
```bash
helm dependency build ./charts/ontoserver
```

Check IngressRoute and ServersTransport are both rendered:
```bash
helm template test-traefik ./charts/ontoserver \
  --values charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml \
  | grep -E "^kind: (IngressRoute|ServersTransport)"
```

Expected output (exactly):
```
kind: IngressRoute
kind: ServersTransport
```

Verify ServersTransport has `insecureSkipVerify: true`:
```bash
helm template test-traefik ./charts/ontoserver \
  --values charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml \
  | grep "insecureSkipVerify"
```
Expected: `  insecureSkipVerify: true`

Verify IngressRoute references the ServersTransport:
```bash
helm template test-traefik ./charts/ontoserver \
  --values charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml \
  | grep "serversTransport:"
```
Expected: `          serversTransport: test-traefik-ontoserver-serverstransport`

Verify IngressRoute uses `backendScheme: https`:
```bash
helm template test-traefik ./charts/ontoserver \
  --values charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml \
  | grep "scheme:"
```
Expected: `          scheme: https`

- [ ] **Step 3: Commit**

```bash
git add charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml
git commit -m "test: add fixture values for Traefik HTTPS backend integration test"
```

---

## Chunk 2: Workflow changes

### Task 2: Backfill existing matrix entries and add the new `traefik-https-backend` entry

**Files:**
- Modify: `.github/workflows/integration-tests.yml` lines 14–24 (the `matrix.mode` list)

Background: GitHub Actions evaluates a missing matrix field as `""` (falsy). The two new boolean fields `runHelmTest` and `verifyTraefikRoute` must be explicitly set on **all three** entries — if they are absent from `read-only` or `read-write`, the `if: matrix.mode.runHelmTest` guards added in Task 3 will silently skip `helm test` for those existing entries, breaking the test suite.

- [ ] **Step 1: Replace the matrix block**

Replace lines 13–24 of `.github/workflows/integration-tests.yml`:

**Before:**
```yaml
      matrix:
        mode:
          - name: read-only
            release: ontoserver-ro
            isReadOnly: "true"
            expectedHook: ontoserver-ro-ontoserver-test-fhir-ro
            unexpectedHook: ontoserver-ro-ontoserver-test-fhir-rw
          - name: read-write
            release: ontoserver-rw
            isReadOnly: "false"
            expectedHook: ontoserver-rw-ontoserver-test-fhir-rw
            unexpectedHook: ontoserver-rw-ontoserver-test-fhir-ro
```

**After:**
```yaml
      matrix:
        mode:
          - name: read-only
            release: ontoserver-ro
            isReadOnly: "true"
            expectedHook: ontoserver-ro-ontoserver-test-fhir-ro
            unexpectedHook: ontoserver-ro-ontoserver-test-fhir-rw
            runHelmTest: true
            verifyTraefikRoute: false
          - name: read-write
            release: ontoserver-rw
            isReadOnly: "false"
            expectedHook: ontoserver-rw-ontoserver-test-fhir-rw
            unexpectedHook: ontoserver-rw-ontoserver-test-fhir-ro
            runHelmTest: true
            verifyTraefikRoute: false
          - name: traefik-https-backend
            release: ontoserver-traefik
            isReadOnly: "true"
            expectedHook: ""
            unexpectedHook: ""
            runHelmTest: false
            verifyTraefikRoute: true
```

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/integration-tests.yml').read()); print('YAML valid')"
```
Expected: `YAML valid`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/integration-tests.yml
git commit -m "ci: add traefik-https-backend matrix entry with runHelmTest/verifyTraefikRoute fields"
```

---

### Task 3: Add `if:` guards to existing steps and split log collection

**Files:**
- Modify: `.github/workflows/integration-tests.yml` — steps "Run integration tests", "Verify mode-specific test hook rendered", "Collect test logs"

Background: Three existing steps reference `matrix.mode.expectedHook`. For the new `traefik-https-backend` entry, `expectedHook` is `""`. Without guards:
- `helm test ""` fails with argument error
- `kubectl get job ""` fails with an invalid API request
- `kubectl describe job "" || true` and `kubectl logs -l job-name= || true` emit API errors (even with `|| true` suppressing exit codes)

The cleanest fix is to add `if: matrix.mode.runHelmTest` to the first two steps and split the "Collect test logs" step into three parts.

- [ ] **Step 1: Guard the "Run integration tests" step**

Add `if: matrix.mode.runHelmTest` to the step:

**Before:**
```yaml
      - name: Run integration tests
        run: helm test ${{ matrix.mode.release }} --timeout 10m
```

**After:**
```yaml
      - name: Run integration tests
        if: matrix.mode.runHelmTest
        run: helm test ${{ matrix.mode.release }} --timeout 10m
```

- [ ] **Step 2: Guard the "Verify mode-specific test hook rendered" step**

**Before:**
```yaml
      - name: Verify mode-specific test hook rendered
        run: |
          kubectl get job ${{ matrix.mode.expectedHook }}
          if kubectl get job ${{ matrix.mode.unexpectedHook }} >/dev/null 2>&1; then
            echo "Unexpected Helm test job found: ${{ matrix.mode.unexpectedHook }}"
            exit 1
          fi
```

**After:**
```yaml
      - name: Verify mode-specific test hook rendered
        if: matrix.mode.runHelmTest
        run: |
          kubectl get job ${{ matrix.mode.expectedHook }}
          if kubectl get job ${{ matrix.mode.unexpectedHook }} >/dev/null 2>&1; then
            echo "Unexpected Helm test job found: ${{ matrix.mode.unexpectedHook }}"
            exit 1
          fi
```

- [ ] **Step 3: Split "Collect test logs" into three parts**

Replace the single "Collect test logs" step with three steps. The first covers common logs (runs for all entries). The second covers Helm test hook logs (guarded on `runHelmTest`). The third covers Traefik logs (guarded on `verifyTraefikRoute`).

**Before:**
```yaml
      - name: Collect test logs
        if: always()
        run: |
          echo "=== Events ==="
          kubectl get events --sort-by='.lastTimestamp'
          echo "=== Ontoserver pod logs (all containers) ==="
          kubectl logs -l app=${{ matrix.mode.release }}-ontoserver --all-containers=true --tail=50 || true
          echo "=== test-metadata job ==="
          kubectl describe job ${{ matrix.mode.release }}-ontoserver-test-metadata || true
          echo "=== test-metadata logs ==="
          kubectl logs -l job-name=${{ matrix.mode.release }}-ontoserver-test-metadata --tail=200 || true
          echo "=== mode-specific test job ==="
          kubectl describe job ${{ matrix.mode.expectedHook }} || true
          echo "=== mode-specific test logs ==="
          kubectl logs -l job-name=${{ matrix.mode.expectedHook }} --tail=200 || true
```

**After:**
```yaml
      - name: Collect test logs
        if: always()
        run: |
          echo "=== Events ==="
          kubectl get events --sort-by='.lastTimestamp'
          echo "=== Ontoserver pod logs (all containers) ==="
          kubectl logs -l app=${{ matrix.mode.release }}-ontoserver --all-containers=true --tail=50 || true
          echo "=== test-metadata job ==="
          kubectl describe job ${{ matrix.mode.release }}-ontoserver-test-metadata || true
          echo "=== test-metadata logs ==="
          kubectl logs -l job-name=${{ matrix.mode.release }}-ontoserver-test-metadata --tail=200 || true

      - name: Collect helm test hook logs
        if: always() && matrix.mode.runHelmTest
        run: |
          echo "=== mode-specific test job ==="
          kubectl describe job ${{ matrix.mode.expectedHook }} || true
          echo "=== mode-specific test logs ==="
          kubectl logs -l job-name=${{ matrix.mode.expectedHook }} --tail=200 || true

      - name: Collect Traefik logs
        if: always() && matrix.mode.verifyTraefikRoute
        run: |
          echo "=== Traefik logs ==="
          kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50 || true
```

- [ ] **Step 4: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/integration-tests.yml').read()); print('YAML valid')"
```
Expected: `YAML valid`

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/integration-tests.yml
git commit -m "ci: add if guards for helm test steps, split log collection by entry type"
```

---

### Task 4: Add Install Traefik v3, conditional chart values, Verify Traefik route steps, and `workflow_dispatch` trigger

**Files:**
- Modify: `.github/workflows/integration-tests.yml`

Background on step ordering: The "Install Traefik v3" step must run **after** "Create k3d cluster" and **before** "Build chart dependencies" so Traefik CRDs are present when Helm resolves the chart. The "Verify Traefik route" step runs after "Install chart" (Ontoserver is ready). The `workflow_dispatch` trigger allows manually running the workflow on the feature branch before merging to `main` (the only current trigger).

Background on the `--values` flag: The `helm install` step needs to conditionally append `--values ./charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml` for the `traefik-https-backend` entry only. The cleanest approach in a multi-line `run:` block is a bash variable set before the `helm install` command.

- [ ] **Step 1: Add `workflow_dispatch` trigger**

**Before:**
```yaml
on:
  push:
    branches: [main]
```

**After:**
```yaml
on:
  push:
    branches: [main]
  workflow_dispatch:
```

- [ ] **Step 2: Add "Install Traefik v3" step after "Create k3d cluster"**

Insert after the "Create k3d cluster" step (after line 40) and before "Build chart dependencies":

```yaml
      - name: Install Traefik v3
        if: matrix.mode.verifyTraefikRoute
        run: |
          helm repo add traefik https://traefik.github.io/charts
          helm repo update
          helm install traefik traefik/traefik \
            --namespace kube-system \
            --version 39.0.5 \
            --set ports.web.expose.default=true \
            --set ports.web.exposedPort=80 \
            --wait --timeout 2m
```

- [ ] **Step 3: Update the "Install chart" step to conditionally pass the fixture values file**

**Before:**
```yaml
      - name: Install chart
        run: |
          helm install ${{ matrix.mode.release }} ./charts/ontoserver \
            --set ontoserver.deployment.isReadOnly=${{ matrix.mode.isReadOnly }} \
            --set ontoserver.managementService.enabled=true \
            --set ontoserver.imageCredentials.username=${{ secrets.QUAY_USERNAME }} \
            --set ontoserver.imageCredentials.password=${{ secrets.QUAY_PASSWORD }} \
            --set ontoserver.resources.ontoserver.requests.cpu=500m \
            --set ontoserver.resources.ontoserver.limits.cpu=2 \
            --set ontoserver.resources.ontoserver.requests.memory=2G \
            --set ontoserver.resources.ontoserver.limits.memory=2G \
            --set ontoserver.resources.ontoserver.initialHeapSize=1500m \
            --set ontoserver.resources.ontoserver.maxHeapSize=1500m \
            --set ontoserver.resources.db.requests.cpu=250m \
            --set ontoserver.resources.db.limits.cpu=1 \
            --set ontoserver.resources.db.requests.memory=512Mi \
            --set ontoserver.resources.db.limits.memory=1G \
            --wait \
            --timeout 10m
```

**After:**
```yaml
      - name: Install chart
        run: |
          EXTRA_VALUES=""
          if [[ "${{ matrix.mode.verifyTraefikRoute }}" == "true" ]]; then
            EXTRA_VALUES="--values ./charts/ontoserver/tests/fixtures/traefik-https-backend-values.yaml"
          fi
          helm install ${{ matrix.mode.release }} ./charts/ontoserver \
            --set ontoserver.deployment.isReadOnly=${{ matrix.mode.isReadOnly }} \
            --set ontoserver.managementService.enabled=true \
            --set ontoserver.imageCredentials.username=${{ secrets.QUAY_USERNAME }} \
            --set ontoserver.imageCredentials.password=${{ secrets.QUAY_PASSWORD }} \
            --set ontoserver.resources.ontoserver.requests.cpu=500m \
            --set ontoserver.resources.ontoserver.limits.cpu=2 \
            --set ontoserver.resources.ontoserver.requests.memory=2G \
            --set ontoserver.resources.ontoserver.limits.memory=2G \
            --set ontoserver.resources.ontoserver.initialHeapSize=1500m \
            --set ontoserver.resources.ontoserver.maxHeapSize=1500m \
            --set ontoserver.resources.db.requests.cpu=250m \
            --set ontoserver.resources.db.limits.cpu=1 \
            --set ontoserver.resources.db.requests.memory=512Mi \
            --set ontoserver.resources.db.limits.memory=1G \
            $EXTRA_VALUES \
            --wait \
            --timeout 10m
```

- [ ] **Step 4: Add "Verify Traefik route" step after "Verify mode-specific test hook rendered"**

```yaml
      - name: Verify Traefik route (HTTPS backend)
        if: matrix.mode.verifyTraefikRoute
        run: |
          # Expose Traefik's web entrypoint locally (ports.web.exposedPort=80)
          kubectl port-forward -n kube-system svc/traefik 18080:80 &

          # Wait for port-forward to be ready (up to 15 s).
          # Uses Traefik's built-in /ping health endpoint with --fail so the loop
          # only breaks on an actual HTTP 200, not on connection errors returning 0.
          for i in $(seq 15); do
            curl -sf http://localhost:18080/ping >/dev/null 2>&1 && break
            sleep 1
          done

          # Full path: curl → Traefik (web entrypoint) → ServersTransport (insecureSkipVerify)
          #            → Ontoserver HTTPS (self-signed /keystore.p12)
          curl -sf \
            -H "Host: ontoserver.traefik-test.local" \
            http://localhost:18080/fhir/metadata \
          | grep '"resourceType":"CapabilityStatement"'

```

- [ ] **Step 5: Validate YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/integration-tests.yml').read()); print('YAML valid')"
```
Expected: `YAML valid`

- [ ] **Step 6: Verify final workflow structure looks correct**

```bash
grep -n "name:" .github/workflows/integration-tests.yml
```

Expected output (step names in order):
```
9:    name: Integration Tests (${{ matrix.mode.name }})
28:      - name: Install Helm
33:      - name: Create k3d cluster
41:      - name: Install Traefik v3
49:      - name: Build chart dependencies
52:      - name: Install chart
67:      - name: Diagnose failed install
76:      - name: Run integration tests
80:      - name: Verify mode-specific test hook rendered
88:      - name: Verify Traefik route (HTTPS backend)
100:      - name: Collect test logs
113:      - name: Collect helm test hook logs
121:      - name: Collect Traefik logs
```
(Line numbers are approximate — what matters is the order.)

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/integration-tests.yml
git commit -m "ci: add Traefik v3 install step, Traefik route verification, and workflow_dispatch trigger"
```

---

## Chunk 3: Follow-up fix

### Task 5: Fix the `ONTOSERVER_INSECURE` parameter comment in values.yaml

**Files:**
- Modify: `charts/ontoserver/values.yaml` line 287 (the `@param` comment for `ONTOSERVER_INSECURE`)

Background: The current comment reads "Disable TLS verification for outgoing connections" but `ONTOSERVER_INSECURE=true` actually disables the server's own inbound TLS listener (makes it serve HTTP). The misleading comment could cause future operators to leave TLS enabled when they intend to disable it, or vice versa.

- [ ] **Step 1: Fix the comment**

Locate and update line 287 of `charts/ontoserver/values.yaml`:

**Before:**
```yaml
    ## @param ontoserver.config.ONTOSERVER_INSECURE        Disable TLS verification for outgoing connections
    ONTOSERVER_INSECURE: "true"
```

**After:**
```yaml
    ## @param ontoserver.config.ONTOSERVER_INSECURE        Disable Ontoserver's inbound TLS listener — set to "true" to serve plain HTTP, "false" (or omit) to serve HTTPS using the bundled self-signed keystore
    ONTOSERVER_INSECURE: "true"
```

- [ ] **Step 2: Run helm lint to confirm no schema violations**

```bash
helm lint --strict ./charts/ontoserver
```
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 3: Commit**

```bash
git add charts/ontoserver/values.yaml
git commit -m "docs: fix ONTOSERVER_INSECURE parameter description — controls inbound TLS listener not outbound verification"
```
