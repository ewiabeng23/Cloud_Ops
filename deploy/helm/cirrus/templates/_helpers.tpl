{{- define "cirrus.name" -}}{{ default .Chart.Name .Values.app.name }}{{- end -}}
{{- define "cirrus.fullname" -}}{{ include "cirrus.name" . }}{{- end -}}
{{- define "cirrus.labels" -}}
app.kubernetes.io/name: {{ include "cirrus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
{{- define "cirrus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cirrus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "cirrus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}{{ default (include "cirrus.fullname" .) .Values.serviceAccount.name }}{{- else -}}{{ default "default" .Values.serviceAccount.name }}{{- end -}}
{{- end -}}
