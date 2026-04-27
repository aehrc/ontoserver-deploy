# Kustomize Override Example

This example demonstrates how to use [Kustomize](https://kustomize.io/) to apply post-processing overrides to the Ontoserver Helm chart.

## Use Case: Adding `priorityClassName`

The `priorityClassName` is not currently exposed as a direct variable in the Ontoserver Helm chart. Instead of modifying the chart templates, you can use Kustomize to inject this property into the `Deployment` or `StatefulSet` resources.

## Files

- `kustomization.yaml`: Defines the transformation rules.
- `priority-class-patch.yaml`: (Optional) An alternative way to define patches using a file-based approach.

## Usage

### Option 1: Pipe Helm to Kustomize (Recommended)

You can generate the Kubernetes manifests using `helm template` and then pipe them into `kustomize build`.

1.  Create a directory for your overrides (like this one).
2.  Run the following command:

    ```bash
    helm template ontoserver ./charts/ontoserver -f your-values.yaml > rendered-helm.yaml
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

### Option 2: Kustomize Helm Chart Inflator (Kustomize v5+)

If you are using a modern version of Kustomize, you can inflate the Helm chart directly within the `kustomization.yaml`:

```yaml
helmCharts:
  - name: ontoserver
    releaseName: ontoserver
    path: ../../charts/ontoserver
    valuesFile: your-values.yaml
```

patches:
  - target:
      kind: Deployment
      labelSelector: "app=ontoserver-ontoserver"
    patch: |
      - op: add
        path: /spec/template/spec/priorityClassName
        value: system-cluster-critical
```

## Note on Label Selectors

The Ontoserver chart generates labels in the format `app: {{ .Release.Name }}-ontoserver`. Ensure your `labelSelector` in `kustomization.yaml` matches the `releaseName` used during template generation.
