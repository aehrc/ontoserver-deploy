# Proposed Documentation Improvements

Based on setting up the pathology-permissions-demo end-to-end (Ontoserver ctsa-6, Ontocloak 5, Snapper, Atomio), these are documentation gaps that caused significant friction. Each proposal includes the problem encountered, the eventual solution, and a suggested documentation improvement.

---

## Critical Priority (Setup Blockers)

### 1. JWT Token / RSA Key Configuration Guide

**Problem**: Setting up JWT validation between Ontocloak and Ontoserver took significant debugging. The key issues were:
- It was unclear that `ontoserver.security.token.secret` handles BOTH HMAC and RSA keys (auto-detected by PEM markers)
- No guidance on how to pass a multi-line PEM key via Docker environment variables
- `SPRING_CONFIG_ADDITIONAL_LOCATION` didn't reliably override `@Value`-injected properties from the packaged config
- When the RSA key was set without PEM markers, Ontoserver silently fell back to HMAC mode, producing "Signed JWT rejected: Another algorithm expected" errors

**Solution discovered**: Use `SPRING_APPLICATION_JSON` to pass the PEM-formatted key with JSON `\n` escapes:
```yaml
SPRING_APPLICATION_JSON: '{"ontoserver.security.token.secret":"-----BEGIN PUBLIC KEY-----\n<base64>\n-----END PUBLIC KEY-----"}'
```

**Suggested documentation**:
- Add a dedicated "JWT Token Verification Setup" section to the deployment guide
- Clearly state that `ontoserver.security.token.secret` auto-detects HMAC vs RSA
- Provide copy-paste examples for Docker Compose (using `SPRING_APPLICATION_JSON`), Kubernetes (using Secrets), and standalone (using `application.properties`)
- Include a troubleshooting subsection for "Algorithm mismatch" and "Empty key" errors
- Show how to extract the RSA public key from Keycloak/Ontocloak:
  ```bash
  curl -s -H "Authorization: Bearer $TOKEN" \
    "$KEYCLOAK_URL/admin/realms/$REALM/keys" \
    | jq -r '.keys[] | select(.type=="RSA" and .algorithm=="RS256") | .publicKey'
  ```

---

### 2. Ontoserver Default Port and SSL Configuration

**Problem**: Ontoserver ctsa-6 defaults to HTTPS on port 8443. When deploying behind a reverse proxy or in Docker Compose (where TLS terminates at the edge), there's no clear guidance on switching to HTTP.

**Solution discovered**: Set both properties:
```yaml
server.port: "8080"
server.ssl.enabled: "false"
```

**Suggested documentation**:
- Add a "Quick Start: HTTP Mode" section showing the two required properties
- Document the default behavior (HTTPS/8443) prominently in the deployment guide
- Note that health checks should use the HTTP port (not 8443) when SSL is disabled

---

### 3. Security Mode Reference (`ontoserver.security.enabled`)

