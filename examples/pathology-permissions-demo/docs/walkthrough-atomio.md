# Atomio Variant Walkthrough

This guide walks through the Atomio variant of the pathology permissions demo, demonstrating release candidate management and the content promotion pipeline.

## Prerequisites

- Docker and Docker Compose running
- Access to `quay.io/aehrc` container images
- `curl`, `jq`, `python3` installed
- Ports 9081, 9083-9085, 9090 available

> **Windows users:** Run inside [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) (Windows Subsystem for Linux). Install Docker Desktop with the WSL2 backend enabled, then run all commands from a WSL2 terminal. The shell scripts, `curl`, `jq`, and `python3` all work natively in WSL2.

## Setup

From the demo root directory:

```bash
./demo.sh setup atomio
```

Or directly from the variant directory:

```bash
cd atomio/
chmod +x scripts/*.sh
./scripts/setup.sh
```

The setup takes approximately 8 minutes. It starts Ontocloak, extracts RSA keys, starts Ontoserver and Atomio instances, creates communities, assigns users, loads sample resources, creates the initial release candidate, and starts UAT and production.

> **Tip:** The setup script offers a manual option `[m]` for Ontocloak configuration. Choose this to experience community creation and user group assignment through the admin UI.

## Web Tools

These cloud-hosted tools connect to your local servers via the `?iss=` and `&clientId=` parameters:

| Tool | Purpose | URL |
|------|---------|-----|
| **Shrimp** | Browse CodeSystem and ValueSet content | `https://ontoserver.csiro.au/shrimp` |
| **Snapper** | Edit CodeSystems, ConceptMaps, ValueSets | `https://ontoserver.csiro.au/snapper` |
| **OntoCommand** | Admin dashboard — loaded resources and metadata | `https://ontoserver.csiro.au/ui` |
| **Atomio UI** | Release management — feeds, aliases, promotion | `https://ontoserver.csiro.au/atomio/` |

Server connections (append the appropriate `clientId` for the tool — `shrimp`, `snapper`, `onto-ui`, or `atomio-ui`):
- **Authoring**: append `?iss=https://localhost:9081&clientId=<tool>`
- **Atomio**: open `https://localhost:9083` (redirects to Atomio UI)
- **UAT**: append `?iss=https://localhost:9084&clientId=<tool>`
- **Production**: append `?iss=https://localhost:9085&clientId=<tool>`

Demo users (all passwords: **`demo`**):
`admin`, `alpha-viewer`, `alpha-author`, `alpha-approver`, `beta-viewer`, `beta-author`, `beta-approver`, `national-admin`

## Part 1: Understanding Atomio Feeds and Aliases

### 1.1 Review Current State

**Using Atomio UI:**

1. Open the Atomio UI:
   `https://localhost:9083`
2. Browse **Feeds** — you should see:
   - `release-1-0` — the initial release candidate (cloned from authoring)
   - `gamma-content` — dedicated feed for Pathology Gamma's CSV-sourced content
3. Browse **Aliases** — both `uat` and `production` point to `release-1-0`

**Using curl:**

```bash
# List feeds
curl -sk https://localhost:9083/feed | jq '.[] | {name: .name, title: .title}'

# List aliases
curl -sk https://localhost:9083/alias | jq '.[] | {alias: .aliasName, feed: .feedName}'

# View feed contents as Atom XML (what Ontoserver consumes)
curl -sk https://localhost:9083/feed/release-1-0/syndication.xml | head -30
```

> Atomio also has a Swagger UI at `https://localhost:9083/swagger-ui/index.html` for interactive API exploration.

> **Atomio Security:** Atomio has security enabled. All write operations (clone, alias update) require authentication via a Bearer token. Read operations (list feeds, list aliases, view feed content) are publicly accessible without authentication.

## Part 2: Resource Isolation

Resource-level permissions work identically to the simple variant. The key difference is how content flows to downstream environments.

### 2.1 Anonymous Access

**Using Shrimp:**

1. Open Shrimp pointed at production (no login):
   `https://ontoserver.csiro.au/shrimp?iss=https://localhost:9085&clientId=shrimp`
2. The **CodeSystems** list is empty — all CodeSystems have community labels
3. Switch to **ValueSets** — the **National Pathology Reference Set** is visible (`*.read` label)

**Using curl:**

```bash
# National valueset visible anonymously on production
curl -sk https://localhost:9085/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset \
  | jq '.total'
# Output: 1
```

### 2.2 Community Isolation

**Using Shrimp:**

1. Open Shrimp pointed at authoring:
   `https://ontoserver.csiro.au/shrimp?iss=https://localhost:9081&clientId=shrimp`
