{{/*
Job name — use job.name if set, otherwise Release.Name
*/}}
{{- define "ontoserver-indexer.jobName" -}}
{{- if .Values.job.name }}{{ .Values.job.name }}{{- else }}{{ .Release.Name }}{{- end }}
{{- end }}

{{/*
Secret name for inline auth credentials
*/}}
{{- define "ontoserver-indexer.secretName" -}}
{{ .Release.Name }}-indexer-auth
{{- end }}

{{/*
Resolved OAuth2 secret name — inline chart secret or user-supplied secretRef
*/}}
{{- define "ontoserver-indexer.oauth2SecretName" -}}
{{- if .Values.auth.oauth2.clientId }}{{ include "ontoserver-indexer.secretName" . }}
{{- else }}{{ .Values.auth.oauth2.secretRef }}{{- end }}
{{- end }}

{{/*
Resolved Basic auth secret name
*/}}
{{- define "ontoserver-indexer.basicSecretName" -}}
{{- if .Values.auth.basic.username }}{{ include "ontoserver-indexer.secretName" . }}
{{- else }}{{ .Values.auth.basic.secretRef }}{{- end }}
{{- end }}
