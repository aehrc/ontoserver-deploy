# ontoserver-indexer Helm Chart Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create `charts/ontoserver-indexer` — a standalone Helm chart that renders a raw Kubernetes `batch/v1 Job` to index a code system and publish the result to a syndication server, without requiring the ontoserver-indexing-operator.

**Architecture:** Single chart under `charts/ontoserver-indexer/` with four templates (`_helpers.tpl`, `validate-values.yaml`, `secret.yaml`, `job.yaml`) and one example file. Tests use `helm unittest` YAML suites mirroring the `ontoserver` chart pattern. TDD throughout — write the failing test, then the template.

**Tech Stack:** Helm 3, helm-unittest, Kubernetes batch/v1 Job

---

## Reference Material

- Design doc: `docs/plans/2026-03-08-ontoserver-indexer-chart-design.md`
- Operator job construction: `/Users/ede020/work/ontoserver-indexing-operator/src/main/java/com/csiro/aehrc/OntoserverIndexJobReconciler.java` (lines 574–604 for args, 480–570 for env vars)
- Existing chart patterns to follow: `charts/ontoserver/templates/validate-values.yaml`, `charts/ontoserver/templates/secret.yaml`
- Run tests: `helm unittest charts/ontoserver-indexer`

---

## Task 1: Chart scaffold

**Files:**
- Create: `charts/ontoserver-indexer/Chart.yaml`
- Create: `charts/ontoserver-indexer/values.yaml`
- Create: `charts/ontoserver-indexer/templates/_helpers.tpl`

**Step 1: Create Chart.yaml**

```yaml
apiVersion: v2
name: ontoserver-indexer
description: Runs a Kubernetes Job to index a SNOMED CT (or other) code system and publish to a syndication server
type: application
version: 1.0.0
appVersion: "ctsa-6"
home: https://ontoserver.csiro.au
sources:
  - https://github.com/aehrc/ontoserver-deploy
keywords:
  - ontoserver
  - fhir
  - terminology
  - snomed
  - indexer
maintainers:
  - name: CSIRO
    email: ontoserver-support@csiro.au
annotations:
  artifacthub.io/license: Apache-2.0
```

**Step 2: Create values.yaml**

```yaml
image:
  repository: quay.io/aehrc/ontoserver
  tag: ctsa-6
  pullSecret: ""            # name of an existing imagePullSecret

job:
  name: ""                  # defaults to {{ .Release.Name }}
  activeDeadlineSeconds: 7200
  ttlSecondsAfterFinished: 3600

resources:
  memoryGb: 20              # sets both -Xmx and memory request/limit

codeSystem:
  url: ""                   # e.g. http://snomed.info/sct/32506021000036107
  version: ""               # e.g. http://snomed.info/sct/32506021000036107/version/20231130

rf2:
  kind: FULL                # FULL | SNAPSHOT | DELTA
  files: []                 # list of RF2 download URLs

syndication:
  endpoint: ""              # syndication server base URL
  tokenEndpoint: ""         # OAuth token URL
  feed: ""                  # feed identifier
  entryTitle: ""            # entry title in the feed
  entryFileName: ""         # optional — custom output filename
  securityLabels: []        # optional — list of permission labels

auth:
  # OAuth2 client credentials — mutually exclusive with basic
  oauth2:
    secretRef: ""           # name of existing Secret (keys: clientId, clientSecret)
    clientId: ""            # OR provide directly — chart creates a Secret
    clientSecret: ""
  # Basic auth — mutually exclusive with oauth2
  basic:
    secretRef: ""           # name of existing Secret (keys: username, password)
    username: ""            # OR provide directly — chart creates a Secret
    password: ""
  # All empty = no auth (valid)

languageRefsets:
  forModule: {}             # map of moduleId -> comma-separated refset IDs
                            # e.g. "32506021000036107": "32570271000036106,900000000000509007"

resolveSkew: ""             # optional — e.g. "20231130"

sentry:                     # all fields ignored unless sentry.dsn is non-empty
  dsn: ""
  environment: "Indexer"
  serverName: ""
```

**Step 3: Create templates/_helpers.tpl**