**Problem**: The valid values for `ontoserver.security.enabled` are not clearly documented. We tried `coarse` (which doesn't exist) before learning the valid values are `false`, `true`, and `fine`. The behavioral differences between `true` and `fine` were unclear.

**Suggested documentation**: Add a comparison table:

| Value | Authentication | Resource Filtering | Syndication Reads | Use Case |
|-------|---------------|-------------------|-------------------|----------|
| `false` | None | None | Open | Development only |
| `true` | Required for writes | None (all resources visible) | Open with `readOnly.fhir` | Internal authoring server |
| `fine` | Required | Community-based (security labels) | Community-filtered | Production / consumer-facing |

Include concrete examples showing what each mode returns for authenticated vs anonymous requests.

---

### 4. Syndication Authentication with Fine-Grained Security

**Problem**: When both authoring and production servers use `ontoserver.security.enabled=fine`, the syndication consumer needs to authenticate when fetching community-labeled FHIR resources from the upstream server. This is not immediately obvious from the documentation.

**Solution discovered**: Ontoserver supports `authentication.oauth.endpoint.*` properties (indexed: `.0`, `.1`, etc.) for OAuth2 client credentials on syndication consumers. Configure a Keycloak service account with `PERM_READ` (all communities read) and the audience-prefixed FHIR_READ role (e.g., `authoring-serverFHIR_READ`), then set:
```yaml
authentication.oauth.endpoint.0: http://upstream-ontoserver:8080
authentication.oauth.endpoint.token_endpoint.0: http://keycloak:8080/auth/realms/my-realm/protocol/openid-connect/token
authentication.oauth.endpoint.client_id.0: syndication-consumer
authentication.oauth.endpoint.client_secret.0: <secret>
authentication.oauth.endpoint.strategy.0: body
```

**Suggested documentation**:
- Document the `authentication.oauth.endpoint.*` property family with a complete example for fine-grained security syndication
- Note that the feed XML itself is accessible anonymously (with `readOnly.synd=true`), but the FHIR resource URLs in feed entries require authentication
- Show how to create a Keycloak service account with the correct roles for all-communities read access
- The NCTS example in existing docs only covers external syndication sources — add an example for Ontoserver-to-Ontoserver syndication with community isolation

---

### 5. Ontocloak Communities API Authentication

**Problem**: The Ontocloak communities API (`/auth/realms/{realm}/communities`) requires a realm-level user token, NOT the master admin token. This is not documented and caused confusing 403 errors during community creation.

Additionally, the `realm-management` client must have `authorizationServicesEnabled=true` for the communities API to work. This is not set by default when importing a realm.

**Suggested documentation**:
- Add a "Communities API" section specifying:
  - Required token type: realm-level user token (not master admin)
  - Required client configuration: `realm-management` client needs `authorizationServicesEnabled=true` and `serviceAccountsEnabled=true`
  - Show how to enable these via the admin API:
    ```bash
    # Get realm-management client UUID
    RM_ID=$(curl -s "$KC_URL/admin/realms/$REALM/clients?clientId=realm-management" \
      -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')
    # Enable authorization services
    curl -X PUT "$KC_URL/admin/realms/$REALM/clients/$RM_ID" \
      -H "Authorization: Bearer $ADMIN_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$(curl -s "$KC_URL/admin/realms/$REALM/clients/$RM_ID" \
        -H "Authorization: Bearer $ADMIN_TOKEN" | \
        jq '.authorizationServicesEnabled=true | .serviceAccountsEnabled=true | .bearerOnly=false')"
    ```

---

### 5b. Syndication Polling Schedule Configuration

**Problem**: `atom.syndication.feedLocation` alone does NOT enable periodic syndication polling. The `PreloadScheduler` bean is gated by `@ConditionalOnProperty(prefix="atom.preload.schedule")` and uses `@Scheduled(cron="${atom.preload.schedule.cron}")`. Without setting `atom.preload.schedule.cron`, no scheduled polling occurs — only the one-time startup preload runs. Additionally, the `PreloadScheduler` only processes feeds from `atom.preload.feedLocation`, not `atom.syndication.feedLocation`.

**Solution discovered**: Set `atom.preload.schedule.cron` AND include remote feed URLs in `atom.preload.feedLocation`:
```yaml
atom.preload.feedLocation: "file:///data/preload/preload.xml,http://upstream:8080/synd/syndication.xml"
atom.preload.schedule.cron: "0 */2 * * * *"  # Spring 6-field cron (sec min hour dom month dow)
```

**Suggested documentation**:
- Document that `atom.preload.schedule.cron` is required to enable periodic syndication consumption
- Clarify that `atom.preload.feedLocation` (not `atom.syndication.feedLocation`) controls what feeds are processed during scheduled polls
- Provide example cron expressions for common intervals (demo: 2 min, staging: 15 min, production: 1 hour)
- Note that `atom.syndication.feedLocation` is used for artifact resolution, not for scheduled polling

---

## High Priority (Significant Time Wasted)

### 6. NCTS Syndication Feed Format

**Problem**: The preload feed XML requires the full URL format for the syndication profile element:
```xml
<ncts:atomSyndicationFormatProfile>http://ns.electronichealth.net.au/ncts/syndication/asf/profile/1.0.0</ncts:atomSyndicationFormatProfile>
```
We initially used the version attribute format (`<ncts:atomSyndicationFormatProfile version="1.0.0" />`), which caused a cryptic error: `atomSyndicationFormatProfile:version; found '1.0.0'`.

**Suggested documentation**:
- Provide a complete, copy-paste-ready preload feed XML template
- Explicitly show the correct format with a "do NOT use" example of the version attribute form
- Include the required NCTS namespace declaration

---

### 7. Ontocloak Realm Import Pitfalls

**Problem**: When creating a custom Keycloak realm JSON for import, including `realm-management` or `account` client role definitions causes conflicts with Keycloak's built-in roles. This produces errors during realm startup that are difficult to diagnose.

**Suggested documentation**:
- Add a "Realm JSON Best Practices" section
- Explicitly warn: "Do NOT include `realm-management` or `account` client roles in your realm JSON — these are created automatically by Keycloak and including them causes conflicts"
- Provide a minimal realm JSON template showing only the elements that should be customized

---

### 8. Docker Compose `.env` File Limitations

**Problem**: Docker Compose `.env` files cannot hold multi-line values. Even with double quotes, values are truncated at the first newline. This is critical for PEM-formatted RSA keys.

**Suggested documentation**:
- Add a "Secrets in Docker Compose" section explaining:
  - `.env` files truncate at newlines (no workaround)
  - `SPRING_APPLICATION_JSON` with JSON `\n` escapes is the recommended approach
  - `printf` can create single-line `.env` values with literal `\n`:
    ```bash
    printf 'KEY={"prop":"-----BEGIN PUBLIC KEY-----\\n%s\\n-----END PUBLIC KEY-----"}\n' "$BASE64_KEY" > .env
    ```
  - Kubernetes Secrets and Docker Secrets handle multi-line values natively

---

### 9. Ontocloak Health Check Endpoint

**Problem**: Ontocloak's health endpoint runs on management port 9000, not the main application port. Docker health checks targeting the main port for health endpoints fail. The reliable readiness check is `GET /auth/realms/master` on the main port.

**Suggested documentation**:
- Document health check options:
  - Management port: `http://localhost:9000/health/ready`
  - Main port: `http://localhost:8080/auth/realms/master` (readiness proxy)
- Provide Docker Compose health check examples for both approaches

---

## Medium Priority (Usability Improvements)

### 10. Troubleshooting Guide

**Problem**: Several errors during setup had no documentation explaining their cause:
- `Signed JWT rejected: Another algorithm expected, or no matching key(s) found` → RSA key not in PEM format
- `java.lang.IllegalArgumentException: Empty key` → Empty `token.secret` value
- `atomSyndicationFormatProfile:version; found '1.0.0'` → Wrong XML element format
- `No enum constant au.csiro.ontoserver.security.SecurityLevel.coarse` → Invalid security mode
- `Cannot access http://...` in syndication logs → Fine-grained security blocking anonymous resource download

**Suggested documentation**: Create a "Common Errors & Solutions" page with:
- Error message (searchable)
- Root cause explanation
- Fix with code example
- Related configuration properties

### 11. `ontoserver.fhir.base` and Syndication URL Generation

**Problem**: Syndication feed entries use `ontoserver.fhir.base` for resource download URLs. In Docker Compose, if this is set to `http://localhost:9081/fhir`, other containers can't reach it (localhost resolves to themselves). Must use Docker-internal hostnames for inter-container syndication.

**Suggested documentation**:
- Explain that `ontoserver.fhir.base` controls URLs in:
  - FHIR CapabilityStatement
  - Syndication feed resource download links
  - Resource self-references
- For Docker Compose: recommend Docker-internal hostname (`http://container-name:8080/fhir`)
- Note the trade-off: Snapper/browser clients may see internal URLs in CapabilityStatements (usually harmless as Snapper constructs URLs relative to its own origin)

### 12. FHIR Resource Write Validation

**Problem**: When updating a CodeSystem via PUT, Ontoserver validates that the concept count matches the `count` field. Adding a concept without incrementing `count` returns 422 ("Too many codes: 13 is more than specified number: 12"). This validation behavior is undocumented.

**Suggested documentation**:
- Document FHIR resource validation rules, especially for CodeSystem:
  - `count` must match the number of concepts
  - `url` in the body must match the resource's canonical URL
  - `id` in the body must match the URL path
- Include example of correct PUT with concept modification

---

## Summary

The most impactful improvements would be:
1. **JWT/RSA key setup guide** (prevented startup for hours)
2. **Syndication authentication for fine-grained security** (`authentication.oauth.endpoint.*` properties)
3. **Security mode reference table** (invalid values, unclear behavioral differences)
4. **Communities API authentication guide** (wrong token type, missing client config)
5. **Common errors & solutions page** (searchable troubleshooting)

These five additions would address the majority of friction encountered during a realistic deployment scenario.
