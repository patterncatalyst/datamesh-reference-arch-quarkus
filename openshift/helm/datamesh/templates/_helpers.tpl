{{- define "datamesh.labels" -}}
app.kubernetes.io/part-of: datamesh
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Container hardening for restricted-v2: no runAsUser, so OpenShift
     assigns a UID from the namespace range. */}}
{{- define "datamesh.containerSecurity" -}}
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
{{- end -}}
