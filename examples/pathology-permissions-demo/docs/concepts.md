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

1. User opens Snapper at `https://ontoserver.csiro.au/snapper?iss=https://localhost:9081&clientId=snapper`
2. Snapper reads Ontoserver's `CapabilityStatement` to find the auth endpoints
3. Snapper redirects to Ontocloak's authorization endpoint
4. User logs in to Ontocloak
5. Ontocloak redirects back to Snapper with an authorization code
6. Snapper exchanges the code for an access token
7. Snapper includes the token in all subsequent FHIR API requests

The `iss` (issuer) query parameter tells Snapper which FHIR server to connect to. The `clientId` parameter identifies the client application to the authorization server. The same pattern works for the Ontoserver Dashboard (`https://ontoserver.csiro.au/ui?iss=...&clientId=onto-ui`) and the Atomio UI (`https://ontoserver.csiro.au/atomio/?iss=...&clientId=atomio-ui`).

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

## Keycloak Realm Configuration

The Ontocloak realm JSON defines the full set of clients, scopes, role mappings, and groups that produce the JWT tokens Ontoserver consumes. Understanding how these pieces fit together explains why tokens contain the claims they do.

### Clients

The realm contains seven clients in three categories:

**Resource servers** (bearer-only):
- `authoring-server` — represents the authoring Ontoserver instance
- `production-server` — represents the production Ontoserver instance
- `atomio-server` — represents the Atomio instance

These clients never accept user logins directly. They exist to define an audience and a namespace for client roles. When a token includes `authoring-server` in its `aud` claim and `authoring-serverFHIR_READ` in its `authorities` claim, those values come from the audience mapper and role mapper associated with the `authoring-server` client.

**Browser UIs** (public, authorization code flow):
- `shrimp` — the cloud-hosted FHIR terminology browser
- `snapper` — the cloud-hosted FHIR terminology editor
- `atomio-ui` — the cloud-hosted Atomio release management UI

These are public clients (no client secret) that use the standard OAuth2 authorization code flow. They have `exclude.issuer.from.auth.response: "true"` set in their attributes. This prevents Keycloak from injecting an `iss` parameter into the authorization response per RFC 9207, which would conflict with Shrimp's use of `?iss=` (along with `&clientId=`) to specify the FHIR server endpoint and client identity.

**CLI client** (public, direct-access-grants):
- `demo-cli` — used by the setup scripts and API demos

This client supports the resource owner password grant (direct access grants), allowing scripts to obtain tokens non-interactively via username and password. This is appropriate for demo and automation purposes.

**Service account** (confidential, client credentials):
- `syndication-consumer` — used by downstream Ontoserver instances to authenticate when pulling syndication feeds

This is a confidential client with a client secret that uses the client credentials grant. The setup script grants it `PERM_READ` (the wildcard community read permission) at runtime so the downstream server can download all community-labeled resources from the syndication feed.

### Client Scopes and Protocol Mappers

Client scopes control which claims appear in the JWT. The realm defines several custom scopes that map Keycloak roles into the `authorities` and `aud` claims that Ontoserver expects:

- **`authoring-server`** scope: contains two protocol mappers:
  - An **audience mapper** that adds `authoring-server` to the `aud` claim
  - A **client role mapper** that takes the client roles defined on the `authoring-server` client (e.g., `authoring-serverFHIR_READ`, `authoring-serverFHIR_WRITE`) and writes them into the `authorities` claim
- **`production-server`** scope: same pattern — audience mapper for `production-server` and client role mapper for its roles
- **`atomio-server`** scope: same pattern for the Atomio resource server
- **`user-realm-roles-authorities`** scope: maps **realm roles** (such as community permissions like `PERM_ALPHA_READ`, `PERM_BETA_WRITE`) into the `authorities` claim

The combination of these scopes means a single JWT token can contain both **audience-prefixed API roles** (e.g., `authoring-serverFHIR_READ`) from the client role mappers and **unprefixed community permissions** (e.g., `PERM_ALPHA_READ`) from the realm role mapper. This is how one token authorises access to multiple resource servers while carrying community-specific permissions that apply across all servers.