```
{{/*
Job name — use job.name if set, otherwise Release.Name
*/}}
{{- define "ontoserver-indexer.jobName" -}}
{{- if .Values.job.name }}{{ .Values.job.name }}{{- else }}{{ .Release.Name }}{{- end }}
{{- end }}

{{/*
Secret name for inline auth credentials
*/}}
{{- define "ontoserver-indexer.secretName" -}}
{{ .Release.Name }}-indexer-auth
{{- end }}

{{/*
True if OAuth2 inline credentials provided
*/}}
{{- define "ontoserver-indexer.oauth2Inline" -}}
{{- if .Values.auth.oauth2.clientId }}true{{- end }}
{{- end }}

{{/*
True if Basic inline credentials provided
*/}}
{{- define "ontoserver-indexer.basicInline" -}}
{{- if .Values.auth.basic.username }}true{{- end }}
{{- end }}

{{/*
Resolved OAuth2 secret name — inline chart secret or user-supplied secretRef
*/}}
{{- define "ontoserver-indexer.oauth2SecretName" -}}
{{- if .Values.auth.oauth2.clientId }}{{ include "ontoserver-indexer.secretName" . }}
{{- else }}{{ .Values.auth.oauth2.secretRef }}{{- end }}
{{- end }}

{{/*
Resolved Basic auth secret name
*/}}
{{- define "ontoserver-indexer.basicSecretName" -}}
{{- if .Values.auth.basic.username }}{{ include "ontoserver-indexer.secretName" . }}
{{- else }}{{ .Values.auth.basic.secretRef }}{{- end }}
{{- end }}
```

**Step 4: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: scaffold ontoserver-indexer chart"
```

---

## Task 2: validate-values.yaml (TDD)

**Files:**
- Create: `charts/ontoserver-indexer/tests/validate_values_test.yaml`
- Create: `charts/ontoserver-indexer/templates/validate-values.yaml`

**Step 1: Write the failing tests**

Create `charts/ontoserver-indexer/tests/validate_values_test.yaml`:

```yaml
suite: validate-values tests
templates:
  - templates/validate-values.yaml

tests:
  - it: passes with all required values set
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      rf2.kind: FULL
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - hasDocuments:
          count: 0

  - it: fails when codeSystem.url is empty
    set:
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - failedTemplate:
          errorMessage: "codeSystem.url is required"

  - it: fails when codeSystem.version is empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - failedTemplate:
          errorMessage: "codeSystem.version is required"

  - it: fails when rf2.files is empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - failedTemplate:
          errorMessage: "rf2.files must contain at least one URL"

  - it: fails when rf2.kind is invalid
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      rf2.kind: INVALID
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - failedTemplate:
          errorMessage: "rf2.kind must be one of: FULL, SNAPSHOT, DELTA"

  - it: fails when syndication.endpoint is empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - failedTemplate:
          errorMessage: "syndication.endpoint is required"

  - it: fails when syndication.tokenEndpoint is empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - failedTemplate:
          errorMessage: "syndication.tokenEndpoint is required"

  - it: fails when syndication.feed is empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.entryTitle: My Entry
    asserts:
      - failedTemplate:
          errorMessage: "syndication.feed is required"

  - it: fails when syndication.entryTitle is empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
    asserts:
      - failedTemplate:
          errorMessage: "syndication.entryTitle is required"

  - it: fails when both oauth2 and basic auth configured
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      auth.oauth2.clientId: my-client
      auth.basic.username: my-user
    asserts:
      - failedTemplate:
          errorMessage: "auth.oauth2 and auth.basic are mutually exclusive"

  - it: fails when oauth2 secretRef and clientId both set
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      auth.oauth2.secretRef: my-secret
      auth.oauth2.clientId: my-client
    asserts:
      - failedTemplate:
          errorMessage: "auth.oauth2.secretRef and auth.oauth2.clientId are mutually exclusive"

  - it: fails when basic secretRef and username both set
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      auth.basic.secretRef: my-secret
      auth.basic.username: my-user
    asserts:
      - failedTemplate:
          errorMessage: "auth.basic.secretRef and auth.basic.username are mutually exclusive"

  - it: passes with no auth configured
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - hasDocuments:
          count: 0
```

**Step 2: Run — expect failure (template not found)**

```bash
helm unittest charts/ontoserver-indexer
```

Expected: error — no `validate-values.yaml` template yet.

**Step 3: Implement validate-values.yaml**

Create `charts/ontoserver-indexer/templates/validate-values.yaml`:

```
{{- if empty .Values.codeSystem.url }}
  {{- fail "codeSystem.url is required" }}
{{- end }}

