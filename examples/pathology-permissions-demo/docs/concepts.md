# Key Concepts

This document explains the core concepts used in this demo, providing background for those unfamiliar with Ontoserver's security model, syndication, or FHIR terminology services.

## FHIR Terminology Resources

This demo works with three types of FHIR R4 terminology resources:

### CodeSystem

A CodeSystem defines a set of codes. In our scenario, each provider has its own local pathology order codes:

```json
{
  "resourceType": "CodeSystem",
  "url": "http://pathology-alpha.example.com/CodeSystem/pathology-codes",
  "concept": [
    { "code": "FBC", "display": "Full Blood Count" },
    { "code": "UEC", "display": "Urea, Electrolytes & Creatinine" }
  ]
}
```

Each provider's codes are different because they evolved independently in different laboratory information systems.

### ValueSet

A ValueSet selects concepts from one or more CodeSystems. The national pathology reference set draws from the national standard CodeSystem:

```json
{
  "resourceType": "ValueSet",
  "url": "http://example.org/ValueSet/national-pathology-refset",
  "compose": {
    "include": [{
      "system": "http://example.org/CodeSystem/national-pathology-codes",
      "concept": [
        { "code": "NAT-CBC", "display": "Complete blood count" }
      ]
    }]
  }
}
```

This ValueSet defines the "target" that all providers map their local codes to.

### ConceptMap

A ConceptMap defines relationships between concepts in different code systems:

```json
{
  "resourceType": "ConceptMap",
  "sourceUri": "http://pathology-alpha.example.com/CodeSystem/pathology-codes",
  "targetUri": "http://example.org/ValueSet/national-pathology-refset",
  "group": [{
    "element": [{
      "code": "FBC",
      "target": [{ "code": "NAT-CBC", "equivalence": "equivalent" }]
    }]
  }]
}
```

This map says "Pathology Alpha's FBC code is equivalent to the national standard's Complete blood count."

## Ontoserver Security Model

### API-Level Security

When `ontoserver.security.enabled=true`, Ontoserver enforces role-based access control on its three API families:

| API | Endpoint | READ Role | WRITE Role |
|-----|----------|-----------|------------|
| FHIR | `/fhir` | `FHIR_READ` | `FHIR_WRITE` |
| Admin | `/api` | `API_READ` | `API_WRITE` |
| Syndication | `/synd` | `SYND_READ` | `SYND_WRITE` |

Roles are carried in JWT tokens issued by Ontocloak, in the `authorities` claim. When using audience-prefixed authorities (recommended for multi-server deployments), each role name is prefixed with the target client ID, e.g., `authoring-serverFHIR_READ` or `production-serverFHIR_READ`. This ensures that a token's permissions are scoped to the correct resource server.

### Resource-Level Security (Fine-Grained Mode)

When `ontoserver.security.enabled=fine`, an additional layer controls access to individual resources using FHIR security labels.

Each resource can have labels in its `meta.security` element:

```json
{
  "meta": {
    "security": [
      {
        "system": "http://ontoserver.csiro.au/CodeSystem/ontoserver-permissions",
        "code": "ALPHA.read"
      },
      {
        "system": "http://ontoserver.csiro.au/CodeSystem/ontoserver-permissions",
        "code": "ALPHA.write"
      }
    ]
  }
}
```

**Label format**: `{category}.{operation}` where:
- `category` is the community security label (e.g., `ALPHA`, `BETA`, `NATIONAL`)
- `operation` is either `read` or `write`

**Special wildcard**: `*.read` or `*.write` means only API-level authorization is required (no community membership needed).

### How Permissions Are Checked

For a **read** request:
1. If the resource has a `{category}.read` label → user needs `PERM_{CATEGORY}_READ` (or `PERM_READ` for wildcard)
2. If the resource has `*.read` → only needs `FHIR_READ` (e.g., `authoring-serverFHIR_READ` with audience-prefixed authorities)
3. If the resource has no security labels → only needs `FHIR_READ`
4. If a resource has multiple read labels → user needs to match **at least one**

For a **write** request:
1. If the resource has a `{category}.write` label → user needs `PERM_{CATEGORY}_WRITE` (or `PERM_WRITE`)
2. Write does **not** imply read (both must be granted separately)

**Important**: Resources that fail the permission check are simply **filtered out** of search results. The user doesn't get an error - they just don't see the resource.

## Ontocloak Communities

### What Is a Community?

A community is an Ontocloak concept that maps a group of users to a set of Ontoserver resource permissions. When you create a community in Ontocloak's admin UI:

1. **Security label** chosen (e.g., `ALPHA`) - alphanumeric identifier
2. **Realm roles** created: `PERM_ALPHA_READ`, `PERM_ALPHA_WRITE`, `PERM_ALPHA_OWNER`
3. **Groups** created:
   - "Pathology Alpha **authors**" → gets `PERM_ALPHA_READ` + `PERM_ALPHA_WRITE`
   - "Pathology Alpha **consumers**" → gets `PERM_ALPHA_READ` only
   - "Pathology Alpha **owners**" → can manage group membership
