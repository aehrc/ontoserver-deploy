# Presentation Design Spec

## Overview

A Slidev-based slide deck for presenting the pathology permissions demo. AEHRC-branded, designed for 30-40 minutes with a compressible demo section for 15-20 minute versions.

## Technology

**Slidev** (Vue-powered presentation framework) — slides authored in Markdown with YAML frontmatter, custom CSS for AEHRC branding. Native Mermaid diagram support. Renders to HTML for presentation, PDF/PPTX for export.

### AEHRC Brand

- Primary blue: `#00A9CE`
- Dark navy: `#001D34`
- Grey: `#757579`
- Indigo: `#1E22AA`, Teal: `#007377`, Purple: `#6D2077`
- Font: Calibri
- Logo: CSIRO AEHRC horizontal (SVG)

## Slide Structure

### Section 1: The Problem (slides 1-5, ~5 min)

Target audience: clinical/business stakeholders.

1. **Title**: "Resource-Level Permissions for Collaborative Terminology Authoring" + AEHRC logo
2. **The Scenario**: Multiple pathology providers maintain local order codes, map to national Australian Pathology Terminology Reference Set (SNOMED CT refset 1072351000168102). Diagram: 3 providers + national standard
3. **The Challenge**: See national content (not modify), create/edit own resources, not see other providers' resources, distinct roles (viewer/author/approver). Collaboration vs isolation on shared infrastructure
4. **Diverse Authoring Workflows**: Some providers author natively in FHIR (Snapper). Others have established governance processes producing CSV — preserve existing human workflows as source of truth, automate FHIR transformation rather than introducing new processes
5. **What We Need**: Summary diagram: multi-tenant resource isolation + role-based access + content promotion pipeline + CSV-to-FHIR automation

### Section 2: Ontoserver Security Model (slides 6-11, ~8 min)

Target audience: technical implementers/decision makers.

6. **FHIR Terminology Resources**: CodeSystem, ValueSet, ConceptMap relationship diagram
7. **FHIR Security Labels**: `meta.security` element with `ALPHA.read`/`ALPHA.write`
8. **Ontoserver Security Levels**: `false` → `true` → `fine` progression table
9. **Two-Layer Security Model**: Layer 1 (API-level) + Layer 2 (resource-level). Both must pass
10. **Security Label Patterns**: `*.read` = anyone with FHIR_READ, `ALPHA.read` = needs PERM_ALPHA_READ
11. **Permission Check Flow**: Decision diagram: JWT → API check → community check → filtered results

### Section 3: Ontocloak (slides 12-16, ~5 min)

12. **What is Ontocloak?**: Keycloak + community management. OAuth2/OIDC
13. **Communities**: Auto-provisions realm roles, groups, role assignments
14. **User → Community → Token**: Trace alpha-author through groups → roles → JWT
15. **Token Anatomy**: Decoded JWT with audience-prefixed authorities and community permissions
16. **SMART-on-FHIR**: Sequence diagram: Snapper → Ontoserver → Ontocloak → JWT → filtered results

### Section 4: Demo Architecture (slides 17-22, ~5 min)

17. **Technology Stack**: Docker Compose, Ontocloak, Ontoserver, Atomio, PostgreSQL
18. **Simple Variant**: Ontocloak → Authoring Ontoserver → syndication → Production Ontoserver
19. **Atomio Variant**: Authoring → Atomio → aliases → UAT / Production
20. **CSV-to-FHIR Pipeline**: CSV in Git → transform → FHIR JSON with labels → upload
21. **Demo Users**: Table of users with permissions

### Section 5: Demo Walkthrough — UI-based (slides 23-35, ~12 min)

Interactive walkthrough using Shrimp, Snapper, and OntoCommand web tools.

22. **Starting the Demo**: Setup script, what it does
23. **Web Tools Overview**: Shrimp (browse), Snapper (edit), OntoCommand (admin)
24. **Anonymous Access (Shrimp)**: Only `*.read` resources visible without login
25. **Alpha Author's View (Shrimp)**: Log in, see Alpha resources, Beta/Gamma hidden
26. **Same Server, Different Views**: Switch users — beta-author vs admin
27. **Viewer vs Author (Snapper)**: Viewer read-only, author can edit
28. **Author Adds a Concept (Snapper)**: Add concept via UI, save succeeds
29. **Viewing ConceptMaps (Snapper)**: Local-to-SNOMED mappings
30. **Syndication to Production**: Compare OntoCommand dashboards
31. **CSV-to-FHIR Pipeline**: Transform command + verify in Shrimp
32. **Verify CSV Content (Shrimp)**: Browse generated Gamma content

### Section 6: Atomio Release Workflow (slides 36-41)

33. **Atomio Feeds and Aliases**: List feeds, list aliases
34. **Create Release Candidate**: Clone feed into snapshot
35. **Promote to UAT, then Production**: Alias updates
36. **Instant Rollback**: Repoint alias
37. **Atomio Web UI**: Hosted UI for visual management

### Section 7: Wrap-up (slides 42-43, ~2 min)

38. **Key Takeaways**: FHIR security labels, Ontocloak, syndication, Atomio, preserve workflows
39. **Resources & Links**: Product links, Snapper, Shrimp, contact

## File Structure

```
presentation/
  slides.md              # Slidev source (all slides)
  style.css              # Custom AEHRC CSS theme
  setup/
    mermaid.ts           # Global Mermaid diagram theme config
  public/
    csiro-aehrc-logo.svg # AEHRC logo
  package.json           # @slidev/cli dependency
  .gitignore             # node_modules/, dist/, .slidev/
```