{{- if empty .Values.codeSystem.version }}
  {{- fail "codeSystem.version is required" }}
{{- end }}

{{- if empty .Values.rf2.files }}
  {{- fail "rf2.files must contain at least one URL" }}
{{- end }}

{{- $validKinds := list "FULL" "SNAPSHOT" "DELTA" }}
{{- if not (has .Values.rf2.kind $validKinds) }}
  {{- fail "rf2.kind must be one of: FULL, SNAPSHOT, DELTA" }}
{{- end }}

{{- if empty .Values.syndication.endpoint }}
  {{- fail "syndication.endpoint is required" }}
{{- end }}

{{- if empty .Values.syndication.tokenEndpoint }}
  {{- fail "syndication.tokenEndpoint is required" }}
{{- end }}

{{- if empty .Values.syndication.feed }}
  {{- fail "syndication.feed is required" }}
{{- end }}

{{- if empty .Values.syndication.entryTitle }}
  {{- fail "syndication.entryTitle is required" }}
{{- end }}

{{- $hasOauth2 := or .Values.auth.oauth2.secretRef .Values.auth.oauth2.clientId }}
{{- $hasBasic  := or .Values.auth.basic.secretRef  .Values.auth.basic.username }}
{{- if and $hasOauth2 $hasBasic }}
  {{- fail "auth.oauth2 and auth.basic are mutually exclusive" }}
{{- end }}

{{- if and .Values.auth.oauth2.secretRef .Values.auth.oauth2.clientId }}
  {{- fail "auth.oauth2.secretRef and auth.oauth2.clientId are mutually exclusive" }}
{{- end }}

{{- if and .Values.auth.basic.secretRef .Values.auth.basic.username }}
  {{- fail "auth.basic.secretRef and auth.basic.username are mutually exclusive" }}
{{- end }}
```

**Step 4: Run — expect all tests pass**

```bash
helm unittest charts/ontoserver-indexer
```

Expected: all 13 tests in `validate_values_test.yaml` pass.

**Step 5: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: add validate-values template and tests"
```

---

## Task 3: secret.yaml (TDD)

**Files:**
- Create: `charts/ontoserver-indexer/tests/secret_test.yaml`
- Create: `charts/ontoserver-indexer/templates/secret.yaml`

**Step 1: Write the failing tests**

Create `charts/ontoserver-indexer/tests/secret_test.yaml`:

```yaml
suite: secret template tests
templates:
  - templates/secret.yaml

tests:
  - it: renders no secret when no auth configured
    asserts:
      - hasDocuments:
          count: 0

  - it: renders no secret when oauth2 secretRef used
    set:
      auth.oauth2.secretRef: existing-secret
    asserts:
      - hasDocuments:
          count: 0

  - it: renders no secret when basic secretRef used
    set:
      auth.basic.secretRef: existing-secret
    asserts:
      - hasDocuments:
          count: 0

  - it: renders secret when oauth2 inline credentials provided
    set:
      auth.oauth2.clientId: my-client
      auth.oauth2.clientSecret: my-secret
    asserts:
      - hasDocuments:
          count: 1
      - isKind:
          of: Secret
      - equal:
          path: metadata.name
          value: RELEASE-NAME-indexer-auth
      - isNotEmpty:
          path: data.clientId
      - isNotEmpty:
          path: data.clientSecret

  - it: renders secret when basic inline credentials provided
    set:
      auth.basic.username: my-user
      auth.basic.password: my-pass
    asserts:
      - hasDocuments:
          count: 1
      - isKind:
          of: Secret
      - equal:
          path: metadata.name
          value: RELEASE-NAME-indexer-auth
      - isNotEmpty:
          path: data.username
      - isNotEmpty:
          path: data.password
```

**Step 2: Run — expect failure**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 3: Implement secret.yaml**

Create `charts/ontoserver-indexer/templates/secret.yaml`:

```
{{- if or .Values.auth.oauth2.clientId .Values.auth.basic.username }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "ontoserver-indexer.secretName" . }}
data:
  {{- if .Values.auth.oauth2.clientId }}
  clientId: {{ .Values.auth.oauth2.clientId | b64enc }}
  clientSecret: {{ .Values.auth.oauth2.clientSecret | b64enc }}
  {{- end }}
  {{- if .Values.auth.basic.username }}
  username: {{ .Values.auth.basic.username | b64enc }}
  password: {{ .Values.auth.basic.password | b64enc }}
  {{- end }}
{{- end }}
```

