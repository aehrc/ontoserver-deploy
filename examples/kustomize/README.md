# Kustomize Override Example

This example demonstrates how to use [Kustomize](https://kustomize.io/) to apply post-processing overrides to the Ontoserver Helm chart.

## Use Case: Adding `priorityClassName`

The `priorityClassName` is not currently exposed as a direct variable in the Ontoserver Helm chart. Instead of modifying the chart templates, you can use Kustomize to inject this property into the `Deployment` or `StatefulSet` resources.

## Files

- `kustomization.yaml`: Defines the transformation rules and Helm chart source.
- `values.yaml`: Configuration values for the Helm chart. **Note:** This file must exist (even if empty) to avoid a Kustomize bug when processing local charts.
- `priority-class-patch.yaml`: (Optional) An alternative way to define patches using a file-based approach.

## Usage

### Option 1: Kustomize Helm Chart Inflator (Kustomize v5+)

This is the recommended approach for modern versions of Kustomize (and `kubectl`). The `kustomization.yaml` in this directory is pre-configured to inflate and patch the chart directly using the `helmCharts` field.

Run the following command from this directory:

```bash
kubectl kustomize . --enable-helm --load-restrictor LoadRestrictionsNone
```

**Note:** The `--load-restrictor LoadRestrictionsNone` flag is required because the Helm chart is located outside of this example directory.

### Option 2: Pipe Helm to Kustomize (Alternative)

If you prefer to separate the steps or are using an older version of Kustomize, you can generate the Kubernetes manifests using `helm template` and then pipe them into `kustomize build`.

1.  Remove the `helmCharts` section from `kustomization.yaml`.
2.  Run the following command:

    ```bash
    helm template ontoserver ../../charts/ontoserver -f your-values.yaml > rendered-helm.yaml
    ```

3.  Update the `kustomization.yaml` to include `rendered-helm.yaml` in the `resources` section:

    ```yaml
    resources:
      - rendered-helm.yaml
    ```

4.  Apply the overrides:

    ```bash
    kustomize build . | kubectl apply -f -
    ```

## Note on Label Selectors

A patch `target.labelSelector` matches a resource's **own metadata labels** — not its pod template labels and not its `spec.selector`. This distinction matters: a selector that only exists on the pod template will match nothing, and Kustomize treats a patch that matches nothing as success rather than an error.

The chart stamps the standard labels on every resource it creates, so prefer the release-independent one:

| Label | Value | Notes |
| --- | --- | --- |
| `app.kubernetes.io/name` | `ontoserver` | Stable — use this in `labelSelector` |
| `app.kubernetes.io/instance` | the release name | Changes with `releaseName` |
| `app` | `<release>-ontoserver` | Release-scoped selector label; also changes with `releaseName` |

Because a non-matching patch fails silently, always confirm the result rather than assuming it applied:

```bash
kubectl kustomize . --enable-helm --load-restrictor LoadRestrictionsNone | grep priorityClassName
```

Expect exactly one match — the chart renders either a `Deployment` or a `StatefulSet` depending on `ontoserver.deployment.kind`, so only one of the two patches in `kustomization.yaml` applies to any given render.