2. Log in as **alpha-author** / **demo** — see Alpha CodeSystem + national content
3. **Log out**, log in as **beta-author** / **demo** — see Beta CodeSystem + national content
4. **Log out**, log in as **admin** / **demo** — see all CodeSystems

> Same server, same URL — the resource list changes based on who is logged in.

**Using curl:**

```bash
ALPHA_TOKEN=$(curl -sk -X POST \
  https://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=alpha-author&password=demo" \
  | jq -r '.access_token')

# Alpha sees only Alpha resources
curl -sk -H "Authorization: Bearer $ALPHA_TOKEN" \
  https://localhost:9081/fhir/CodeSystem \
  | jq '[.entry[].resource | {url: .url, title: .title}]'
```

## Part 3: The Release Candidate Workflow

This is the core Atomio workflow: author changes, create a release candidate, promote through environments.

### 3.1 Author Blocked on Published Resource

Published (syndicated) resources are protected by `secureSyndicated`. Authors cannot modify them — this prevents accidental changes to production-published content.

**Using curl:**

```bash
# Try to modify the published CodeSystem 1.0.0 as alpha-author
CURRENT=$(curl -sk -H "Authorization: Bearer $ALPHA_TOKEN" \
  https://localhost:9081/fhir/CodeSystem/alpha-pathology-codes)

MODIFIED=$(echo "$CURRENT" | jq '.description = .description + " (modified)"')

curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X PUT \
  https://localhost:9081/fhir/CodeSystem/alpha-pathology-codes \
  -H "Authorization: Bearer $ALPHA_TOKEN" \
  -H "Content-Type: application/fhir+json" \
  -d "$MODIFIED"
# Output: HTTP 403
```

> The author has `FHIR_WRITE` but not `SYND_WRITE`. The `secureSyndicated` setting requires `SYND_WRITE` to modify syndicated resources.

### 3.2 Author Creates New Business Version

Instead of modifying the published resource, the author creates a new version — a separate FHIR resource instance with version 1.1.0.

**Using curl:**

```bash
# Get the published 1.0.0 as a starting point
CURRENT=$(curl -sk -H "Authorization: Bearer $ALPHA_TOKEN" \
  https://localhost:9081/fhir/CodeSystem/alpha-pathology-codes)

# Create version 1.1.0 with a new concept
NEW_VERSION=$(echo "$CURRENT" | jq '
  .id = "alpha-pathology-codes-v1-1-0"
  | .version = "1.1.0"
  | .concept += [{"code":"TROP","display":"Troponin","definition":"High-sensitivity troponin for cardiac markers"}]
  | .count = (.concept | length)
  | del(.meta.versionId, .meta.lastUpdated)
')

curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X PUT \
  https://localhost:9081/fhir/CodeSystem/alpha-pathology-codes-v1-1-0 \
  -H "Authorization: Bearer $ALPHA_TOKEN" \
  -H "Content-Type: application/fhir+json" \
  -d "$NEW_VERSION"
# Output: HTTP 201
```

> The new version is a draft — no syndication status. It won't appear in the syndication feed until approved.

### 3.3 Approver Publishes New Version

The approver sets syndication status on the new version, making it available in the syndication feed.

**Using curl:**

```bash
APPROVER_TOKEN=$(curl -sk -X POST \
  https://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=alpha-approver&password=demo" \
  | jq -r '.access_token')

curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X POST \
  "https://localhost:9081/synd/setSyndicationStatus?resourceType=CodeSystem&id=alpha-pathology-codes-v1-1-0&syndicate=true" \
  -H "Authorization: Bearer $APPROVER_TOKEN"
# Output: HTTP 200
```

> The new version 1.1.0 is now in the syndication feed. The next Atomio clone will include it.

### 3.4 Create a New Release Candidate

**Using Atomio UI:**

1. Open the Atomio UI:
   `https://localhost:9083`
2. Create a new feed by cloning the authoring syndication feed
3. Name it `release-2-0`
4. Verify both `release-1-0` and `release-2-0` appear in the feeds list

**Using curl:**

```bash
# Get an admin token for Atomio write operations
ADMIN_TOKEN=$(curl -sk -X POST \
  https://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=admin&password=demo" \
  | jq -r '.access_token')

# Clone authoring's syndication feed into a new snapshot
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X POST \
  "https://localhost:9083/feed/\$clone?name=release-2-0&url=http://authoring-ontoserver:8080/synd/syndication.xml" \
  -H "Authorization: Bearer $ADMIN_TOKEN"

# Verify both feeds exist
curl -sk https://localhost:9083/feed | jq '.[].name'
# "release-1-0"
# "release-2-0"
```

> Feed names must match `^[A-Za-z0-9-_]+$` (no dots). Use `release-2-0` not `release-2.0`.