**Step 4: Run — expect all tests pass**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 5: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: add secret template and tests"
```

---

## Task 4: job.yaml — structure, image and resources (TDD)

**Files:**
- Create: `charts/ontoserver-indexer/tests/job_test.yaml`
- Modify: `charts/ontoserver-indexer/templates/job.yaml`

**Step 1: Write the failing tests**

Create `charts/ontoserver-indexer/tests/job_test.yaml` (initial section — add more tests in later tasks):

```yaml
suite: job template tests
templates:
  - templates/job.yaml

# Shared valid values used by most tests
values: []

tests:
  - it: renders a Job
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - isKind:
          of: Job
      - hasDocuments:
          count: 1

  - it: uses Release.Name as job name by default
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: metadata.name
          value: RELEASE-NAME

  - it: uses job.name when set
    set:
      job.name: my-custom-job
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: metadata.name
          value: my-custom-job

  - it: sets activeDeadlineSeconds
    set:
      job.activeDeadlineSeconds: 9000
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: spec.activeDeadlineSeconds
          value: 9000

  - it: sets ttlSecondsAfterFinished
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: spec.ttlSecondsAfterFinished
          value: 3600

  - it: sets backoffLimit to 0
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: spec.backoffLimit
          value: 0

  - it: sets restartPolicy to Never
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: spec.template.spec.restartPolicy
          value: Never

  - it: sets container image from values
    set:
      image.repository: quay.io/aehrc/ontoserver
      image.tag: ctsa-6
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: quay.io/aehrc/ontoserver:ctsa-6

  - it: sets memory request and limit from resources.memoryGb
    set:
      resources.memoryGb: 24
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: spec.template.spec.containers[0].resources.requests.memory
          value: 24G
      - equal:
          path: spec.template.spec.containers[0].resources.limits.memory
          value: 24G

  - it: sets imagePullSecrets when pullSecret provided
    set:
      image.pullSecret: my-pull-secret
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: spec.template.spec.imagePullSecrets[0].name
          value: my-pull-secret

  - it: omits imagePullSecrets when pullSecret empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - isNull:
          path: spec.template.spec.imagePullSecrets
```

**Step 2: Run — expect failure**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 3: Implement job.yaml (structure only — no args or env vars yet)**

Create `charts/ontoserver-indexer/templates/job.yaml`:

```
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "ontoserver-indexer.jobName" . }}
spec:
  backoffLimit: 0
  activeDeadlineSeconds: {{ .Values.job.activeDeadlineSeconds }}
  ttlSecondsAfterFinished: {{ .Values.job.ttlSecondsAfterFinished }}
  template:
    spec:
      restartPolicy: Never
      {{- if .Values.image.pullSecret }}
      imagePullSecrets:
        - name: {{ .Values.image.pullSecret }}
      {{- end }}
      containers:
        - name: indexer
          image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
          resources:
            requests:
              memory: {{ .Values.resources.memoryGb }}G
            limits:
              memory: {{ .Values.resources.memoryGb }}G
```

**Step 4: Run — expect all job structure tests pass**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 5: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: add job template structure, image and resources"
```

---

## Task 5: job.yaml — container args (TDD)

**Files:**
- Modify: `charts/ontoserver-indexer/tests/job_test.yaml` (append tests)
- Modify: `charts/ontoserver-indexer/templates/job.yaml`

**Step 1: Append failing tests to job_test.yaml**

Add these tests to the existing `job_test.yaml` suite:

```yaml
  - it: sets JAVA_OPTS env var from resources.memoryGb
    set:
      resources.memoryGb: 16
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: JAVA_OPTS
            value: "-Xmx16g"

  - it: includes indexCodeSystemDebug as first arg
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - equal:
          path: spec.template.spec.containers[0].command[0]
          value: /run.sh
      - equal:
          path: spec.template.spec.containers[0].args[0]
          value: indexCodeSystemDebug

  - it: passes codeSystem url and version as args
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - contains:
          path: spec.template.spec.containers[0].args
          content: "-s"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "http://snomed.info/sct/32506021000036107"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "-v"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "http://snomed.info/sct/32506021000036107/version/20231130"

  - it: passes rf2 files as repeated -f args
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/file1.zip
      rf2.files[1]: https://example.com/file2.zip
      rf2.kind: SNAPSHOT
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - contains:
          path: spec.template.spec.containers[0].args
          content: "https://example.com/file1.zip"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "https://example.com/file2.zip"

  - it: passes rf2.kind lowercased as -k arg
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      rf2.kind: SNAPSHOT
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - contains:
          path: spec.template.spec.containers[0].args
          content: "-k"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "snapshot"

  - it: passes syndication endpoint, feed and entryTitle
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: "SNOMED CT AU November 2023"
    asserts:
      - contains:
          path: spec.template.spec.containers[0].args
          content: "-synd"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "https://synd.example.com"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "-feed"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "my-feed"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "-t"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "SNOMED CT AU November 2023"

  - it: includes -file arg when entryFileName set
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      syndication.entryFileName: snomed-au-20231130.zip
    asserts:
      - contains:
          path: spec.template.spec.containers[0].args
          content: "-file"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "snomed-au-20231130.zip"

  - it: omits -file arg when entryFileName empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - notContains:
          path: spec.template.spec.containers[0].args
          content: "-file"

  - it: passes each security label as a separate -perms arg
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      syndication.securityLabels[0]: http://snomed.info/sct/32506021000036107
      syndication.securityLabels[1]: http://snomed.info/sct/900000000000207008
    asserts:
      - contains:
          path: spec.template.spec.containers[0].args
          content: "-perms"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "http://snomed.info/sct/32506021000036107"
      - contains:
          path: spec.template.spec.containers[0].args
          content: "http://snomed.info/sct/900000000000207008"
```

**Step 2: Run — expect new tests fail**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 3: Add command, args and JAVA_OPTS env var to job.yaml**

Update the container section in `charts/ontoserver-indexer/templates/job.yaml`:

```
      containers:
        - name: indexer
          image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
          command: ["/run.sh"]
          args:
            - indexCodeSystemDebug
            - -s
            - {{ .Values.codeSystem.url | quote }}
            - -v
            - {{ .Values.codeSystem.version | quote }}
            {{- range .Values.rf2.files }}
            - -f
            - {{ . | quote }}
            {{- end }}
            - -k
            - {{ .Values.rf2.kind | lower | quote }}
            - -synd
            - {{ .Values.syndication.endpoint | quote }}
            - -feed
            - {{ .Values.syndication.feed | quote }}
            {{- if .Values.syndication.entryFileName }}
            - -file
            - {{ .Values.syndication.entryFileName | quote }}
            {{- end }}
            - -t
            - {{ .Values.syndication.entryTitle | quote }}
            {{- range .Values.syndication.securityLabels }}
            - -perms
            - {{ . | quote }}
            {{- end }}
          env:
            - name: JAVA_OPTS
              value: "-Xmx{{ .Values.resources.memoryGb }}g"
          resources:
            requests:
              memory: {{ .Values.resources.memoryGb }}G
            limits:
              memory: {{ .Values.resources.memoryGb }}G
```