4. **Client scopes** created for consent-based access

### User-Community-Permission Flow

```
User "alpha-author"
  ├── member of group "Pathology Alpha authors"
  │     └── has realm role PERM_ALPHA_READ
  │     └── has realm role PERM_ALPHA_WRITE
  ├── member of group "System/Authors"
  │     └── has realm role Author
  │           └── includes client role authoring-server:authoring-serverFHIR_READ
  │           └── includes client role authoring-server:authoring-serverFHIR_WRITE
  │           └── includes client role production-server:production-serverFHIR_READ
  │
  └── JWT token contains:
        authorities: [authoring-serverFHIR_READ, authoring-serverFHIR_WRITE,
                      production-serverFHIR_READ, PERM_ALPHA_READ, PERM_ALPHA_WRITE, Author]
        audience: [authoring-server, production-server]
```

### System Roles vs Community Roles

| Role Type | Example | Controls |
|-----------|---------|----------|
| System role | Author, Consumer, Approver | API-level access (which endpoints) |
| Community role | PERM_ALPHA_READ | Resource-level access (which resources) |

A user needs **both**: a system role for API access AND a community role for resource access.

## Syndication

### What Is Syndication?

Syndication is Ontoserver's mechanism for distributing terminology content between instances using the Atom Syndication Format (RFC 4287). It works like an RSS feed for terminology resources.

### Upstream vs Downstream