### 3.5 Promote to UAT

**Using Atomio UI:**

1. In the Atomio UI, go to **Aliases**
2. Edit the `uat` alias to point to `release-2-0`
3. Verify: `uat` → `release-2-0`, `production` → `release-1-0`

**Using curl:**

```bash
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X PUT \
  https://localhost:9083/alias/uat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"aliasName": "uat", "feedName": "release-2-0"}'

# Verify
curl -sk https://localhost:9083/alias | jq '.[] | {alias: .aliasName, feed: .feedName}'
```

**Result**: UAT points to `release-2-0` (new content), production still on `release-1-0`.

The UAT Ontoserver polls every 2 minutes. After waiting, verify the new content:

**Using Shrimp:**

1. Open Shrimp pointed at UAT:
   `https://ontoserver.csiro.au/shrimp?iss=https://localhost:9084&clientId=shrimp`
2. Log in as **alpha-author** — check that the Troponin concept appears

**Using curl:**

```bash
curl -sk https://localhost:9084/fhir/CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes \
  | jq '.entry[0].resource.version // "not synced yet"'
```

### 3.6 Production Still Has the Old Content

**Using Shrimp:**

1. Open Shrimp pointed at production:
   `https://ontoserver.csiro.au/shrimp?iss=https://localhost:9085&clientId=shrimp`
2. Log in as **alpha-author** — the Troponin concept is **not yet present**

**Using curl:**

```bash
curl -sk https://localhost:9085/fhir/CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes \
  | jq '.entry[0].resource.version // "not found"'
```

### 3.7 Promote to Production

After UAT testing, promote to production:

**Using Atomio UI:**

1. In the Atomio UI, edit the `production` alias to point to `release-2-0`
2. Both aliases now point to the same feed

**Using curl:**

```bash
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X PUT \
  https://localhost:9083/alias/production \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"aliasName": "production", "feedName": "release-2-0"}'

# Verify
curl -sk https://localhost:9083/alias | jq '.[] | {alias: .aliasName, feed: .feedName}'
```

> The production Ontoserver polls every 2 minutes and automatically picks up the new content. No restart needed.

### 3.8 Rollback

If issues are found, rollback is instant — repoint the alias to the previous feed:

**Using Atomio UI:**

1. Edit the `production` alias back to `release-1-0`
2. UAT continues testing `release-2-0` independently

**Using curl:**

```bash
# Rollback production to release-1-0
curl -sk -o /dev/null -w "HTTP %{http_code}\n" -X PUT \
  https://localhost:9083/alias/production \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -d '{"aliasName": "production", "feedName": "release-1-0"}'

# UAT stays on release-2-0
curl -sk https://localhost:9083/alias | jq '.[] | {alias: .aliasName, feed: .feedName}'
# {"alias":"uat","feed":"release-2-0"}
# {"alias":"production","feed":"release-1-0"}
```

> All feed snapshots are **immutable** and preserved. Rollback is instant — no rebuild, no re-syndication.

## Part 4: CSV-to-FHIR Pipeline

### 4.1 Review CSV Source Data

Pathology Gamma maintains codes in CSV files under version control:

```bash
head -5 ../common/csv-data/gamma-codes.csv
head -5 ../common/csv-data/gamma-mappings.csv
```

### 4.2 Transform to FHIR

The setup script runs this automatically, but you can re-run manually:

```bash
python3 ../common/scripts/csv-transform.py \
  --codes ../common/csv-data/gamma-codes.csv \
  --mappings ../common/csv-data/gamma-mappings.csv \
  --output-dir ./generated \
  --security-label GAMMA \
  --codesystem-url http://pathology-gamma.example.com/CodeSystem/pathology-codes \
  --conceptmap-url http://pathology-gamma.example.com/ConceptMap/pathology-to-national \
  --target-valueset http://example.org/ValueSet/national-pathology-refset \
  --publisher "Pathology Gamma"
```

### 4.3 Verify CSV Content

**Using Shrimp:**

1. Open Shrimp (authoring), log in as **admin**
2. Browse CodeSystems — find **Pathology Gamma** (15 concepts from CSV)
3. Explore the codes: GLU-R, GLU-F, HBA1C, CHOL-T, TSH, etc.
4. **Log out**, log in as **alpha-author** — Gamma CodeSystem **disappears** (requires `PERM_GAMMA_READ`)

**Using curl:**

```bash
jq '{url: .url, count: .count, security: [.meta.security[].code]}' generated/gamma-pathology-codes.json
```

> In a CI/CD pipeline, the CSV transform and upload would be automated. The generated resources can be uploaded directly to an Atomio feed or to the authoring server.

## Part 5: Comparing Environments