**Step 4: Run — expect all tests pass**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 5: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: add job args and JAVA_OPTS env var"
```

---

## Task 6: job.yaml — OAuth2 env vars (TDD)

**Files:**
- Modify: `charts/ontoserver-indexer/tests/job_test.yaml` (append tests)
- Modify: `charts/ontoserver-indexer/templates/job.yaml`

**Step 1: Append failing tests**

```yaml
  - it: adds OAuth2 env vars when oauth2 secretRef provided
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      auth.oauth2.secretRef: my-oauth-secret
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.oauth.endpoint.0
            value: https://synd.example.com
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.oauth.endpoint.token_endpoint.0
            value: https://auth.example.com/token
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.oauth.endpoint.strategy.0
            value: body
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.oauth.endpoint.client_id.0
            valueFrom:
              secretKeyRef:
                name: my-oauth-secret
                key: clientId
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.oauth.endpoint.client_secret.0
            valueFrom:
              secretKeyRef:
                name: my-oauth-secret
                key: clientSecret

  - it: adds OAuth2 env vars using chart-created secret when clientId provided inline
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      auth.oauth2.clientId: my-client
      auth.oauth2.clientSecret: my-secret
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.oauth.endpoint.client_id.0
            valueFrom:
              secretKeyRef:
                name: RELEASE-NAME-indexer-auth
                key: clientId

  - it: omits OAuth2 env vars when no auth configured
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - notContains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.oauth.endpoint.0
```

**Step 2: Run — expect new tests fail**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 3: Add OAuth2 env vars block to job.yaml env section**

Append to the `env:` list in the container:

```
            {{- $oauth2SecretName := include "ontoserver-indexer.oauth2SecretName" . }}
            {{- if $oauth2SecretName }}
            - name: authentication.oauth.endpoint.0
              value: {{ .Values.syndication.endpoint | quote }}
            - name: authentication.oauth.endpoint.token_endpoint.0
              value: {{ .Values.syndication.tokenEndpoint | quote }}
            - name: authentication.oauth.endpoint.strategy.0
              value: body
            - name: authentication.oauth.endpoint.client_id.0
              valueFrom:
                secretKeyRef:
                  name: {{ $oauth2SecretName }}
                  key: clientId
            - name: authentication.oauth.endpoint.client_secret.0
              valueFrom:
                secretKeyRef:
                  name: {{ $oauth2SecretName }}
                  key: clientSecret
            {{- end }}
```

**Step 4: Run — expect all tests pass**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 5: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: add OAuth2 env vars to job template"
```

---

## Task 7: job.yaml — Basic auth env vars (TDD)

**Files:**
- Modify: `charts/ontoserver-indexer/tests/job_test.yaml` (append tests)
- Modify: `charts/ontoserver-indexer/templates/job.yaml`

**Step 1: Append failing tests**

```yaml
  - it: adds Basic auth env vars when basic secretRef provided
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      auth.basic.secretRef: my-basic-secret
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.basic.endpoint.0
            value: https://synd.example.com
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.basic.endpoint.user.0
            valueFrom:
              secretKeyRef:
                name: my-basic-secret
                key: username
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.basic.endpoint.password.0
            valueFrom:
              secretKeyRef:
                name: my-basic-secret
                key: password

  - it: adds Basic auth env vars using chart-created secret when username provided inline
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      auth.basic.username: my-user
      auth.basic.password: my-pass
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.basic.endpoint.user.0
            valueFrom:
              secretKeyRef:
                name: RELEASE-NAME-indexer-auth
                key: username

  - it: omits Basic auth env vars when no auth configured
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - notContains:
          path: spec.template.spec.containers[0].env
          content:
            name: authentication.basic.endpoint.0
```

**Step 2: Run — expect new tests fail**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 3: Add Basic auth env vars block to job.yaml env section**

```
            {{- $basicSecretName := include "ontoserver-indexer.basicSecretName" . }}
            {{- if $basicSecretName }}
            - name: authentication.basic.endpoint.0
              value: {{ .Values.syndication.endpoint | quote }}
            - name: authentication.basic.endpoint.user.0
              valueFrom:
                secretKeyRef:
                  name: {{ $basicSecretName }}
                  key: username
            - name: authentication.basic.endpoint.password.0
              valueFrom:
                secretKeyRef:
                  name: {{ $basicSecretName }}
                  key: password
            {{- end }}
```

**Step 4: Run — expect all tests pass**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 5: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: add Basic auth env vars to job template"
```

---

## Task 8: job.yaml — optional env vars (TDD)

**Files:**
- Modify: `charts/ontoserver-indexer/tests/job_test.yaml` (append tests)
- Modify: `charts/ontoserver-indexer/templates/job.yaml`

**Step 1: Append failing tests**

```yaml
  - it: adds language.refset env vars for each forModule entry
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      languageRefsets.forModule.32506021000036107: "32570271000036106,900000000000509007"
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: language.refset.32506021000036107
            value: "32570271000036106,900000000000509007"

  - it: omits language.refset env vars when forModule empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - notContains:
          path: spec.template.spec.containers[0].env
          content:
            name: language.refset.32506021000036107

  - it: adds resolveSkew env var when set
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      resolveSkew: "20231130"
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: snomed.editions.resolveSkew
            value: "20231130"

  - it: omits resolveSkew env var when empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - notContains:
          path: spec.template.spec.containers[0].env
          content:
            name: snomed.editions.resolveSkew

  - it: adds sentry env vars when sentry.dsn set
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
      sentry.dsn: https://key@sentry.example.com/1
      sentry.environment: Production
      sentry.serverName: my-indexer
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: sentry.dsn
            value: https://key@sentry.example.com/1
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: sentry.environment
            value: Production
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: sentry.servername
            value: my-indexer

  - it: omits sentry env vars when sentry.dsn empty
    set:
      codeSystem.url: http://snomed.info/sct/32506021000036107
      codeSystem.version: http://snomed.info/sct/32506021000036107/version/20231130
      rf2.files[0]: https://example.com/snomed.zip
      syndication.endpoint: https://synd.example.com
      syndication.tokenEndpoint: https://auth.example.com/token
      syndication.feed: my-feed
      syndication.entryTitle: My Entry
    asserts:
      - notContains:
          path: spec.template.spec.containers[0].env
          content:
            name: sentry.dsn
