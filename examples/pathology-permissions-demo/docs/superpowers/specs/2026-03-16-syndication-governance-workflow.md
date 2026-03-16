# Syndication Governance Workflow — Design Spec

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement the plan generated from this spec.

**Goal:** Add a syndication governance workflow to the pathology permissions demo that demonstrates how published resources are protected from modification, authors create new business versions, and approvers control what reaches production.

**Motivation:** The current demo shows community isolation and role-based access, but treats resource editing as a simple save. Real terminology governance requires that published (syndicated) resources cannot be accidentally modified. Changes go through a versioning workflow where authors create new versions and approvers explicitly publish them.

---

## 1. Infrastructure Changes

### Docker Compose (both `simple/docker-compose.yml` and `atomio/docker-compose.yml`)

On the authoring Ontoserver, change:
```yaml
# Before
atom.syndication.publish.fhir.enabled: "true"

# After
atom.syndication.publish.fhir.enabled: "selected"
atom.syndication.publish.fhir.secureSyndicated: "true"
```

- `"selected"` — only resources with syndication status = true appear in the syndication feed. New resources are draft by default.
- `secureSyndicated: "true"` — modifying a syndicated resource requires `SYND_WRITE` permission (the `Approver` role), on top of normal FHIR write permissions.

No other infrastructure changes needed. The `Approver` role already includes `authoring-serverSYND_WRITE` and `authoring-serverSYND_READ`. The `Author` role does not.

### Setup Scripts (both `simple/scripts/setup.sh` and `atomio/scripts/setup.sh`)

After loading sample resources (Step 7 in atomio, similar in simple), set syndication status on all 1.0.0 resources to simulate an initial approval:

```bash
# Set syndication status on initial resources (simulates initial approval)
for rt_id in \
    "CodeSystem/alpha-pathology-codes" \
    "ConceptMap/alpha-pathology-to-snomed" \
    "CodeSystem/beta-pathology-codes" \
    "ConceptMap/beta-pathology-to-snomed"; do
  resourceType="${rt_id%%/*}"
  id="${rt_id##*/}"
  curl -sf -o /dev/null -X POST \
    "${AUTHORING_URL}/synd/setSyndicationStatus?resourceType=${resourceType}&id=${id}&syndicate=true" \
    -H "Authorization: Bearer ${admin_token}"
done
```

Also set syndication status on Gamma resources after they are loaded (Step 8).

The syndication status API (`/synd/setSyndicationStatus`) requires `SYND_WRITE` permission, so the admin token (which has the Full Administrator role with SYND_WRITE) is used.

## 2. Walkthrough Scene Changes

### Roles involved
- **alpha-viewer** — `PERM_ALPHA_READ` only (Consumer role). Can browse, cannot edit.
- **alpha-author** — `PERM_ALPHA_READ` + `PERM_ALPHA_WRITE` + `FHIR_WRITE` (Author role). Can create/edit draft resources. Cannot modify syndicated resources (no `SYND_WRITE`).
- **alpha-approver** — everything alpha-author has, plus `SYND_READ` + `SYND_WRITE` (Approver role). Can modify syndicated resources and set syndication status.

### Revised scene flow (both simple and atomio)

**Scene 5: Viewer — Read-Only Access** (minor update)
- alpha-viewer opens Snapper on authoring server
- Searches CodeSystems, sees Pathology Alpha 1.0.0
- Can browse but cannot edit (no FHIR_WRITE)

**Scene 6: Author Blocked on Published Resource** (new)
- alpha-author opens Snapper on authoring server
- Opens Pathology Alpha CodeSystem 1.0.0 (syndicated)
- Attempts to save a modification (e.g., change description)
- Gets **403 Forbidden** — has FHIR_WRITE but not SYND_WRITE
- Narrator explains: "Published resources are protected. Authors cannot accidentally modify what's already in production."

