# ontoserver-indexer Helm Chart Design

**Date:** 2026-03-08

## Overview

A new standalone Helm chart `charts/ontoserver-indexer` that creates a raw Kubernetes `batch/v1 Job` to index a SNOMED CT (or other) code system and publish the result to a syndication server. It does not require the ontoserver-indexing-operator — the Job is created directly by Helm.

The design mirrors the behaviour of the operator's `OntoserverIndexJobReconciler` but exposes the configuration as Helm values.

---

## Chart Structure

```
charts/ontoserver-indexer/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── job.yaml               # batch/v1 Job
│   ├── secret.yaml            # only rendered when inline auth credentials provided
│   └── validate-values.yaml   # fails fast on missing/conflicting values
└── examples/
    └── snomed-au.yaml         # realistic SNOMED CT AU worked example
```

---

## values.yaml Shape

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
  tokenEndpoint: ""         # OAuth token URL (required for OAuth2 auth)
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

  # All fields empty = no auth (valid when syndication endpoint is unauthenticated)

languageRefsets:
  forModule: {}             # map of moduleId -> comma-separated refset IDs
                            # e.g. "32506021000036107": "32570271000036106,900000000000509007"

resolveSkew: ""             # optional — e.g. "20231130"

sentry:                     # entirely optional — all fields ignored if sentry.dsn is empty
  dsn: ""
  environment: "Indexer"
  serverName: ""
```

---

## Job Template Design

### Container command

The container runs `/run.sh` with args assembled as a list (each flag and value is a separate entry — no shell quoting required, Helm `| quote` used for YAML safety only):

```
indexCodeSystemDebug
-s  <codeSystem.url>
-v  <codeSystem.version>
-f  <rf2.files[0]>  [-f <rf2.files[1]> ...]    # one -f per file
-k  <rf2.kind | lower>
-synd <syndication.endpoint>
-feed <syndication.feed>
-t  <syndication.entryTitle>
[-file <syndication.entryFileName>]              # omitted if empty
[-perms <label> ...]                             # one -perms per security label
```

### Environment variables

| Variable | Source | Condition |
|---|---|---|
| `JAVA_OPTS` | `-Xmx{{ resources.memoryGb }}g` | always |
| `authentication.oauth.endpoint.0` | `syndication.endpoint` | oauth2 auth |
| `authentication.oauth.endpoint.token_endpoint.0` | `syndication.tokenEndpoint` | oauth2 auth |
| `authentication.oauth.endpoint.strategy.0` | hardcoded `body` | oauth2 auth |
| `authentication.oauth.endpoint.client_id.0` | `secretKeyRef` | oauth2 auth |
| `authentication.oauth.endpoint.client_secret.0` | `secretKeyRef` | oauth2 auth |
| `authentication.basic.endpoint.0` | `syndication.endpoint` | basic auth |
| `authentication.basic.endpoint.user.0` | `secretKeyRef` | basic auth |
| `authentication.basic.endpoint.password.0` | `secretKeyRef` | basic auth |
| `snomed.editions.resolveSkew` | `resolveSkew` | if non-empty |
| `language.refset.<moduleId>` | `languageRefsets.forModule[moduleId]` | per entry |
| `sentry.dsn` | `sentry.dsn` | if sentry.dsn non-empty |
| `sentry.environment` | `sentry.environment` | if sentry.dsn non-empty |
| `sentry.servername` | `sentry.serverName` | if sentry.dsn non-empty |

### Resources

`requests.memory` and `limits.memory` both set to `{{ resources.memoryGb }}G`, matching `-Xmx`.

### Job spec

- `backoffLimit: 0` — no retries
- `restartPolicy: Never`
- `activeDeadlineSeconds`: from `job.activeDeadlineSeconds`
- `ttlSecondsAfterFinished`: from `job.ttlSecondsAfterFinished`

---

## Secret Template

Rendered only when inline credentials are provided (`auth.oauth2.clientId` or `auth.basic.username`). Creates a Secret with the appropriate keys (`clientId`/`clientSecret` or `username`/`password`). Auth env vars reference this Secret via `secretKeyRef`.

---

## Validation Rules (`validate-values.yaml`)

| Check | Error |
|---|---|
| `codeSystem.url` empty | `codeSystem.url is required` |
| `codeSystem.version` empty | `codeSystem.version is required` |
| `rf2.files` empty | `rf2.files must contain at least one URL` |
| `rf2.kind` not FULL/SNAPSHOT/DELTA | `rf2.kind must be one of: FULL, SNAPSHOT, DELTA` |
| `syndication.endpoint` empty | `syndication.endpoint is required` |
| `syndication.tokenEndpoint` empty | `syndication.tokenEndpoint is required` |
| `syndication.feed` empty | `syndication.feed is required` |
| `syndication.entryTitle` empty | `syndication.entryTitle is required` |
| Both `auth.oauth2` and `auth.basic` configured | `auth.oauth2 and auth.basic are mutually exclusive` |
| Within oauth2: both `secretRef` and `clientId` set | `auth.oauth2.secretRef and auth.oauth2.clientId are mutually exclusive` |
| Within basic: both `secretRef` and `username` set | `auth.basic.secretRef and auth.basic.username are mutually exclusive` |

No auth configured (all auth fields empty) is valid — the syndication endpoint may not require authentication.

---

## Example Values File (`examples/snomed-au.yaml`)

A realistic SNOMED CT AU indexing run:

```yaml
image:
  repository: quay.io/aehrc/ontoserver
  tag: ctsa-6

job:
  activeDeadlineSeconds: 14400   # 4 hours for a full AU release

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

auth:
  oauth2:
    secretRef: snomed-indexer-oauth   # Secret with keys: clientId, clientSecret

languageRefsets:
  forModule:
    "32506021000036107": "32570271000036106,900000000000509007"

# sentry:
#   dsn: ""
#   environment: "Indexer"
```

---

## References

- Operator job creation: `/Users/ede020/work/ontoserver-indexing-operator/src/main/java/com/csiro/aehrc/OntoserverIndexJobReconciler.java`
- Indexer command: `/Users/ede020/work/ontoserver4/src/main/java/au/csiro/ontoserver/CodeSystemIndexer.java`
- Indexer Spring profile: `/Users/ede020/work/ontoserver4/src/main/jib/application-indexer.properties`
- Language refset config: `/Users/ede020/work/ontoserver4/src/main/resources/config/application.properties`
