# Helm — Kubernetes 패키지 매니저 교육 자료

> Helm은 Kubernetes 애플리케이션을 패키징, 배포, 관리하기 위한 공식 패키지 매니저입니다.

---

## 목차

1. [Helm 개요 및 아키텍처](#1-helm-개요-및-아키텍처)
2. [Helm 3 vs Helm 2 차이점](#2-helm-3-vs-helm-2-차이점)
3. [Chart 구조](#3-chart-구조)
4. [주요 명령어 전체](#4-주요-명령어-전체)
5. [values.yaml 오버라이드 방법](#5-valuesyaml-오버라이드-방법)
6. [실무 예시: nginx-ingress, cert-manager 설치](#6-실무-예시)
7. [Chart 직접 만들기 예시](#7-chart-직접-만들기-예시)
8. [Helmfile 간단 소개](#8-helmfile-간단-소개)
9. [자주 쓰는 패턴 및 팁](#9-자주-쓰는-패턴-및-팁)

---

## 1. Helm 개요 및 아키텍처

### Helm이란?

Helm은 Kubernetes 용 "apt/yum"과 같은 패키지 매니저입니다.  
복잡한 Kubernetes 매니페스트(YAML 파일 묶음)를 **Chart**라는 단위로 패키징하여 쉽게 설치·업그레이드·롤백할 수 있습니다.

```
┌─────────────────────────────────────────────────────────┐
│                     Helm 아키텍처                        │
│                                                         │
│  ┌──────────────┐     helm install    ┌──────────────┐  │
│  │  Helm Client │ ─────────────────▶ │  Kubernetes  │  │
│  │  (helm CLI)  │                    │  API Server  │  │
│  └──────┬───────┘                    └──────────────┘  │
│         │                                               │
│         ▼                                               │
│  ┌──────────────┐                                       │
│  │   Chart      │  ← templates/ + values.yaml          │
│  │  Repository  │                                       │
│  └──────────────┘                                       │
└─────────────────────────────────────────────────────────┘
```

### 핵심 개념

| 개념 | 설명 |
|------|------|
| **Chart** | Kubernetes 리소스를 정의하는 패키지. `Chart.yaml`, `values.yaml`, `templates/` 포함 |
| **Repository** | Chart를 저장하고 배포하는 HTTP 서버 (Artifact Hub, Bitnami 등) |
| **Release** | 클러스터에 설치된 Chart의 인스턴스. 같은 Chart를 여러 번 설치하면 릴리즈가 여러 개 생성됨 |
| **Values** | Chart의 기본 설정값. `values.yaml`에 정의되며 설치 시 오버라이드 가능 |
| **Template** | Go 템플릿 엔진으로 렌더링되는 Kubernetes 매니페스트 |
| **Revision** | 릴리즈의 버전. upgrade/rollback 시 증가 |

### Helm 동작 흐름

```
1. helm install myapp ./mychart
        ↓
2. values.yaml + 사용자 지정값 병합
        ↓
3. templates/*.yaml 렌더링 (Go 템플릿)
        ↓
4. 렌더링된 YAML을 Kubernetes API에 전송
        ↓
5. 릴리즈 정보를 Secret(Helm 3) 또는 ConfigMap(Helm 2)으로 저장
```

---

## 2. Helm 3 vs Helm 2 차이점

| 항목 | Helm 2 | Helm 3 |
|------|--------|--------|
| **서버 컴포넌트** | Tiller (클러스터 내 서버 필요) | ❌ Tiller 제거 (클라이언트 전용) |
| **보안** | Tiller의 과도한 권한 (RBAC 복잡) | kubeconfig 기반 인증, 사용자 권한 직접 사용 |
| **릴리즈 저장소** | ConfigMap (kube-system) | Secret (해당 네임스페이스) |
| **네임스페이스** | 릴리즈가 전역에 저장됨 | 릴리즈가 네임스페이스 단위로 저장됨 |
| **Chart API 버전** | apiVersion: v1 | apiVersion: v2 |
| **3-way merge** | ❌ | ✅ (현재 상태 고려하여 패치) |
| **helm install** | 이름 자동 생성 불가 | `--generate-name` 옵션 추가 |
| **requirements.yaml** | 별도 파일로 의존성 관리 | Chart.yaml의 `dependencies` 섹션으로 통합 |
| **helm test** | Pod 기반 테스트 | 동일하나 개선됨 |

### Tiller 제거가 중요한 이유

```
Helm 2 (Tiller 있음):
  helm client → Tiller (kube-system) → Kubernetes API
  - Tiller가 cluster-admin 권한 필요 → 보안 취약점
  - 멀티 테넌트 환경에서 위험

Helm 3 (Tiller 없음):
  helm client → Kubernetes API (사용자 kubeconfig 사용)
  - 사용자의 RBAC 권한 그대로 사용
  - 보안이 훨씬 단순하고 안전
```

---

## 3. Chart 구조

```
mychart/
├── Chart.yaml          # Chart 메타데이터 (필수)
├── values.yaml         # 기본값 정의 (필수)
├── values.schema.json  # values 유효성 검사 스키마 (선택)
├── charts/             # 의존 Chart들 (서브차트)
├── crds/               # CRD 정의 (설치 시 가장 먼저 적용)
├── templates/          # 매니페스트 템플릿
│   ├── NOTES.txt       # 설치 후 출력될 안내 메시지
│   ├── _helpers.tpl    # 공통 헬퍼 함수/템플릿 정의
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── serviceaccount.yaml
│   └── hpa.yaml
└── .helmignore         # 패키징 시 제외할 파일 패턴
```

### Chart.yaml

```yaml
apiVersion: v2          # Helm 3 = v2, Helm 2 = v1
name: mychart
description: A simple web app chart
type: application       # application 또는 library
version: 0.1.0          # Chart 버전 (SemVer)
appVersion: "1.0.0"     # 앱 버전 (정보성)
keywords:
  - webapp
  - nginx
home: https://example.com
sources:
  - https://github.com/myorg/mychart
maintainers:
  - name: 홍길동
    email: hong@example.com
icon: https://example.com/icon.png

# 의존성 (Helm 3)
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled
```

### values.yaml

```yaml
# 복제본 수
replicaCount: 2

# 이미지 설정
image:
  repository: nginx
  pullPolicy: IfNotPresent
  tag: "1.25"

# 서비스 설정
service:
  type: ClusterIP
  port: 80

# Ingress 설정
ingress:
  enabled: false
  className: nginx
  annotations: {}
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []

# 리소스 제한
resources:
  limits:
    cpu: 500m
    memory: 128Mi
  requests:
    cpu: 100m
    memory: 64Mi

# HPA 설정
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

# 환경 변수
env:
  - name: APP_ENV
    value: production

# ConfigMap 데이터
config:
  logLevel: info
  maxConnections: "100"

# PostgreSQL 서브차트 활성화 여부
postgresql:
  enabled: false
```

### templates/_helpers.tpl

`_helpers.tpl`은 공통 네이밍·레이블 생성 함수를 정의하는 파일입니다.  
언더스코어(`_`)로 시작하는 파일은 템플릿 렌더링 대상에서 제외되고 헬퍼로만 사용됩니다.

```yaml
{{/*
앱 이름 반환 (최대 63자)
*/}}
{{- define "mychart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
전체 이름 (release + chart)
*/}}
{{- define "mychart.fullname" -}}
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

{{/*
공통 레이블
*/}}
{{- define "mychart.labels" -}}
helm.sh/chart: {{ include "mychart.chart" . }}
{{ include "mychart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
셀렉터 레이블
*/}}
{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

### templates/deployment.yaml 예시

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 80
          env:
            {{- toYaml .Values.env | nindent 12 }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

---

## 4. 주요 명령어 전체

### 4.1 Repository 관리

```bash
# 저장소 추가
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add stable https://charts.helm.sh/stable
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io

# 저장소 목록 조회
helm repo list

# 저장소 인덱스 업데이트 (최신 차트 반영)
helm repo update

# 특정 저장소 업데이트
helm repo update bitnami

# 저장소 제거
helm repo remove bitnami
```

### 4.2 Chart 검색

```bash
# 로컬 저장소에서 검색
helm search repo nginx
helm search repo nginx --versions          # 모든 버전 표시
helm search repo nginx --version "4.x.x"  # 특정 버전 범위

# Artifact Hub(공개 허브)에서 검색
helm search hub nginx
helm search hub wordpress --max-col-width 80
```

### 4.3 설치 / 업그레이드 / 롤백 / 삭제

```bash
# 기본 설치
helm install myrelease bitnami/nginx

# 네임스페이스 지정
helm install myrelease bitnami/nginx -n mynamespace --create-namespace

# values 파일 지정
helm install myrelease bitnami/nginx -f myvalues.yaml

# --set 으로 값 오버라이드
helm install myrelease bitnami/nginx --set replicaCount=3

# 특정 버전 설치
helm install myrelease bitnami/nginx --version 15.0.0

# 로컬 Chart 설치
helm install myrelease ./mychart

# dry-run (실제 설치 없이 렌더링만)
helm install myrelease bitnami/nginx --dry-run --debug

# 이름 자동 생성
helm install bitnami/nginx --generate-name

# 설치 또는 업그레이드 (멱등성 보장)
helm upgrade --install myrelease bitnami/nginx -f myvalues.yaml -n mynamespace --create-namespace

# 업그레이드
helm upgrade myrelease bitnami/nginx --set image.tag=1.26

# 업그레이드 + values 파일 변경
helm upgrade myrelease bitnami/nginx -f newvalues.yaml

# 업그레이드 실패 시 자동 롤백
helm upgrade myrelease bitnami/nginx --atomic --timeout 5m

# 롤백 (이전 버전으로)
helm rollback myrelease

# 특정 revision으로 롤백
helm rollback myrelease 2

# 삭제
helm uninstall myrelease
helm uninstall myrelease -n mynamespace

# 삭제 시 히스토리도 함께 제거
helm uninstall myrelease --keep-history  # 히스토리 유지
```

### 4.4 릴리즈 조회

```bash
# 현재 네임스페이스의 릴리즈 목록
helm list
helm ls

# 모든 네임스페이스
helm list -A
helm list --all-namespaces

# 특정 네임스페이스
helm list -n mynamespace

# 실패한 릴리즈 포함
helm list --failed
helm list --all  # pending, failed 포함 모두

# 릴리즈 상세 상태
helm status myrelease
helm status myrelease -n mynamespace

# 업그레이드 히스토리
helm history myrelease
helm history myrelease --max 5  # 최근 5개만
```

### 4.5 Chart 다운로드 및 정보 확인

```bash
# Chart 다운로드 (압축 파일)
helm pull bitnami/nginx
helm pull bitnami/nginx --version 15.0.0

# 다운로드 + 압축 해제
helm pull bitnami/nginx --untar

# 특정 경로에 다운로드
helm pull bitnami/nginx --destination /tmp/charts

# Chart 정보 확인
helm show chart bitnami/nginx       # Chart.yaml 출력
helm show values bitnami/nginx      # 기본 values.yaml 출력
helm show readme bitnami/nginx      # README.md 출력
helm show all bitnami/nginx         # 전체 정보 출력

# 실제 배포된 values 확인
helm get values myrelease           # 사용자가 지정한 값
helm get values myrelease --all     # 기본값 포함 모든 값
helm get values myrelease -o json   # JSON 형식

# 배포된 매니페스트 확인
helm get manifest myrelease

# 배포 정보 전체 확인
helm get all myrelease

# 배포된 노트 확인
helm get notes myrelease
```

### 4.6 Chart 개발

```bash
# 스캐폴딩 생성 (기본 구조 자동 생성)
helm create mychart

# 문법 검사 (lint)
helm lint ./mychart
helm lint ./mychart -f myvalues.yaml  # 특정 values로 검사

# 템플릿 렌더링 (실제 배포 없이 YAML 확인)
helm template myrelease ./mychart
helm template myrelease ./mychart -f myvalues.yaml
helm template myrelease ./mychart --set replicaCount=3
helm template myrelease ./mychart > rendered.yaml  # 파일로 저장

# Chart 패키징 (tgz 생성)
helm package ./mychart
helm package ./mychart --version 0.2.0
helm package ./mychart --destination /tmp/packages

# 의존성 업데이트 (charts/ 폴더에 서브차트 다운로드)
helm dependency update ./mychart
helm dependency list ./mychart
helm dependency build ./mychart  # 이미 있는 경우 재빌드
```

---

## 5. values.yaml 오버라이드 방법

### --set (키=값 형식으로 직접 지정)

```bash
# 단순 값 설정
helm install myapp ./mychart --set replicaCount=3

# 중첩된 값 설정 (점 표기법)
helm install myapp ./mychart --set image.tag=1.26

# 여러 값 동시 설정
helm install myapp ./mychart --set replicaCount=3,image.tag=1.26

# 배열 값 설정
helm install myapp ./mychart --set ingress.hosts[0].host=myapp.example.com

# 중첩 배열
helm install myapp ./mychart --set ingress.hosts[0].paths[0].path=/

# 값에 쉼표 포함 시 (이스케이프)
helm install myapp ./mychart --set config="a\,b\,c"
```

### --set-string (값을 문자열로 강제)

```bash
# 숫자가 문자열이어야 할 때 유용
helm install myapp ./mychart --set-string image.tag=1.26
helm install myapp ./mychart --set-string annotations."kubernetes\.io/ingress\.class"=nginx
```

### --set-file (파일 내용을 값으로 설정)

```bash
# 파일 내용을 값으로 설정 (인증서, 스크립트 등)
helm install myapp ./mychart --set-file config.script=./myscript.sh
helm install myapp ./mychart --set-file tls.cert=./tls.crt
```

### -f / --values (values 파일 지정)

```bash
# 단일 values 파일
helm install myapp ./mychart -f myvalues.yaml

# 여러 values 파일 (뒤에 오는 파일이 앞 파일을 오버라이드)
helm install myapp ./mychart -f base.yaml -f override.yaml

# 환경별 values 파일 패턴
helm install myapp ./mychart \
  -f values/base.yaml \
  -f values/production.yaml \
  --set image.tag=v1.5.0
```

### 오버라이드 우선순위

```
낮음 ──────────────────────────────────── 높음
Chart 기본값 < -f 파일 < --set < --set-string
```

### 실전 예시: production.yaml

```yaml
# values/production.yaml
replicaCount: 5

image:
  tag: "v1.5.0"

resources:
  limits:
    cpu: 2000m
    memory: 512Mi
  requests:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: myapp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: myapp-tls
      hosts:
        - myapp.example.com
```

---

## 6. 실무 예시

### 6.1 NGINX Ingress Controller 설치

```bash
# 저장소 추가
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 기본 설치
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# 커스텀 values로 설치
cat > ingress-values.yaml << 'EOF'
controller:
  replicaCount: 2
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
  metrics:
    enabled: true
  config:
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
    proxy-body-size: "50m"
EOF

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  -f ingress-values.yaml

# 설치 확인
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
helm status ingress-nginx -n ingress-nginx

# 업그레이드
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  -f ingress-values.yaml

# 삭제
helm uninstall ingress-nginx -n ingress-nginx
```

### 6.2 cert-manager 설치 (TLS 인증서 자동 관리)

```bash
# 저장소 추가
helm repo add jetstack https://charts.jetstack.io
helm repo update

# CRD 설치 (cert-manager는 CRD 별도 설치 권장)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml

# cert-manager 설치
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.14.0 \
  --set installCRDs=false  # 이미 위에서 설치했으므로

# 설치 확인
kubectl get pods -n cert-manager
helm status cert-manager -n cert-manager

# Let's Encrypt ClusterIssuer 생성 (cert-manager 설치 후)
cat > clusterissuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

kubectl apply -f clusterissuer.yaml

# 자기 서명 ClusterIssuer (내부용)
cat > selfsigned-issuer.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
EOF
kubectl apply -f selfsigned-issuer.yaml
```

### 6.3 Prometheus Stack 설치 (모니터링)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

cat > monitoring-values.yaml << 'EOF'
grafana:
  adminPassword: "mySecurePassword"
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - grafana.example.com
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.example.com
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod

prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          resources:
            requests:
              storage: 50Gi
EOF

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f monitoring-values.yaml
```

---

## 7. Chart 직접 만들기 예시

### 웹앱 Chart 생성 (Node.js 예시)

```bash
# Chart 스캐폴딩
helm create webapp

# 자동 생성된 구조 확인
ls -la webapp/
```

### Chart.yaml 수정

```yaml
# webapp/Chart.yaml
apiVersion: v2
name: webapp
description: Simple Node.js web application
type: application
version: 0.1.0
appVersion: "1.0.0"
```

### values.yaml 수정

```yaml
# webapp/values.yaml
replicaCount: 2

image:
  repository: myregistry/webapp
  pullPolicy: IfNotPresent
  tag: "latest"

service:
  type: ClusterIP
  port: 3000
  targetPort: 3000

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  hosts:
    - host: webapp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  limits:
    cpu: 500m
    memory: 256Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

env:
  NODE_ENV: production
  PORT: "3000"

configmap:
  config.json: |
    {
      "logLevel": "info",
      "maxConnections": 100
    }
```

### templates/configmap.yaml

```yaml
# webapp/templates/configmap.yaml
{{- if .Values.configmap }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "webapp.fullname" . }}-config
  labels:
    {{- include "webapp.labels" . | nindent 4 }}
data:
  {{- range $key, $value := .Values.configmap }}
  {{ $key }}: |
    {{- $value | nindent 4 }}
  {{- end }}
{{- end }}
```

### templates/deployment.yaml (커스텀)

```yaml
# webapp/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "webapp.fullname" . }}
  labels:
    {{- include "webapp.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "webapp.selectorLabels" . | nindent 6 }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        {{- include "webapp.selectorLabels" . | nindent 8 }}
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
          env:
            {{- range $key, $value := .Values.env }}
            - name: {{ $key }}
              value: {{ $value | quote }}
            {{- end }}
          volumeMounts:
            {{- if .Values.configmap }}
            - name: config
              mountPath: /app/config
              readOnly: true
            {{- end }}
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
      volumes:
        {{- if .Values.configmap }}
        - name: config
          configMap:
            name: {{ include "webapp.fullname" . }}-config
        {{- end }}
```

### templates/NOTES.txt

```
Thank you for installing {{ .Chart.Name }}!

Your application has been deployed!

To get the application URL:
{{- if .Values.ingress.enabled }}
  http{{ if $.Values.ingress.tls }}s{{ end }}://{{ (first .Values.ingress.hosts).host }}
{{- else if contains "NodePort" .Values.service.type }}
  export NODE_PORT=$(kubectl get svc {{ include "webapp.fullname" . }} -n {{ .Release.Namespace }} -o jsonpath="{.spec.ports[0].nodePort}")
  export NODE_IP=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://$NODE_IP:$NODE_PORT
{{- else }}
  kubectl port-forward svc/{{ include "webapp.fullname" . }} 3000:{{ .Values.service.port }} -n {{ .Release.Namespace }}
  Then visit: http://localhost:3000
{{- end }}

Release: {{ .Release.Name }}
Namespace: {{ .Release.Namespace }}
Chart version: {{ .Chart.Version }}
App version: {{ .Chart.AppVersion }}
```

### Chart 검증 및 설치

```bash
# 문법 검사
helm lint ./webapp

# 렌더링 미리보기
helm template myapp ./webapp -f myvalues.yaml

# 설치
helm install myapp ./webapp -n webapp --create-namespace

# 패키징
helm package ./webapp
# → webapp-0.1.0.tgz 생성

# 로컬 저장소에서 서비스 (테스트용)
helm serve  # Helm 3에서는 직접 지원하지 않음
# OCI 또는 ChartMuseum 사용 권장
```

---

## 8. Helmfile 간단 소개

Helmfile은 여러 Helm 릴리즈를 **선언적**으로 관리하는 도구입니다.  
여러 Chart를 한 번에 배포하고, 환경별 설정을 관리하는 데 유용합니다.

### 설치

```bash
# macOS
brew install helmfile

# Linux
curl -LO https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_amd64.tar.gz
tar -xzf helmfile_linux_amd64.tar.gz
sudo mv helmfile /usr/local/bin/
```

### helmfile.yaml 예시

```yaml
# helmfile.yaml
repositories:
  - name: ingress-nginx
    url: https://kubernetes.github.io/ingress-nginx
  - name: jetstack
    url: https://charts.jetstack.io
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts

helmDefaults:
  wait: true
  timeout: 600
  createNamespace: true

releases:
  # NGINX Ingress
  - name: ingress-nginx
    namespace: ingress-nginx
    chart: ingress-nginx/ingress-nginx
    version: 4.9.0
    values:
      - values/ingress-nginx.yaml

  # cert-manager
  - name: cert-manager
    namespace: cert-manager
    chart: jetstack/cert-manager
    version: v1.14.0
    set:
      - name: installCRDs
        value: true

  # Prometheus Stack
  - name: kube-prometheus-stack
    namespace: monitoring
    chart: prometheus-community/kube-prometheus-stack
    version: 56.x.x
    values:
      - values/monitoring.yaml
    needs:
      - ingress-nginx/ingress-nginx  # 의존성 순서

  # 로컬 앱
  - name: myapp
    namespace: production
    chart: ./webapp
    values:
      - values/base.yaml
      - values/{{ requiredEnv "ENV" }}.yaml  # ENV 환경변수 필수
```

### Helmfile 사용법

```bash
# 저장소 동기화
helmfile repos

# 전체 배포 (sync)
helmfile sync

# 특정 릴리즈만
helmfile sync --selector name=myapp

# 변경 사항 미리보기 (diff)
helmfile diff

# 삭제
helmfile destroy

# 환경 변수와 함께
ENV=production helmfile sync

# 환경별 파일 분리
helmfile --environment production sync
```

### 환경별 helmfile

```yaml
# helmfile.yaml 에서 environments 사용
environments:
  staging:
    values:
      - environments/staging.yaml
  production:
    values:
      - environments/production.yaml

releases:
  - name: myapp
    values:
      - values/base.yaml
      - values/{{ .Environment.Name }}.yaml
```

---

## 9. 자주 쓰는 패턴 및 팁

### 패턴 1: 멱등적 배포 (CI/CD에서 필수)

```bash
# install 또는 upgrade를 하나의 명령으로
helm upgrade --install myapp ./mychart \
  --namespace production \
  --create-namespace \
  -f values/production.yaml \
  --atomic \          # 실패 시 자동 롤백
  --timeout 5m \
  --wait              # 모든 Pod가 Ready 될 때까지 대기
```

### 패턴 2: 배포 전 변경사항 확인

```bash
# helm-diff 플러그인 설치
helm plugin install https://github.com/databus23/helm-diff

# 현재 배포와 차이점 확인
helm diff upgrade myapp ./mychart -f values/production.yaml -n production
```

### 패턴 3: 렌더링된 YAML 저장 및 kubectl로 적용

```bash
# YAML만 추출하여 GitOps 파이프라인에 활용
helm template myapp ./mychart \
  -f values/production.yaml \
  --include-crds \
  > rendered/production.yaml

kubectl apply -f rendered/production.yaml
```

### 패턴 4: ConfigMap 변경 시 Deployment 자동 재시작

```yaml
# templates/deployment.yaml
template:
  metadata:
    annotations:
      # ConfigMap 내용이 바뀌면 checksum이 바뀌어 Pod 재시작 트리거
      checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
```

### 패턴 5: 공통 레이블/어노테이션 추가

```yaml
# values.yaml
commonLabels:
  team: backend
  project: myproject
  environment: production

commonAnnotations:
  contact: "backend-team@example.com"
  documentation: "https://docs.example.com/myapp"
```

```yaml
# templates/deployment.yaml
metadata:
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
    {{- with .Values.commonLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  annotations:
    {{- with .Values.commonAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
```

### 패턴 6: 조건부 리소스 생성

```yaml
# templates/ingress.yaml
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}
```

### 패턴 7: required 함수로 필수값 검증

```yaml
# templates/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "mychart.fullname" . }}-secret
data:
  # values.yaml에 db.password가 없으면 에러 발생
  db-password: {{ required "db.password is required!" .Values.db.password | b64enc }}
```

### 유용한 팁 모음

```bash
# 1. 릴리즈의 실제 적용된 values 확인
helm get values myapp -n production --all

# 2. 배포된 매니페스트 확인
helm get manifest myapp -n production

# 3. 히스토리 확인 및 특정 버전으로 롤백
helm history myapp -n production
helm rollback myapp 3 -n production

# 4. 네임스페이스 없이 전체 릴리즈 확인
helm list -A

# 5. 특정 Chart 버전의 기본값 확인
helm show values ingress-nginx/ingress-nginx --version 4.9.0

# 6. 플러그인 목록
helm plugin list

# 7. 환경 정보 확인
helm env

# 8. 캐시/데이터 경로 확인
helm env HELM_CACHE_HOME
helm env HELM_DATA_HOME
helm env HELM_CONFIG_HOME

# 9. OCI 레지스트리에서 Chart 가져오기 (Helm 3.8+)
helm pull oci://registry.example.com/charts/myapp --version 1.0.0
helm install myapp oci://registry.example.com/charts/myapp --version 1.0.0

# 10. 릴리즈 네임스페이스 이동 (불가 - 재설치 필요)
helm uninstall myapp -n old-namespace
helm install myapp ./mychart -n new-namespace
```

### 주의사항 및 Best Practice

```
✅ DO:
- 항상 --namespace를 명시적으로 지정
- values.yaml에 민감정보 넣지 않기 (Secret 또는 외부 시크릿 관리 사용)
- Chart 버전 고정하기 (--version 옵션)
- helm upgrade --install로 CI/CD에서 멱등성 보장
- helm diff로 변경 사항 사전 확인
- values.yaml에 required()로 필수값 검증

❌ DON'T:
- helm install과 kubectl apply 혼용 (충돌 가능)
- 프로덕션에서 latest 태그 사용
- values.yaml에 비밀번호/토큰 직접 저장
- 테스트 없이 프로덕션 직접 업그레이드
```

---

*최종 업데이트: 2026-05-08*
