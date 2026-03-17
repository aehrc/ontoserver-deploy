# Pathology Permissions Demo

A comprehensive demonstration of resource-level permissions for collaborative terminology authoring using [Ontoserver](https://ontoserver.csiro.au), [Ontocloak](https://ontoserver.csiro.au/site/our-solutions/ontocloak/), and [Atomio](https://ontoserver.csiro.au/site/our-solutions/atomio/).

## Scenario

Multiple pathology providers each maintain their own local order codes that need to be mapped to a **shared national pathology reference set**. Each group must:

- **See** the national reference set but not modify it
- **Create and edit** their own local CodeSystems and ConceptMaps
- **Not see** other groups' local resources
- Have distinct **roles**: viewers (read-only), authors (read/write), and approvers (can release content)

A third group maintains their terminology data as **CSV files in Git**, with an automated pipeline that transforms and loads the content.

## Two Variants

### Simple (`simple/`)

Direct syndication from authoring to production:

```mermaid
graph LR
    OC[Ontocloak<br/>auth] --> AO[Authoring Ontoserver<br/>read/write]
    AO -->|syndication| PO[Production Ontoserver<br/>read-only]

    style OC fill:#4a90d9,color:#fff
    style AO fill:#7cb342,color:#fff
    style PO fill:#ff8f00,color:#fff
```

Best for understanding the core concepts of resource-level permissions and syndication.

### Atomio (`atomio/`)

Release candidate management through Atomio:

```mermaid
graph TD
    OC[Ontocloak<br/>auth] --> AO[Authoring Ontoserver<br/>read/write]
    AO -->|clone feed| AT[Atomio<br/>release management]
    AT -->|uat alias| UAT[UAT Ontoserver<br/>read-only]
    AT -->|production alias| PO[Production Ontoserver<br/>read-only]

    style OC fill:#4a90d9,color:#fff
    style AO fill:#7cb342,color:#fff
    style AT fill:#ab47bc,color:#fff
    style UAT fill:#ff8f00,color:#fff
    style PO fill:#ff8f00,color:#fff
```

Adds release candidate creation, UAT testing, promotion/rollback, and the CSV-to-Atomio pipeline.

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Access to `quay.io/aehrc` container registry (Ontoserver, Ontocloak, Atomio images)
- `curl`, `jq`, `python3` installed locally
- Node.js and npm (for visual walkthroughs only)

### Using the Demo Script

Everything is controlled through a single entry point — `demo.sh`:

```bash
./demo.sh <command> <variant>
```

| Command | Description |
|---------|-------------|
| `setup` | Start Docker services and configure the environment |
| `walkthrough` | Run the interactive visual walkthrough in a browser |
| `status` | Show running services and health checks |
| `teardown` | Stop all services and remove data volumes |

| Variant | Description |
|---------|-------------|
| `simple` | Authoring + Production (direct syndication) |
| `atomio` | Authoring + Atomio + UAT + Production (release management) |

Run `./demo.sh` with no arguments to see full usage and available URLs.

### Simple Example

```bash
./demo.sh setup simple     # ~5 minutes
```

After setup, open:
- **Authoring Snapper**: http://localhost:9081/snapper
- **Production Snapper**: http://localhost:9082/snapper
- **Ontocloak Admin**: http://localhost:9090/auth/admin (admin/admin)
- **Snapper** (cloud-hosted): https://ontoserver.csiro.au/snapper?iss=http://localhost:9081
- **Ontoserver Dashboard**: https://ontoserver.csiro.au/ui?iss=http://localhost:9081

### Atomio Example

```bash
./demo.sh setup atomio     # ~8 minutes
```

After setup, additionally open:
- **Atomio API**: http://localhost:9083/swagger-ui.html
- **UAT Snapper**: http://localhost:9084/snapper
- **Production Snapper**: http://localhost:9085/snapper
- **Atomio UI**: https://ontoserver.csiro.au/atomio/?iss=http://localhost:9083
- **Ontoserver Dashboard** (UAT): https://ontoserver.csiro.au/ui?iss=http://localhost:9084

### Visual Walkthrough

After setup, run the visual walkthrough to see each demo scenario in a browser:

```bash
./demo.sh walkthrough simple       # Interactive — pauses at each scene
./demo.sh walkthrough simple --auto  # Auto mode — runs through all scenes
./demo.sh walkthrough atomio       # Atomio variant (13 scenes)
```

The walkthrough opens a Chromium browser and steps through login flows, permission checks, governance workflows, and syndication — demonstrating everything described in the documentation.

## Demo Users

All users have the password `demo`.

| User | Role | Can See | Can Edit |
|------|------|---------|----------|
| `admin` | Full administrator | Everything | Everything |
| `national-admin` | National admin | Everything (approver) | National valueset |
| `alpha-viewer` | Pathology Alpha viewer | National + Alpha resources | Nothing |
| `alpha-author` | Pathology Alpha author | National + Alpha resources | Alpha resources |
| `alpha-approver` | Pathology Alpha approver | National + Alpha resources | Alpha resources + syndication |
| `beta-viewer` | Pathology Beta viewer | National + Beta resources | Nothing |
| `beta-author` | Pathology Beta author | National + Beta resources | Beta resources |
| `beta-approver` | Pathology Beta approver | National + Beta resources | Beta resources + syndication |

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | System architecture, design decisions, and component interactions |
| [Key Concepts](docs/concepts.md) | Explanation of security labels, communities, syndication, and the permission model |
| [Simple Walkthrough](docs/walkthrough-simple.md) | Step-by-step guide for the simple example |
| [Atomio Walkthrough](docs/walkthrough-atomio.md) | Step-by-step guide for the Atomio variant |

## Teardown and Reset

```bash
# Tear down and remove all data
./demo.sh teardown simple
./demo.sh teardown atomio
```

This stops all Docker services and removes data volumes. To re-run a demo after completing it, you must tear it down first — the setup script expects a clean environment.

You can also check service health at any time:

```bash
./demo.sh status simple
./demo.sh status atomio
```

## Port Reference

| Port | Service | Variant |
|------|---------|---------|
| 9090 | Ontocloak (authorization) | Both |
| 9081 | Authoring Ontoserver | Both |
| 9082 | Production Ontoserver | Simple |
| 9083 | Atomio | Atomio |
| 9084 | UAT Ontoserver | Atomio |
| 9085 | Production Ontoserver | Atomio |
