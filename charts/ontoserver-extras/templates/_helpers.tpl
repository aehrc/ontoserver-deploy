{{/*
Common labels
*/}}
{{- define "ontoserver-extras.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ontoserver
{{- /* appVersion (the Ontoserver release), not the chart version: app.kubernetes.io/version
     describes the deployed application, while helm.sh/chart carries the chart version. */}}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Varnish selector labels
*/}}
{{- define "ontoserver-extras.varnish.selectorLabels" -}}
app: {{ .Release.Name }}-varnish-cache
{{- end }}
