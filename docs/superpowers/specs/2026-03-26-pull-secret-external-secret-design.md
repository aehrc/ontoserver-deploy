# Design: Chart-native ExternalSecret for Image Pull Secret

**Date:** 2026-03-26

## Goal

Allow users to source quay.io credentials from an external secrets manager via the External Secrets Operator, using chart-native values rather than writing their own `ExternalSecret` manifest.

## Values Structure

New block added under `ontoserver.externalSecret`:

```yaml
ontoserver:
  externalSecret:
    # existing fields unchanged
    imagePullSecret:
      # Optional override for the secret store. If omitted, falls back to
      # ontoserver.externalSecret.secretStoreRef.
      secretStoreRef:
        name: ""
        kind: ""
      data:
        username:
          key: ""        # secret path in store (e.g. "quay-credentials")
          property: username
        password:
          key: ""        # secret path in store
          property: password
```

No `enabled` flag. The feature activates when **both** `data.username.key` and `data.password.key` are non-empty. Setting only one of the two is a validation error (chart fails with a descriptive message).

## Activation Logic

| State | Behaviour |
|---|---|
| Both keys empty | Feature inactive, no resources created |
| Both keys set | ExternalSecret created, pull secret auto-wired |
| Only one key set | `fail` with error message |

## New Template: `imagepullsecretexternal.yaml`

Creates an `ExternalSecret` resource with:
- `secretStoreRef` from `imagePullSecret.secretStoreRef` if set, otherwise falls back to `ontoserver.externalSecret.secretStoreRef`
- `refreshInterval` from `ontoserver.externalSecret.refreshInterval`
- `target.template.type: kubernetes.io/dockerconfigjson` — produces a docker auth secret
- `target.name: {release}-ontoserver-pull-secret-external`
- Two `data` entries mapping username and password from the store

## Deployment / StatefulSet Wiring

`deployment.yaml` (and `statefulset.yaml` if present) auto-append `{release}-ontoserver-pull-secret-external` to `imagePullSecrets` when both keys are set, using the same condition as the template.

## Files Changed

| File | Change |
|---|---|
| `values.yaml` | Add `imagePullSecret` block under `externalSecret` with `@param` annotations |
| `templates/imagepullsecretexternal.yaml` | New — ExternalSecret template |
| `templates/deployment.yaml` | Auto-append pull secret to `imagePullSecrets` |
| `templates/statefulset.yaml` | Same as deployment (if file exists) |
| `values.schema.json` | Add `imagePullSecret` object under `externalSecret` properties |
| `charts/ontoserver/README.md` | Replace manual Option B example with chart-native values example |

## README Change

Option B in the "Registry Credentials" section is replaced with a chart-native example:

```yaml
ontoserver:
  externalSecret:
    secretStoreRef:
      name: my-cluster-secret-store
    imagePullSecret:
      data:
        username:
          key: quay-credentials
          property: username
        password:
          key: quay-credentials
          property: password
```

The manual `ExternalSecret` YAML snippet is removed. A note explains that `imagePullSecret.secretStoreRef` can override the parent store if needed.

## Validation Error Message

```
ontoserver.externalSecret.imagePullSecret: both data.username.key and data.password.key must be set together
```
