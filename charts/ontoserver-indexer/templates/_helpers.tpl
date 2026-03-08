{{/*
Job name — use job.name if set, otherwise Release.Name with a random suffix.
The suffix changes on every render so that helm upgrade --install creates a new
Job rather than failing due to Job spec immutability.
*/}}
{{- define "ontoserver-indexer.jobName" -}}
{{- if .Values.job.name }}{{ .Values.job.name }}{{- else }}{{ .Release.Name }}-{{ randAlphaNum 6 | lower }}{{- end }}
{{- end }}

{{/*
Secret name for inline auth credentials
*/}}
{{- define "ontoserver-indexer.secretName" -}}
{{- printf "%s-indexer-auth" .Release.Name }}
{{- end }}

{{/*
Resolved OAuth2 secret name — inline chart secret or user-supplied secretRef
*/}}
{{- define "ontoserver-indexer.oauth2SecretName" -}}
{{- if .Values.auth.oauth2.clientId }}{{- include "ontoserver-indexer.secretName" . }}
{{- else }}{{- .Values.auth.oauth2.secretRef }}{{- end }}
{{- end }}

{{/*
Resolved Basic auth secret name
*/}}
{{- define "ontoserver-indexer.basicSecretName" -}}
{{- if .Values.auth.basic.username }}{{- include "ontoserver-indexer.secretName" . }}
{{- else }}{{- .Values.auth.basic.secretRef }}{{- end }}
{{- end }}
