{{/*
Job name — use job.name if set, otherwise Release.Name suffixed with the release revision.
The revision increments on every helm upgrade, so `helm upgrade --install` creates a new
Job rather than failing due to Job spec immutability.

Do NOT use randAlphaNum here: this helper is called from job.yaml (metadata.name, two
label fields) and NOTES.txt, and every `include` re-evaluates the template body. A random
value would therefore differ between those call sites, and would also make `helm template`
non-deterministic, which shows up as permanent drift in ArgoCD and friends.
*/}}
{{- define "ontoserver-indexer.jobName" -}}
{{- if .Values.job.name }}{{ .Values.job.name }}{{- else }}{{ .Release.Name }}-{{ .Release.Revision }}{{- end }}
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