- **Upstream**: Ontoserver pulls content from an external feed (e.g., the Australian NCTS, or another Ontoserver's syndication endpoint)
- **Downstream**: Ontoserver publishes its own content as a syndication feed that other instances can consume

### Syndication Publish Modes

The `atom.syndication.publish.fhir.enabled` property controls which resources appear in the syndication feed:

| Value | Behaviour |
|-------|-----------|
| `"true"` | All FHIR resources are published automatically |
| `"selected"` | Only resources with syndication status = true are published |
| `"false"` | No FHIR resources are published |

This demo uses `"selected"` so that an approver must explicitly approve each resource before it reaches downstream servers.

### Configuration

```yaml
# Publishing (authoring server)
atom.syndication.publish.enabled: "true"
atom.syndication.publish.fhir.enabled: "selected"
atom.syndication.publish.fhir.secureSyndicated: "true"

# Consuming (production server)
atom.syndication.feedLocation: http://authoring-ontoserver:8080/synd/syndication.xml
atom.preload.schedule.cron: "0 */2 * * * *"  # Poll every 2 minutes
```

### Feed URL

The authoring server's syndication feed is available at:
```
http://authoring-ontoserver:8080/synd/syndication.xml
```

This Atom XML feed lists all published FHIR resources with:
- `contentItemIdentifier` - the canonical URL of the resource
- `contentItemVersion` - the version
- A `link` element pointing to the downloadable FHIR JSON

### Security Labels in Syndication

Security labels in `meta.security` are part of the FHIR resource and are preserved through syndication. When the production server ingests a resource with `ALPHA.read` labels, those labels are present on the production copy too.

## Syndication Governance

### Why Protect Published Resources?

Once a resource has been approved for syndication and is flowing to production, it should not be accidentally modified. A change to a published resource would silently propagate to downstream environments without going through any review process.

### secureSyndicated

The `atom.syndication.publish.fhir.secureSyndicated` property adds a write-protection layer to syndicated resources:

- When set to `"true"`, modifying a resource that has syndication status = true requires the `SYND_WRITE` permission
- Authors (who have `FHIR_WRITE` but not `SYND_WRITE`) get **403 Forbidden** when trying to modify a published resource
- Approvers (who have `SYND_WRITE`) can modify published resources when necessary (e.g., correcting a typo)

### The Versioning Workflow

The governance model follows this pattern:

1. **Initial publication**: Resources are created, reviewed, and approved for syndication (syndication status set to true by an approver)
2. **Author wants changes**: The author cannot modify the published resource (403). Instead, they create a **new business version** — a new FHIR resource instance with the same canonical URL but a new version number (e.g., 1.0.0 → 1.1.0)
3. **New version is a draft**: The new version has no syndication status, so it does not appear in the syndication feed
4. **Approver reviews and publishes**: The approver sets syndication status on the new version, making it available in the feed
5. **Downstream sync**: Production (or Atomio → UAT → production) picks up the new version

### Role Requirements

| Action | Required Role | Has SYND_WRITE? |
|--------|--------------|-----------------|
| Create/edit draft resources | Author | No |
| Modify syndicated resources | Approver | Yes |
| Set syndication status | Approver | Yes |
| Create new business versions | Author | No |

### Setting Syndication Status

Syndication status can be set via the API:

```bash
POST /synd/setSyndicationStatus?resourceType=CodeSystem&id=alpha-pathology-codes&syndicate=true
Authorization: Bearer <approver-token>
```

This requires `SYND_WRITE` permission. The resource then appears in the syndication feed and is protected from modification by users without `SYND_WRITE`.

## Atomio

### What Is Atomio?

Atomio is a standalone syndication server that hosts terminology content as entries in Atom feeds. Unlike Ontoserver's built-in syndication, Atomio provides:

- **Named feeds**: Multiple independent feeds with descriptive names
- **Feed cloning**: Create snapshots of other feeds (including Ontoserver syndication)
- **Aliases**: Stable URLs that can be retargeted to different feeds
- **REST API**: Full CRUD for feeds, entries, and aliases

### Key Concepts

**Feed**: A named collection of entries. Example feeds: `release-1-0`, `release-2-0`, `gamma-content`. Feed names must match `^[A-Za-z0-9-_]+$` (alphanumeric, hyphens, and underscores only — no dots).

**Entry**: A single content item in a feed, containing:
- Metadata (title, version, content type)
- One or more artefacts (downloadable files)

**Alias**: A symbolic name that points to a feed. Example: `production` -> `release-2-0`. Changing the alias doesn't change the feed - it changes which feed the alias resolves to.

### Release Candidate Workflow

```
1. Author creates content on authoring Ontoserver
2. Approver clones authoring feed → Atomio "release-2-0"
3. Update "uat" alias → "release-2-0"
4. UAT Ontoserver syncs from uat alias
5. Test in UAT environment
6. Update "production" alias → "release-2-0"
7. Production Ontoserver syncs from production alias
```

**Rollback**: If issues are found in production, simply update the "production" alias back to the previous release feed (e.g., "release-1-0"). The previous content is still in Atomio.

### Feed Cloning

```bash
POST /feed/$clone?name=release-2-0&url=http://authoring-ontoserver:8080/synd/syndication.xml
```

This downloads the Atom feed from the authoring server and creates a new local feed in Atomio with all the entries and artefacts. The clone is a **snapshot** - subsequent changes to the authoring server do not affect the cloned feed.

## CSV-to-FHIR Pipeline

### Motivation

Some organizations maintain their terminology data in spreadsheets or databases rather than directly in FHIR format. The CSV-to-FHIR pipeline bridges this gap.

### How It Works

1. **CSV files** define codes and mappings (maintained in a Git repository)
2. **csv-transform.py** reads the CSVs and generates FHIR JSON with security labels
3. **Loading**: Resources are loaded into Ontoserver (simple variant) or uploaded to Atomio (Atomio variant)

### CSV Format

**Codes CSV** (`gamma-codes.csv`):
```csv
code,display,definition
GLU-R,Glucose Random,Random blood glucose measurement
HBA1C,HbA1c,Glycated haemoglobin percentage
```

**Mappings CSV** (`gamma-mappings.csv`):
```csv
source_code,source_display,target_system,target_code,target_display,equivalence,comment
GLU-R,Glucose Random,http://example.org/CodeSystem/national-pathology-codes,NAT-GLUC,Glucose measurement,equivalent,
```

### Security Labels

The transform script automatically adds security labels based on the `--security-label` argument:

```bash
python3 csv-transform.py --security-label GAMMA ...
```

Generates resources with:
```json
{ "meta": { "security": [
    { "code": "GAMMA.read" },
    { "code": "GAMMA.write" }
]}}
```

This ensures only Pathology Gamma community members can access the generated resources.

## SMART-on-FHIR Authentication

### How Snapper Authenticates

Snapper (Ontoserver's terminology browser/editor) uses the SMART-on-FHIR authorization flow:

1. User opens Snapper at `https://ontoserver.csiro.au/snapper?iss=http://localhost:9081`
2. Snapper reads Ontoserver's `CapabilityStatement` to find the auth endpoints
3. Snapper redirects to Ontocloak's authorization endpoint
4. User logs in to Ontocloak
5. Ontocloak redirects back to Snapper with an authorization code
6. Snapper exchanges the code for an access token
7. Snapper includes the token in all subsequent FHIR API requests

The `iss` (issuer) query parameter tells Snapper which FHIR server to connect to. The same pattern works for the Ontoserver Dashboard (`https://ontoserver.csiro.au/ui?iss=...`) and the Atomio UI (`https://ontoserver.csiro.au/atomio/?iss=...`).

### Token Contents

The JWT access token contains audience-prefixed authorities that scope permissions to each resource server:
```json
{
  "aud": ["authoring-server", "production-server"],
  "authorities": [
    "authoring-serverFHIR_READ", "authoring-serverFHIR_WRITE",
    "production-serverFHIR_READ",
    "PERM_ALPHA_READ", "PERM_ALPHA_WRITE"
  ],
  "preferred_username": "alpha-author",
  "exp": 1710000000
}
```

The audience prefix (`authoring-server`, `production-server`) on each API role ensures that a token's permissions are correctly scoped. Community permission roles (`PERM_*`) remain unprefixed since they apply across all servers.

Ontoserver validates the token using the RSA public key from Ontocloak and checks:
1. Token signature (RSA verification)
2. Audience claim matches the expected server
3. Token is not expired
4. Authorities include required permissions (matching the audience-prefixed role names)
