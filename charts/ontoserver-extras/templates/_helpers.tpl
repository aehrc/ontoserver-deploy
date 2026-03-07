{{/*
Common labels
*/}}
{{- define "ontoserver-extras.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: ontoserver
app.kubernetes.io/version: {{ .Chart.Version | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Varnish selector labels
*/}}
{{- define "ontoserver-extras.varnish.selectorLabels" -}}
app: {{ .Release.Name }}-varnish-cache
{{- end }}
