# Simple Example Walkthrough

This guide walks through the simple variant of the pathology permissions demo, demonstrating resource-level permissions with direct syndication from authoring to production.

## Prerequisites

- Docker and Docker Compose running
- Access to `quay.io/aehrc` container images
- `curl`, `jq`, `python3` installed
- Ports 9081, 9082, 9090 available

> **Windows users:** Run inside [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) (Windows Subsystem for Linux). Install Docker Desktop with the WSL2 backend enabled, then run all commands from a WSL2 terminal. The shell scripts, `curl`, `jq`, and `python3` all work natively in WSL2.

## Setup

From the demo root directory:

```bash
./demo.sh setup simple
```

Or directly from the variant directory:

```bash
cd simple/
chmod +x scripts/*.sh
./scripts/setup.sh
```

The setup script takes approximately 5 minutes. It starts Ontocloak, extracts RSA keys, starts Ontoserver instances, creates communities, assigns users to groups, and loads sample FHIR resources.

> **Tip:** The setup script offers a manual option `[m]` for Ontocloak configuration. Choose this to experience community creation and user group assignment through the admin UI.

## Web Tools

These cloud-hosted tools connect to your local servers via the `?iss=` parameter:

| Tool | Purpose | URL |
|------|---------|-----|
| **Shrimp** | Browse CodeSystem and ValueSet content | `https://ontoserver.csiro.au/shrimp` |
| **Snapper** | Edit CodeSystems, ConceptMaps, ValueSets | `https://ontoserver.csiro.au/snapper` |
| **OntoCommand** | Admin dashboard — loaded resources and metadata | `https://ontoserver.csiro.au/ui` |

Server connections:
- **Authoring**: append `?iss=http://localhost:9081`
- **Production**: append `?iss=http://localhost:9082`

Demo users (all passwords: **`demo`**):
`admin`, `alpha-viewer`, `alpha-author`, `alpha-approver`, `beta-viewer`, `beta-author`, `beta-approver`, `national-admin`

## Part 1: Exploring Resource Isolation

### 1.1 Anonymous Access

Without logging in, only resources with `*.read` security labels (shared national content) are visible. Community-labeled resources are silently filtered.

**Using Shrimp:**

1. Open Shrimp pointed at production (no login required):
   `https://ontoserver.csiro.au/shrimp?iss=http://localhost:9082`
2. The **CodeSystems** list is empty — all CodeSystems have community labels
3. Switch to **ValueSets** — you'll see the **National Pathology Reference Set** (`*.read` label)

> Production has `readOnly.fhir=true`, so anonymous users get implicit `FHIR_READ`. But community-labeled resources (e.g., `ALPHA.read`) require the matching `PERM` role in a JWT — they are silently filtered.

**Using curl:**

```bash
# National valueset is visible anonymously on production (has *.read label)
curl -s http://localhost:9082/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset \
  | jq '.total, .entry[0].resource.title'
# Output: 1, "National Pathology Reference Set"

# Alpha's CodeSystem is NOT visible anonymously (has ALPHA.read label)
curl -s http://localhost:9081/fhir/CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes \
  | jq '.total'
# Output: 0
```

### 1.2 Log In as Alpha Author

**Using Shrimp:**

1. Open Shrimp pointed at authoring:
   `https://ontoserver.csiro.au/shrimp?iss=http://localhost:9081`
2. Click **Login** and authenticate as **alpha-author** / **demo**
3. Browse **CodeSystems** — you now see:
   - **Pathology Alpha Local Order Codes** (has `ALPHA.read` label)
   - The national content (`*.read`)
4. Search for "Beta" or "Gamma" CodeSystems — **nothing appears**

> alpha-author's token has `PERM_ALPHA_READ`. Resources labeled `BETA.read` or `GAMMA.read` are silently filtered.

**Using curl:**

```bash
ALPHA_TOKEN=$(curl -s -X POST \
  http://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=alpha-author&password=demo" \
  | jq -r '.access_token')

# Alpha sees only their CodeSystem
curl -s -H "Authorization: Bearer $ALPHA_TOKEN" \
  http://localhost:9081/fhir/CodeSystem \
  | jq '[.entry[].resource | {url: .url, title: .title}]'

# Alpha cannot see Beta's resources
curl -s -H "Authorization: Bearer $ALPHA_TOKEN" \
  http://localhost:9081/fhir/CodeSystem?url=http://pathology-beta.example.com/CodeSystem/pathology-codes \
  | jq '.total'
# Output: 0

# Alpha CAN see the national valueset (*.read)
curl -s -H "Authorization: Bearer $ALPHA_TOKEN" \
  http://localhost:9081/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset \
  | jq '.total'
# Output: 1
```