```

**Step 2: Run — expect new tests fail**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 3: Add optional env vars to job.yaml env section**

```
            {{- range $moduleId, $refsetIds := .Values.languageRefsets.forModule }}
            - name: language.refset.{{ $moduleId }}
              value: {{ $refsetIds | quote }}
            {{- end }}
            {{- if .Values.resolveSkew }}
            - name: snomed.editions.resolveSkew
              value: {{ .Values.resolveSkew | quote }}
            {{- end }}
            {{- if .Values.sentry.dsn }}
            - name: sentry.dsn
              value: {{ .Values.sentry.dsn | quote }}
            - name: sentry.environment
              value: {{ .Values.sentry.environment | quote }}
            - name: sentry.servername
              value: {{ .Values.sentry.serverName | quote }}
            {{- end }}
```

**Step 4: Run — expect all tests pass**

```bash
helm unittest charts/ontoserver-indexer
```

**Step 5: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: add optional env vars (languageRefsets, resolveSkew, sentry)"
```

---

## Task 9: Example values file and final smoke test

**Files:**
- Create: `charts/ontoserver-indexer/examples/snomed-au.yaml`

**Step 1: Create examples/snomed-au.yaml**

```yaml
# examples/snomed-au.yaml
# Index SNOMED CT AU and publish to a syndication feed.
#
# Usage:
#   helm install snomed-au-index ./charts/ontoserver-indexer \
#     -f charts/ontoserver-indexer/examples/snomed-au.yaml \
#     --set auth.oauth2.secretRef=your-secret

image:
  repository: quay.io/aehrc/ontoserver
  tag: ctsa-6

job:
  activeDeadlineSeconds: 14400   # 4 hours — full AU release can take time

resources:
  memoryGb: 20

codeSystem:
  url: http://snomed.info/sct/32506021000036107
  version: http://snomed.info/sct/32506021000036107/version/20231130

rf2:
  kind: FULL
  files:
    - https://your-storage/SnomedCT_Australian_1000036_20231130.zip

syndication:
  endpoint: https://your-syndication-server
  tokenEndpoint: https://your-auth-server/oauth/token
  feed: ncts-syndication
  entryTitle: "SNOMED CT AU November 2023 release"
  securityLabels:
    - http://snomed.info/sct/32506021000036107

# Provide credentials via an existing Secret with keys: clientId, clientSecret
# Create it with: kubectl create secret generic snomed-indexer-oauth \
#   --from-literal=clientId=YOUR_CLIENT_ID \
#   --from-literal=clientSecret=YOUR_CLIENT_SECRET
auth:
  oauth2:
    secretRef: snomed-indexer-oauth

languageRefsets:
  forModule:
    "32506021000036107": "32570271000036106,900000000000509007"

# sentry:
#   dsn: ""
#   environment: "Indexer"
```

**Step 2: Smoke test — helm lint and template render**

```bash
helm lint charts/ontoserver-indexer
helm template test-release charts/ontoserver-indexer -f charts/ontoserver-indexer/examples/snomed-au.yaml \
  --set auth.oauth2.secretRef=snomed-indexer-oauth
```

Expected: clean lint, valid YAML output with Job and no Secret (secretRef used).

**Step 3: Run full test suite one final time**

```bash
helm unittest charts/ontoserver-indexer
```

Expected: all tests pass.

**Step 4: Commit**

```bash
git add charts/ontoserver-indexer/
git commit -m "feat: add snomed-au example and complete ontoserver-indexer chart"
```