**Scene 7: Author Creates New Business Version** (new)
- alpha-author loads CodeSystem 1.0.0, changes version to 1.1.0
- Adds new concept: code=D-DIM, display="D-Dimer", definition="D-dimer test for thrombosis"
- Saves → **200 OK** (new resource instance, not yet syndicated)
- Narrator explains: "Authors create new versions rather than modifying published ones. The new version is a draft — it won't appear in the syndication feed until approved."

**Scene 8: Approver Publishes New Version** (new)
- Logout, login as alpha-approver
- Open OntoCommand (dashboard) for the authoring server
- Navigate to the new CodeSystem 1.1.0
- Set syndication status to true (approve for publication)
- Narrator explains: "The approver gates what reaches downstream environments. Only approved resources enter the syndication feed."

**Scene 9: Syndication Verification** (updated, replaces old scene 8)
- Show that the 1.1.0 version now appears in the syndication feed
- **Simple variant**: Open dashboard for production server, verify 1.1.0 appears after sync
- **Atomio variant**: Show that next clone/release from authoring would include 1.1.0

**Scene 10: ConceptMaps and CSV Content** (consolidation of old scenes 7 + 9)
- Show ConceptMap community isolation (alpha-author sees only Alpha's ConceptMap)
- Show CSV-generated Gamma content visible to admin

**Atomio-only scenes** (11-13): unchanged — feeds, aliases, UAT content

### Implementation approach for scenes 6-8

**Scene 6 (403 on edit):** The walkthrough needs to demonstrate the 403. Options:
- Use the Ontoserver FHIR API via Playwright's request context to attempt a PUT and show the 403 status in the narrator output
- OR attempt a save in Snapper and capture the error dialog

Recommend: **API approach** — more reliable, clearly shows the HTTP 403, and the narrator can display the exact error.

**Scene 7 (new version):** Use the FHIR API to PUT a new CodeSystem resource with version 1.1.0 and the additional concept. This is more reliable than driving Snapper's editor UI.

**Scene 8 (approve):** Use the `/synd/setSyndicationStatus` API with alpha-approver's token. Show OntoCommand in the browser to visually confirm the status change.

## 3. Documentation Updates

### walkthrough-simple.md
- Add "Part 2: Authoring Workflow" section between the current Part 1 (resource isolation) and Part 2 (syndication):
  - 2.1 Viewer access (read-only)
  - 2.2 Author blocked on published resource
  - 2.3 Author creates new business version
  - 2.4 Approver publishes new version
  - 2.5 Syndication verification

### walkthrough-atomio.md
- Same authoring workflow section
- Atomio-specific: after approval, show clone/release workflow

### concepts.md
- Add section: "Syndication Governance" explaining:
  - `secureSyndicated` configuration
  - Why published resources are locked
  - The versioning workflow (author → new version → approver → syndication)
  - Role requirements (Author vs Approver)

### architecture.md
- Note `secureSyndicated` in the authoring server configuration section
- Document the `selected` vs `true` syndication mode difference

## 4. Presentation Updates

### Section 5: UI Walkthrough (slides.md)

Update/add slides to cover the governance workflow:

- **Slide: "Editing — Author Blocked"** — show that saving to a published resource returns 403
- **Slide: "Editing — New Business Version"** — author creates 1.1.0 with new concept
- **Slide: "Approving — Syndication Status"** — approver publishes the new version
- **Slide: "Governance Rationale"** — explain why: prevent accidental production changes, versioning discipline, approval gates

### Section 2: Security Model

- Add mention of `secureSyndicated` in the security levels discussion
- Note that `SYND_WRITE` is the approval permission

---

## 5. What Does NOT Change

- Keycloak realm configuration — roles and groups are already correct
- Community isolation — unchanged
- Anonymous access scene — unchanged
- Atomio infrastructure — unchanged
- CSV pipeline — unchanged (Gamma resources also need syndication status set in setup)

## 6. Testing

After implementation:
- Run `npm run walkthrough:auto` (simple variant) — all scenes pass
- Run `npm run walkthrough:atomio:auto` (atomio variant) — all scenes pass
- Verify production server receives syndicated content after setup
- Verify alpha-author gets 403 on syndicated resource
- Verify alpha-author can create new version
- Verify alpha-approver can set syndication status