### 1.3 Same Server, Different Views

**Using Shrimp:**

1. **Log out**, then log in as **beta-author** / **demo**
2. Browse CodeSystems — see only **Pathology Beta** CodeSystem + national content
3. Alpha and Gamma are invisible
4. **Log out**, then log in as **admin** / **demo**
5. Browse CodeSystems — see **all three**: Alpha, Beta, Gamma + national content

> Same Shrimp URL, same server — the resource list changes based on who is logged in. The admin has `PERM_READ` (wildcard), so all community-labeled resources are visible.

**Using curl:**

```bash
# Beta author sees only Beta resources
BETA_TOKEN=$(curl -s -X POST \
  http://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=beta-author&password=demo" \
  | jq -r '.access_token')

curl -s -H "Authorization: Bearer $BETA_TOKEN" \
  http://localhost:9081/fhir/CodeSystem \
  | jq '[.entry[].resource | {url: .url, title: .title}]'

# Admin sees everything
ADMIN_TOKEN=$(curl -s -X POST \
  http://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=admin&password=demo" \
  | jq -r '.access_token')

curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://localhost:9081/fhir/CodeSystem \
  | jq '[.entry[].resource | {url: .url, title: .title}]'
```

## Part 2: Role-Based Access Control

### 2.1 Viewer vs Author

**Using Snapper:**

1. Open Snapper pointed at authoring:
   `https://ontoserver.csiro.au/snapper?iss=http://localhost:9081`
2. Log in as **alpha-viewer** / **demo**
3. Open the **Alpha CodeSystem** — you can **browse** it
4. Try to **edit** a concept (e.g., change a display name) — **Save fails** with 403
5. **Log out**, log in as **alpha-author** / **demo**
6. Open the same Alpha CodeSystem — now you **can edit and save**

> alpha-viewer has `PERM_ALPHA_READ` but lacks `PERM_ALPHA_WRITE`. The server returns 403 Forbidden on write attempts.

**Using curl:**

```bash
VIEWER_TOKEN=$(curl -s -X POST \
  http://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=alpha-viewer&password=demo" \
  | jq -r '.access_token')

# Viewer can read Alpha's CodeSystem
curl -s -H "Authorization: Bearer $VIEWER_TOKEN" \
  http://localhost:9081/fhir/CodeSystem?url=http://pathology-alpha.example.com/CodeSystem/pathology-codes \
  | jq '.total'
# Output: 1

# But cannot update it (gets 403)
curl -s -o /dev/null -w "%{http_code}" -X PUT \
  http://localhost:9081/fhir/CodeSystem/alpha-pathology-codes \
  -H "Authorization: Bearer $VIEWER_TOKEN" \
  -H "Content-Type: application/fhir+json" \
  -d '{"resourceType":"CodeSystem","id":"alpha-pathology-codes","url":"http://pathology-alpha.example.com/CodeSystem/pathology-codes","status":"active","content":"complete","concept":[{"code":"TEST","display":"Test"}]}'
# Output: 403
```

### 2.2 Author Blocked on Published Resource

Published (syndicated) resources are protected by the `secureSyndicated` setting. Authors have `FHIR_WRITE` but not `SYND_WRITE`, so they cannot modify resources that have been approved for syndication.

**Using curl:**

```bash
# Try to modify the published CodeSystem 1.0.0 as alpha-author
CURRENT=$(curl -s -H "Authorization: Bearer $ALPHA_TOKEN" \
  http://localhost:9081/fhir/CodeSystem/alpha-pathology-codes)

MODIFIED=$(echo "$CURRENT" | jq '.description = .description + " (modified)"')

curl -s -o /dev/null -w "%{http_code}" -X PUT \
  http://localhost:9081/fhir/CodeSystem/alpha-pathology-codes \
  -H "Authorization: Bearer $ALPHA_TOKEN" \
  -H "Content-Type: application/fhir+json" \
  -d "$MODIFIED"
# Output: 403
```

> The author has `PERM_ALPHA_WRITE` and `FHIR_WRITE`, but the resource has syndication status = true. Modifying a syndicated resource requires `SYND_WRITE` (the Approver role). This protects production-published content from accidental changes.

### 2.3 Author Creates New Business Version

Since published resources are locked, authors create new business versions instead. A new version is a separate FHIR resource instance with the same canonical URL but a new version number.

