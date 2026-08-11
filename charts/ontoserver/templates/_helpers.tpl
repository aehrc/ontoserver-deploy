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

{{/*
Is a PodDisruptionBudget field set?

`empty` cannot be used here: empty 0 is true, so it conflates a deliberate 0 with an unset
field and the caller then reports "set one of them" for a field that was set. Nil and the
empty string are unset; 0 is set (and rejected separately, with a reason).
*/}}
{{- define "ontoserver.pdbIsSet" -}}
{{- if kindIs "invalid" . }}{{- else if eq (toString .) "" }}{{- else }}true{{- end }}
{{- end }}

{{/*
Render a PodDisruptionBudget field as a Kubernetes IntOrString.

Percentages must be quoted strings ("25%") and counts must stay unquoted integers. Quoting
everything would emit minAvailable: "1", which the API server tries to parse as a percentage
and rejects; quoting nothing would emit an unquoted 25% that survives YAML parsing but is
fragile. So quote if and only if the value is a percentage.
*/}}
{{- define "ontoserver.pdbValue" -}}
{{- if hasSuffix "%" (toString .) }}{{ toString . | quote }}{{ else }}{{ . }}{{ end }}
{{- end }}