### 5.1 Using OntoCommand

1. Open OntoCommand for each environment and compare loaded resources:
   - **Authoring**: `https://ontoserver.csiro.au/ui?iss=https://localhost:9081&clientId=onto-ui`
   - **UAT**: `https://ontoserver.csiro.au/ui?iss=https://localhost:9084&clientId=onto-ui`
   - **Production**: `https://ontoserver.csiro.au/ui?iss=https://localhost:9085&clientId=onto-ui`
2. Log in as **admin** on each to see the full resource inventory
3. Compare versions — UAT and production reflect whichever Atomio feed their alias points to

### 5.2 Security Labels Apply Everywhere

**Using Shrimp:**

1. Open Shrimp pointed at UAT:
   `https://ontoserver.csiro.au/shrimp?iss=https://localhost:9084&clientId=shrimp`
2. Log in as **alpha-author** — see only Alpha resources + national
3. **Log out**, log in as **beta-author** — see only Beta resources + national

> Security labels are preserved through syndication via Atomio. Community isolation applies on every downstream server.

**Using curl:**

```bash
# Authenticated Alpha user on UAT
ALPHA_TOKEN=$(curl -sk -X POST \
  https://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=alpha-viewer&password=demo" \
  | jq -r '.access_token')

# Alpha sees their resources on UAT
curl -sk -H "Authorization: Bearer $ALPHA_TOKEN" \
  https://localhost:9084/fhir/CodeSystem \
  | jq '[.entry[].resource | {url: .url, title: .title}]'

# Alpha cannot see Beta's resources on UAT
curl -sk -H "Authorization: Bearer $ALPHA_TOKEN" \
  https://localhost:9084/fhir/CodeSystem?url=http://pathology-beta.example.com/CodeSystem/pathology-codes \
  | jq '.total'
# Output: 0
```

## Automated Walkthrough Scripts

### Terminal Walkthrough (curl)

Runs curl commands with explanations in the terminal:

```bash
./scripts/demo-workflow.sh
```

### Visual Walkthrough (Playwright)

Opens a browser and drives through Shrimp, Snapper, OntoCommand, and the Atomio UI with narrated steps and pause points in the terminal. Requires Node.js and a running demo environment (run `./scripts/setup.sh` first).

```bash
cd ../tests/e2e
npm install && npm run install-browsers  # first time only
npm run walkthrough:atomio
```

This launches a visible Chromium window and walks through all 12 scenes — 8 shared scenes plus 4 Atomio-specific scenes:
1. Anonymous Access
2. Alpha Community
3. Beta Community
4. Admin Full Access
5. Viewer vs Author Roles
6. Upload and Syndication
7. Approve Resources
8. ConceptMaps
9. Atomio — Clone Release Candidate
10. Atomio — Promote to UAT
11. Atomio — Promote to Production
12. CSV-to-FHIR Pipeline — Gamma Content

Press Enter at each pause point to advance. If a scene fails, you can retry, skip, or quit.

## Helper Scripts

### Create Release Candidate

```bash
# Create a new release
./scripts/create-release-candidate.sh release-3-0

# Create and immediately promote to UAT
./scripts/create-release-candidate.sh release-3-0 --promote-to uat

# Create and promote to production
./scripts/create-release-candidate.sh release-3-0 --promote-to production
```

## Resetting the Environment

The walkthrough modifies server state (e.g., creates new resource versions, sets syndication status, clones feeds). To run the demo again from a clean state, you must tear down and re-run setup:

```bash
# From the demo root directory:
./demo.sh teardown atomio     # Stops containers, deletes volumes and generated files
./demo.sh setup atomio        # Re-run setup from scratch (~8 minutes)
```

Or directly from the variant directory:

```bash
cd atomio/
docker compose down -v        # Stop containers and delete all data volumes
rm -rf generated/ .env        # Remove generated files and environment config
./scripts/setup.sh            # Re-run setup from scratch (~8 minutes)
```

> **Important:** `docker compose down` without `-v` preserves the database and Atomio volumes, so leftover resources and feeds from a previous demo run will still be present. Always use `-v` to get a clean slate.

## Troubleshooting

### Atomio feed clone fails?

Ensure the authoring server's syndication feed is populated:
```bash
curl -sk https://localhost:9081/synd/syndication.xml | head -5
```

### UAT/Production not syncing?

Check alias configuration and feed contents:
```bash
curl -sk https://localhost:9083/alias | jq .
curl -sk https://localhost:9083/feed/release-1-0 | jq '.entries | length'
docker compose logs uat-ontoserver | grep -i "synd\|preload\|feed"
```

### Token errors?

```bash
curl -sk https://localhost:9090/auth/health/ready
```