**Using curl:**

```bash
# Get the published 1.0.0 as a starting point
CURRENT=$(curl -s -H "Authorization: Bearer $ALPHA_TOKEN" \
  http://localhost:9081/fhir/CodeSystem/alpha-pathology-codes)

# Create a new version: new id, version 1.1.0, add D-Dimer concept
NEW_VERSION=$(echo "$CURRENT" | jq '
  .id = "alpha-pathology-codes-v1-1-0"
  | .version = "1.1.0"
  | .concept += [{"code":"D-DIM","display":"D-Dimer","definition":"D-dimer test for thrombosis screening"}]
  | .count = (.concept | length)
  | del(.meta.versionId, .meta.lastUpdated)
')

curl -s -o /dev/null -w "%{http_code}" -X PUT \
  http://localhost:9081/fhir/CodeSystem/alpha-pathology-codes-v1-1-0 \
  -H "Authorization: Bearer $ALPHA_TOKEN" \
  -H "Content-Type: application/fhir+json" \
  -d "$NEW_VERSION"
# Output: 201 (Created)
```

> The new version 1.1.0 is a draft — it has no syndication status and will not appear in the syndication feed until an approver publishes it.

### 2.4 Approver Publishes New Version

The approver has `SYND_WRITE` permission and can set syndication status to approve resources for publication.

**Using curl:**

```bash
APPROVER_TOKEN=$(curl -s -X POST \
  http://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=alpha-approver&password=demo" \
  | jq -r '.access_token')

# Set syndication status on the new version
curl -s -o /dev/null -w "%{http_code}" -X POST \
  "http://localhost:9081/synd/setSyndicationStatus?resourceType=CodeSystem&id=alpha-pathology-codes-v1-1-0&syndicate=true" \
  -H "Authorization: Bearer $APPROVER_TOKEN"
# Output: 200
```

> The new version 1.1.0 now appears in the syndication feed. Downstream servers (production) will pick it up on their next sync cycle (every 2 minutes).

### 2.5 Cross-Community Write Protection

An author from one community cannot modify another community's resources — even if they somehow know the resource URL.

**Using curl:**

```bash
# Alpha author tries to modify Beta's CodeSystem — gets 403
curl -s -o /dev/null -w "%{http_code}" -X PUT \
  http://localhost:9081/fhir/CodeSystem/beta-pathology-codes \
  -H "Authorization: Bearer $ALPHA_TOKEN" \
  -H "Content-Type: application/fhir+json" \
  -d '{"resourceType":"CodeSystem","id":"beta-pathology-codes","url":"http://pathology-beta.example.com/CodeSystem/pathology-codes","status":"active","content":"complete","concept":[{"code":"HACK","display":"Hacked"}]}'
# Output: 403
```

## Part 3: Viewing ConceptMaps

### 3.1 Alpha's Mapping to National Standard

**Using Snapper:**

1. In Snapper (authoring), logged in as **alpha-author**
2. Navigate to **ConceptMaps**
3. Open **Alpha Local Codes to National Standard** — see mappings from local codes to national standard codes
4. Try searching for Beta's ConceptMap — **not visible**

> Snapper shows ConceptMap content that Shrimp does not (Shrimp focuses on CodeSystems and ValueSets).

**Using curl:**

```bash
curl -s -H "Authorization: Bearer $ALPHA_TOKEN" \
  http://localhost:9081/fhir/ConceptMap/alpha-pathology-to-national \
  | jq '{
    title: .title,
    source: .sourceUri,
    target: .targetUri,
    mappings: [.group[0].element[:5][] | {
      local: .code,
      national: .target[0].code,
      equivalence: .target[0].equivalence
    }]
  }'
```

## Part 4: Syndication to Production

### 4.1 Verify Content on Production

**Using OntoCommand:**

1. Open OntoCommand pointed at authoring:
   `https://ontoserver.csiro.au/ui?iss=http://localhost:9081`
2. Log in as **admin** — see all loaded resources and their metadata
3. Open OntoCommand pointed at production:
   `https://ontoserver.csiro.au/ui?iss=http://localhost:9082`
4. Compare — production has the **same resources** (synced every 2 minutes)

**Using Shrimp:**

1. Open Shrimp pointed at production:
   `https://ontoserver.csiro.au/shrimp?iss=http://localhost:9082`
2. Log in as **alpha-author** — see the same Alpha resources that were on authoring
3. Security labels are **preserved** through syndication — end users still only see what their token allows

**Using curl:**