### SMART-on-FHIR Scopes and Role Scope Mappings

SMART-on-FHIR scopes control what operations a client application is permitted to perform. In the realm, these scopes interact with Keycloak's role scope mapping feature to conditionally appear in tokens based on the user's roles.

**Scope definitions**: The following client scopes are defined with `include.in.token.scope: "true"`, meaning their name appears in the token's `scope` claim when granted:
- `system/*.read`
- `system/*.write`
- `onto/synd.read`
- `onto/synd.write`

**Default scopes**: These SMART scopes are configured as **default scopes** on the browser UI clients (shrimp, snapper). "Default" means Keycloak will always *consider* including them in the token without the client explicitly requesting them in the authorization request.

**Role scope mappings** (`clientScopeMappings`): Each SMART scope has a **role scope mapping** that gates whether it actually appears in the token. The scope is only included if the authenticated user holds the required client role:

| SMART Scope | Required Client Role |
|-------------|---------------------|
| `system/*.read` | `authoring-serverFHIR_READ` |
| `system/*.write` | `authoring-serverFHIR_WRITE` |
| `onto/synd.read` | `authoring-serverSYND_READ` |
| `onto/synd.write` | `authoring-serverSYND_WRITE` |

The same pattern applies for production-server roles.

**Effect on users by role**:
- A **viewer** (Consumer role) has `FHIR_READ` but not `FHIR_WRITE`, so their token includes `system/*.read` in the scope claim but **not** `system/*.write`
- An **author** has both `FHIR_READ` and `FHIR_WRITE`, so their token includes both `system/*.read` and `system/*.write`
- An **approver** additionally has `SYND_READ` and `SYND_WRITE`, so their token also includes `onto/synd.read` and `onto/synd.write`

**Why this matters**: Snapper reads the `scope` claim to determine which UI features to enable. If `system/*.write` is absent from the scope, the Upload button is shown as "(unauthorised)". If `onto/synd.write` is absent, the Syndicate button is disabled. Ontoserver itself checks both the `scope` claim (preferred, per SMART-on-FHIR conventions) and the `authorities` claim (legacy) when authorising requests.

### Composite Realm Roles

The realm defines a hierarchy of composite roles that build on each other:

- **`Consumer`** — grants `FHIR_READ` on authoring-server, production-server, and atomio-server. This is the baseline role for read-only access to all resource servers.
- **`Author`** — includes Consumer, plus `FHIR_WRITE` on authoring-server and atomio-server. Authors can create and modify draft resources on the authoring server but have only read access to production.
- **`Approver`** — includes Author, plus `SYND_READ` and `SYND_WRITE` on authoring-server and atomio-server. Approvers can set syndication status and modify published resources.
- **`Full administrator`** — includes everything: all of the above, plus `API_READ` and `API_WRITE` on all servers, plus the wildcard community permissions (`PERM_READ`, `PERM_WRITE`). Administrators have unrestricted access to all resources and all API endpoints.

Users never need to be assigned individual client roles directly. Assigning a single composite realm role (or, more commonly, adding the user to a group) grants the full set of permissions for that level.

### Groups

Groups provide the mechanism for assigning roles to users:

**System groups** (defined in the realm JSON):
- `/System/Consumers` — the **default group** for all new users. Members receive the `Consumer` composite role, granting read access to all servers.
- `/System/Authors` — members receive the `Author` composite role
- `/System/Approvers` — members receive the `Approver` composite role

**Community groups** (created at runtime by the Ontocloak Communities API):
- `/Communities/...` — when a community is created (e.g., "Pathology Alpha" with label `ALPHA`), Ontocloak creates groups like "Pathology Alpha authors" and "Pathology Alpha consumers" with the appropriate `PERM_ALPHA_*` realm roles

Users are assigned to system groups in the realm JSON (e.g., `alpha-author` is in `/System/Authors`). Community group assignments are made by the setup script after it creates the communities via the Ontocloak API. A user typically belongs to one system group (determining their API access level) and one or more community groups (determining which resources they can see).
