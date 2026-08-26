{{/*
Shared JobSpec used by the CronJob and the optional revision-named run Job.
*/}}
{{- define "chc-mirror.jobSpec" -}}
backoffLimit: {{ .Values.backoffLimit }}
{{- if .Values.activeDeadlineSeconds }}
activeDeadlineSeconds: {{ .Values.activeDeadlineSeconds }}
{{- end }}
template:
  metadata:
    labels:
      {{- include "chc-mirror.selectorLabels" . | nindent 6 }}
      {{- with .Values.podLabels }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    annotations:
      gke-gcsfuse/volumes: "true"
      {{- with .Values.gcs.sidecar.cpuLimit }}
      gke-gcsfuse/cpu-limit: {{ . | quote }}
      {{- end }}
      {{- with .Values.gcs.sidecar.memoryLimit }}
      gke-gcsfuse/memory-limit: {{ . | quote }}
      {{- end }}
      {{- with .Values.gcs.sidecar.ephemeralStorageLimit }}
      gke-gcsfuse/ephemeral-storage-limit: {{ . | quote }}
      {{- end }}
      {{- with .Values.podAnnotations }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
  spec:
    restartPolicy: Never
    serviceAccountName: {{ include "chc-mirror.serviceAccountName" . }}
    {{- with .Values.imagePullSecrets }}
    imagePullSecrets:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    containers:
      - name: wget
        image: {{ include "chc-mirror.image" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        env:
          - name: BASE_URL
            value: {{ .Values.wget.baseUrl | quote }}
          - name: GCS_MOUNT
            value: {{ .Values.gcs.mountPath | quote }}
          - name: MIRROR_PREFIX
            value: {{ .Values.gcs.mirrorPrefix | quote }}
        command: ["/bin/sh", "-c"]
        args:
          - |
            set -euo pipefail
            apk add --no-cache wget
            DEST_ROOT="${GCS_MOUNT}/${MIRROR_PREFIX}"
            mkdir -p "${DEST_ROOT}"
{{- range $i, $entry := .Values.subfolders }}
{{- if kindIs "string" $entry }}
{{- fail (printf "subfolders[%d] must be an object with path (and optional accept), not a string" $i) }}
{{- end }}
{{- if not $entry.path }}
{{- fail (printf "subfolders[%d].path is required" $i) }}
{{- end }}
            echo "Mirroring ${BASE_URL}/{{ $entry.path }} -> ${DEST_ROOT}/{{ if $entry.accept }} (accept: {{ $entry.accept }}){{ end }}"
            list="$(mktemp)"
            # Spider the tree, then keep only real file URLs (drop dirs / index.html*).
            wget \
{{- range $.Values.wget.spiderArgs }}
              {{ . | quote }} \
{{- end }}
{{- if $entry.accept }}
              "-A" {{ $entry.accept | quote }} \
{{- end }}
              "${BASE_URL}/{{ $entry.path }}" \
              2>&1 \
              | awk '/^--/ { print $3 }' \
              | grep -E '^https?://' \
              | grep -viE 'index\.html' \
              | grep -vE '/$' \
              | grep -vE '/\?' \
              | sort -u \
              > "${list}" || true
            echo "Found $(wc -l < "${list}") URLs to fetch for {{ $entry.path }}"
            if [ -s "${list}" ]; then
              wget \
{{- range $.Values.wget.downloadArgs }}
                {{ . | quote }} \
{{- end }}
                -i "${list}" \
                -P "${DEST_ROOT}/"
            else
              echo "Nothing to download for {{ $entry.path }}"
            fi
            rm -f "${list}"
            echo "Finished {{ $entry.path }}"
{{- end }}
            echo "All mirrors complete"
        volumeMounts:
          - name: sheerwater-public
            mountPath: {{ .Values.gcs.mountPath }}
        {{- with .Values.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    volumes:
      - name: sheerwater-public
        csi:
          driver: {{ .Values.gcs.driver | quote }}
          volumeAttributes:
            bucketName: {{ .Values.gcs.bucket | quote }}
            {{- with .Values.gcs.mountOptions }}
            mountOptions: {{ . | quote }}
            {{- end }}
            {{- with .Values.gcs.volumeAttributes }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
    {{- with .Values.nodeSelector }}
    nodeSelector:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.affinity }}
    affinity:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.tolerations }}
    tolerations:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
