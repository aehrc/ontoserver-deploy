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

The Ontoserver chart generates labels in the format `app: {{ .Release.Name }}-ontoserver`. Ensure your `labelSelector` in `kustomization.yaml` matches the `releaseName` used during template generation.
