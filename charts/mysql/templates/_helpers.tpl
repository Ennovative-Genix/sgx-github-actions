{{/*
Fully qualified name. Set fullnameOverride so the Deployment / pod label stays vistamysql.
*/}}
{{- define "mysql.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "mysql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector matches the pre-Helm manifest: app: <name>. Selectors are immutable, do not add labels here.
*/}}
{{- define "mysql.selectorLabels" -}}
app: {{ include "mysql.fullname" . }}
{{- end }}

{{- define "mysql.labels" -}}
helm.sh/chart: {{ include "mysql.chart" . }}
{{ include "mysql.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Image: prefer digest, else tag, else latest. CI passes --set image.repository / image.tag.
*/}}
{{- define "mysql.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else if .Values.image.tag }}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- else }}
{{- printf "%s:latest" .Values.image.repository }}
{{- end }}
{{- end }}

{{- define "mysql.serviceName" -}}
{{- default (include "mysql.fullname" .) .Values.service.name }}
{{- end }}

{{- define "mysql.claimName" -}}
{{- default (printf "%s-data" (include "mysql.fullname" .)) .Values.persistence.existingClaim }}
{{- end }}