```bash
# Check national valueset on production
curl -s http://localhost:9082/fhir/ValueSet?url=http://example.org/ValueSet/national-pathology-refset \
  | jq '.total'
# Output: 1

# Authenticated Alpha user sees their resources on production too
ALPHA_PROD_TOKEN=$(curl -s -X POST \
  http://localhost:9090/auth/realms/pathology-demo/protocol/openid-connect/token \
  -d "grant_type=password&client_id=demo-cli&username=alpha-viewer&password=demo" \
  | jq -r '.access_token')

curl -s -H "Authorization: Bearer $ALPHA_PROD_TOKEN" \
  http://localhost:9082/fhir/CodeSystem \
  | jq '[.entry[].resource | {url: .url, title: .title}]'
```

> Production uses the `syndication-consumer` service account (OAuth2 client credentials with `PERM_READ`) to download **all** community-labeled resources. Security labels are preserved — end users on production still only see what their token allows.

## Part 5: CSV-to-FHIR Pipeline

### 5.1 Review CSV Source Data

Pathology Gamma maintains codes in CSV files under version control:

```bash
head -5 ../common/csv-data/gamma-codes.csv
head -5 ../common/csv-data/gamma-mappings.csv
```

### 5.2 Transform and Load

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

### 5.3 Verify CSV Content

**Using Shrimp:**

1. Open Shrimp (authoring), log in as **admin**
2. Browse CodeSystems — find **Pathology Gamma** (15 concepts from CSV)
3. Explore the codes: GLU-R, GLU-F, HBA1C, CHOL-T, TSH, etc.
4. **Log out**, log in as **alpha-author** — Gamma CodeSystem **disappears** (requires `PERM_GAMMA_READ`)

**Using curl:**

```bash
jq '{url: .url, count: .count, security: [.meta.security[].code]}' generated/gamma-pathology-codes.json
```

> In a CI/CD pipeline, the CSV transform and upload would be automated — Git push triggers transform and upload to the authoring server.

## Automated Walkthrough Scripts

### Terminal Walkthrough (curl)

Runs curl commands with explanations in the terminal:

```bash
./scripts/demo-workflow.sh
```

### Visual Walkthrough (Playwright)

Opens a browser and drives through Shrimp, Snapper, and OntoCommand with narrated steps and pause points in the terminal. Requires Node.js and a running demo environment (run `./scripts/setup.sh` first).

```bash
cd ../tests/e2e
npm install && npm run install-browsers  # first time only
npm run walkthrough
```

This launches a visible Chromium window and walks through:
1. Anonymous access on production (Shrimp) — only national content visible
2. Alpha author — community isolation (Shrimp on authoring)
3. Beta author — same server, different view
4. Admin — wildcard permissions, sees all resources
5. Viewer vs author — read-only access in Snapper (alpha-viewer)
6. Author permissions — write but not syndicate (shows write gate on published resources, then creates and uploads version 1.1.0 via Snapper UI)
7. Approver publishes new version (sets syndication status on 1.1.0)
8. ConceptMaps — community isolation for all resource types
9. Syndication — content flows to production (Shrimp on production as admin)
10. CSV-to-FHIR pipeline — Gamma content (Shrimp on authoring as admin)

Press Enter at each pause point to advance. If a scene fails, you can retry, skip, or quit.

## Resetting the Environment

The walkthrough modifies server state (e.g., creates new resource versions, sets syndication status). To run the demo again from a clean state, you must tear down and re-run setup:

```bash
# From the demo root directory:
./demo.sh teardown simple     # Stops containers, deletes volumes and generated files
./demo.sh setup simple        # Re-run setup from scratch (~5 minutes)
```

Or directly from the variant directory:

```bash
cd simple/
docker compose down -v        # Stop containers and delete all data volumes
rm -rf generated/ .env        # Remove generated files and environment config
./scripts/setup.sh            # Re-run setup from scratch (~5 minutes)
```

> **Important:** `docker compose down` without `-v` preserves the database volumes, so leftover resources from a previous demo run will still be present. Always use `-v` to get a clean slate.

## Troubleshooting

### Services not starting?

```bash
docker compose logs ontocloak
docker compose logs authoring-ontoserver
docker compose logs production-ontoserver
```

### Token errors?

```bash
curl -s http://localhost:9090/auth/health/ready
```

### Resources not visible?

Check the token's authorities:
```bash
echo $ALPHA_TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq '.authorities'
```

### Production not syncing?

The production server polls every 2 minutes. Check its logs:
```bash
docker compose logs production-ontoserver | grep -i synd
```
