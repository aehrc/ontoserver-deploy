{{/*
Common labels applied to the metadata of every resource this chart creates.

These are metadata-only. They are deliberately NOT added to any selector:
  - Deployment/StatefulSet .spec.selector is immutable, so changing it breaks helm upgrade
    on an existing release.
  - StatefulSet .spec.volumeClaimTemplates is likewise immutable.
Use ontoserver.selectorLabels for anything that participates in matching.
*/}}
{{- define "ontoserver.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ontoserver
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Selector labels — the immutable identity of the Ontoserver pods.

This value is baked into the .spec.selector of existing Deployments and StatefulSets, so it
must never change. Everything that selects Ontoserver pods (Services, PodDisruptionBudget)
uses this and only this.
*/}}
{{- define "ontoserver.selectorLabels" -}}
app: {{ .Release.Name }}-ontoserver
{{- end }}
