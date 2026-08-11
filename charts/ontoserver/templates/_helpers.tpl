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
Config checksum annotations for the Ontoserver pod template.

Without these, `helm upgrade` that changes only a secret value updates the Secret object and
leaves the pod template byte-identical, so no rollout happens and the running pods keep the
old value indefinitely. Ontoserver reads all of this configuration as environment variables,
which are resolved once at container start — unlike a mounted file, a Secret update is never
picked up by a running pod.

These hash the *values*, not the rendered manifests that the Helm documentation's canonical
pattern uses. Hashing the rendered Secret would fold in the common labels, which carry
helm.sh/chart: ontoserver-<version> — so every chart version bump would roll every pod even
with byte-identical configuration. An Ontoserver restart is expensive (the Lucene index is
re-opened on start), so that trade is not worth making here. Nothing is lost by hashing values
instead: secret.yaml is a straight passthrough of secretConfig, and the one other thing its
template controls — the Secret's name — already appears in the pod template's secretKeyRef,
so a rename rolls the pods on its own.

Deliberately NOT covered:
  - ontoserver.config — rendered directly as env values in the pod template, so a change
    already alters the template hash and rolls the pods without help.
  - ontoserver.existingSecretConfig — a Secret this chart does not own or read. Its content is
    invisible to the template, so rotating it requires an explicit `kubectl rollout restart`.
  - the image pull secrets — consumed only when the kubelet pulls an image. Rolling every pod
    because a registry credential rotated would be disruptive for no benefit; the pods already
    have their image.
  - ontoserver.customization — a user-supplied ConfigMap name, mounted as a volume. Kubelet
    syncs mounted ConfigMap updates in place, and the content is not visible here either.
*/}}
{{- define "ontoserver.configChecksums" -}}
{{- if gt (len .Values.ontoserver.secretConfig) 0 }}
checksum/secret-config: {{ .Values.ontoserver.secretConfig | toYaml | sha256sum }}
{{- end }}
{{- if .Values.ontoserver.externalSecret.enabled }}
{{- /* Only the parts that decide which env vars exist. refreshInterval is excluded (it changes
     no key), and so is externalSecret.imagePullSecret, per the pull-secret note above. Note
     this covers the ExternalSecret *spec*: when the upstream store rotates a value, External
     Secrets rewrites the target Secret and nothing here changes, so that case still needs a
     manual restart — or a reloader. */}}
checksum/external-secret: {{ dict "data" .Values.ontoserver.externalSecret.data "dataFrom" .Values.ontoserver.externalSecret.dataFrom "secretStoreRef" .Values.ontoserver.externalSecret.secretStoreRef | toYaml | sha256sum }}
{{- end }}
{{- end }}

{{/*
Pod-level security settings for the Ontoserver pod template.

Emitted by both deployment.yaml and statefulset.yaml, which must stay identical here — a
setting that applied to only one kind would be a trap for anyone switching between them.

Everything is opt-in and defaults to unset, so an upgrade of an existing release produces a
byte-identical pod spec and does not roll any pods. That is deliberate: the charts have run
without a securityContext since they were written, and imposing one by default would break
releases in ways this chart cannot predict — the Ontoserver image's uid, whether the
persistent volume's existing files are readable under a new fsGroup, and whether the mounted
customization ConfigMap is still readable are all deployment-specific. See the README for a
hardened configuration that has been verified against the images this chart ships.

automountServiceAccountToken is a tri-state, so `with` is wrong: it treats an explicit false
as absent and would silently drop the setting that actually matters. Only a nil value means
"leave it to the cluster default".
*/}}
{{- define "ontoserver.podSecurity" -}}
{{- with .Values.ontoserver.deployment.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if not (kindIs "invalid" .Values.ontoserver.deployment.automountServiceAccountToken) }}
automountServiceAccountToken: {{ .Values.ontoserver.deployment.automountServiceAccountToken }}
{{- end }}
{{- end }}

{{/*
Security context for the chart's `helm test` hook pods.

Unlike the workload pods, these are hardened unconditionally rather than opt-in. They are
chart-owned, ephemeral (they exist only for the duration of a `helm test`) and run nothing but
curl against a mounted script, so there is no existing release whose behaviour could change and
nothing deployment-specific to get wrong.

Doing this is not cosmetic. Cluster policy that audits pod security counts these pods too: on a
cluster with the AKS "allowed users and groups" policy, a release with a fully hardened workload
still reported violations from the test hooks alone, because the policy inspects the manifest and
does not care that curlimages/curl happens to default to a non-root uid.

uid 100 / gid 101 are curl_user / curl_group in curlimages/curl. readOnlyRootFilesystem is safe
only because every test script writes its response bodies to /tmp and each Job mounts an emptyDir
there — keep those together if either is changed.
*/}}
{{- define "ontoserver.testPodSecurity" -}}
automountServiceAccountToken: false
securityContext:
  runAsNonRoot: true
  runAsUser: 100
  runAsGroup: 101
  seccompProfile:
    type: RuntimeDefault
{{- end }}

{{- define "ontoserver.testContainerSecurity" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
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
