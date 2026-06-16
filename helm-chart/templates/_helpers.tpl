{{/*
Return a canonical fullname for resources
*/}}
{{- define "lair.fullname" -}}
{{- printf "%s-lair" .Release.Name -}}
{{- end -}}

{{/*
Create a host whitelist string for n8n
*/}}
{{- define "n8n.hostWhitelist" -}}
{{- $whitelist := list "localhost:5678" (printf "n8n.%s.svc.cluster.local" .Values.namespace) "127.0.0.1:5678" -}}
{{- range .Values.ingress.hosts -}}
  {{- if eq .serviceName "n8n" -}}
    {{- $whitelist = append $whitelist .host -}}
  {{- end -}}
{{- end -}}
{{- join "," $whitelist -}}
{{- end -}}

{{/* Velero credentials secret name */}}
{{- define "lair.veleroCredentialsSecretName" -}}
{{- if .Values.velero.credentials.existingSecret -}}
{{- .Values.velero.credentials.existingSecret -}}
{{- else -}}
velero-credentials
{{- end -}}
{{- end -}}

{{/*
Determine the correct StorageClass name based on platform and creation settings
*/}}
{{- define "lair.storageClassName" -}}
{{- if .Values.createStorageClass -}}
  {{- if eq .Values.global.platform "jetson" -}}
    {{- .Values.global.storageClass -}}
  {{- else -}}
    {{- printf "%s-longhorn" .Values.global.storageClass -}}
  {{- end -}}
{{- else -}}
  {{- .Values.global.storageClass -}}
{{- end -}}
{{- end -}}