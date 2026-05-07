# Carvel 툴킷 & kapp 교육 자료

> Carvel은 Kubernetes 애플리케이션 빌드·배포·관리를 위한 오픈소스 툴킷입니다.  
> CNCF Sandbox 프로젝트로, 각 도구가 단일 책임 원칙을 따릅니다.

---

## 목차

1. [Carvel 툴킷 개요](#1-carvel-툴킷-개요)
2. [kapp 개요 및 Helm과 차이점](#2-kapp-개요-및-helm과-차이점)
3. [kapp 주요 명령어](#3-kapp-주요-명령어)
4. [ytt 기초](#4-ytt-기초)
5. [kbld 기초](#5-kbld-기초)
6. [kapp-controller & App CRD (GitOps)](#6-kapp-controller--app-crd-gitops)
7. [Carvel vs Helm 비교표](#7-carvel-vs-helm-비교표)
8. [실무 활용 예시](#8-실무-활용-예시)

---

## 1. Carvel 툴킷 개요

### 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Carvel 툴킷 파이프라인                    │
│                                                             │
│  소스 YAML   →  ytt  →  kbld  →  kapp  →  Kubernetes       │
│  (템플릿)       (렌더링)  (이미지고정)  (배포)                │
│                                                             │
│  컨테이너 이미지  →  imgpkg  →  OCI 레지스트리               │
│                    (패키징)                                 │
│                                                             │
│  외부 소스    →  vendir  →  로컬 파일                        │
│               (동기화)                                      │
└─────────────────────────────────────────────────────────────┘
```

### 각 도구 역할

| 도구 | 역할 | 비유 |
|------|------|------|
| **ytt** | YAML 템플릿 엔진 (Starlark 기반 조건/반복/함수 지원) | Helm templates의 대체제 |
| **kbld** | 컨테이너 이미지를 digest(sha256) 해시로 고정 | 이미지 버전 고정 도구 |
| **kapp** | Kubernetes 리소스 배포·관리 (변경 diff, 의존성 순서) | kubectl apply의 스마트한 버전 |
| **imgpkg** | OCI 형식으로 YAML + 이미지를 번들로 패키징 | 앱 배포 패키지 도구 |
| **vendir** | 외부 소스(git, helm, s3 등)를 로컬 디렉토리로 동기화 | 의존성 관리 도구 |

### 설치

```bash
# macOS (Homebrew)
brew tap carvel-dev/carvel
brew install ytt kbld kapp imgpkg vendir

# Linux (공식 스크립트)
wget -O- https://carvel.dev/install.sh | bash

# 개별 바이너리 다운로드
curl -LO https://github.com/carvel-dev/kapp/releases/latest/download/kapp-linux-amd64
chmod +x kapp-linux-amd64
sudo mv kapp-linux-amd64 /usr/local/bin/kapp

# 버전 확인
ytt version
kbld version
kapp version
```

---

## 2. kapp 개요 및 Helm과 차이점

### kapp이란?

kapp(Kubernetes Application)은 Kubernetes 리소스를 **그룹(앱)**으로 관리하는 CLI 도구입니다.  
`kubectl apply`와 달리, 리소스 간 의존성 순서를 지키고, 변경 사항을 상세히 보여주며, 안전한 삭제를 보장합니다.

### kapp의 핵심 특징

```
1. 변경 diff 미리보기
   → 배포 전에 "무엇이 추가/변경/삭제되는지" 정확히 표시

2. 의존성 순서 보장
   → Namespace → CRD → ServiceAccount → Deployment → Service 순서로 배포

3. 안전한 삭제
   → kapp이 관리하는 리소스만 추적하여 정확히 삭제

4. 상태 추적 (Wait Rules)
   → Pod/Deployment/Job 등의 실제 Ready 상태를 확인 후 성공 반환

5. 레이블 기반 리소스 그룹핑
   → kapp.k14s.io/app 레이블로 앱 단위 관리
```

### Helm과의 주요 차이점

| 항목 | Helm | kapp |
|------|------|------|
| **상태 저장 방식** | Secret에 릴리즈 정보 저장 | 리소스에 레이블 추가 (Secret 저장 없음) |
| **변경 미리보기** | helm diff 플러그인 필요 | 기본 내장 (--diff-changes) |
| **의존성 순서** | 기본 미지원 (weight annotation으로 부분 지원) | 완전 자동 (리소스 타입별 순서) |
| **외부 변경 감지** | 3-way merge로 감지 | 실제 상태와 비교하여 감지 |
| **삭제 안전성** | helm uninstall로 전부 삭제 | 관리 대상 리소스만 정확히 삭제 |
| **템플릿 엔진** | Go 템플릿 내장 | 없음 (ytt와 조합하여 사용) |
| **패키지 관리** | Chart(tgz) 형식 | 없음 (imgpkg와 조합) |
| **GitOps** | ArgoCD/FluxCD 필요 | kapp-controller로 네이티브 지원 |
| **CRD 처리** | 별도 단계 필요 | 자동 순서 보장 |

### kapp 작동 방식

```
kapp deploy -a myapp -f ./manifests/
        ↓
1. 현재 클러스터 상태 조회 (kapp.k14s.io/app=myapp 레이블 리소스)
        ↓
2. 새 매니페스트와 diff 계산
        ↓
3. 변경 사항 표시 (추가/변경/삭제)
        ↓
4. 사용자 확인 (--yes 옵션으로 건너뜀)
        ↓
5. 의존성 순서에 따라 리소스 적용
        ↓
6. 모든 리소스가 Ready 상태가 될 때까지 대기
        ↓
7. 완료 보고
```

---

## 3. kapp 주요 명령어

### 3.1 배포 (deploy)

```bash
# 기본 배포
kapp deploy -a myapp -f ./manifests/

# 단일 파일 배포
kapp deploy -a myapp -f deployment.yaml

# 여러 파일/디렉토리
kapp deploy -a myapp -f ./base/ -f ./overlays/production/

# 변경 사항 확인 후 확인 없이 바로 적용
kapp deploy -a myapp -f ./manifests/ --yes
kapp deploy -a myapp -f ./manifests/ -y  # 단축형

# 변경 사항만 미리보기 (실제 배포 안 함)
kapp deploy -a myapp -f ./manifests/ --diff-run

# 변경 사항 상세 표시
kapp deploy -a myapp -f ./manifests/ --diff-changes

# stdin으로 입력
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml | \
  kapp deploy -a nginx -f - --yes

# 네임스페이스 지정
kapp deploy -a myapp -f ./manifests/ -n production --yes

# 특정 레이블로 앱 구분
kapp deploy -a myapp \
  --into-ns production \  # 리소스를 특정 NS로 강제
  -f ./manifests/ --yes

# 대기 타임아웃 설정
kapp deploy -a myapp -f ./manifests/ --wait-timeout 10m --yes

# 배포 후 상태 확인 비활성화 (빠른 배포)
kapp deploy -a myapp -f ./manifests/ --wait=false --yes
```

### 3.2 삭제 (delete)

```bash
# 앱 삭제 (kapp이 관리하는 모든 리소스 삭제)
kapp delete -a myapp

# 확인 없이 삭제
kapp delete -a myapp --yes

# 네임스페이스 지정
kapp delete -a myapp -n production --yes

# 변경 사항 미리보기 (어떤 리소스가 삭제되는지 확인)
kapp delete -a myapp --diff-run
```

### 3.3 상태 조회 (inspect / list)

```bash
# 앱이 관리하는 리소스 목록 조회
kapp inspect -a myapp

# 상세 조회 (트리 구조)
kapp inspect -a myapp --tree

# 특정 네임스페이스
kapp inspect -a myapp -n production

# 전체 앱 목록 조회
kapp list
kapp ls

# 특정 네임스페이스의 앱 목록
kapp list -n production

# 모든 네임스페이스의 앱 목록
kapp list -A

# 앱 변경 이력
kapp app-change list -a myapp
kapp app-change list -a myapp -n production

# 특정 배포의 상세 diff
kapp app-change diff -a myapp CHANGE_NAME
```

### 3.4 로그 (logs)

```bash
# 앱의 모든 Pod 로그 스트리밍
kapp logs -a myapp

# 특정 Pod 레이블 필터
kapp logs -a myapp --pod-name my-pod

# 과거 로그 포함
kapp logs -a myapp --previous

# 타임스탬프 표시
kapp logs -a myapp --timestamps

# 특정 컨테이너
kapp logs -a myapp -c mycontainer
```

### 3.5 주요 옵션 정리

```bash
# --diff-changes : 리소스별 상세 변경 내용 표시
kapp deploy -a myapp -f ./manifests/ --diff-changes

# --diff-run : 실제 배포 없이 diff만 확인
kapp deploy -a myapp -f ./manifests/ --diff-run

# --yes / -y : 사용자 확인 단계 건너뜀 (CI/CD에서 사용)
kapp deploy -a myapp -f ./manifests/ --yes

# --app / -a : 앱 이름 지정 (그룹핑 단위)
kapp deploy --app myapp -f ./manifests/

# --into-ns : 리소스를 특정 네임스페이스로 강제
kapp deploy -a myapp --into-ns production -f ./manifests/ --yes

# --filter : 특정 타입만 조회
kapp inspect -a myapp --filter '{"kinds":["Deployment","Service"]}'

# --wait-timeout : 대기 타임아웃
kapp deploy -a myapp -f ./manifests/ --wait-timeout 15m --yes
```

### 3.6 app-change 명령어

```bash
# 앱의 변경 이력 목록
kapp app-change list -a myapp

# 특정 변경의 diff 확인
kapp app-change diff -a myapp CHANGE_NAME

# 변경 이력 삭제 (오래된 이력 정리)
kapp app-change gc -a myapp --max 10  # 최근 10개만 유지
```

---

## 4. ytt 기초

### ytt란?

ytt(YAML Templating Tool)는 Starlark(Python 기반) 언어를 사용하여 YAML 파일을 동적으로 생성하는 템플릿 엔진입니다.  
Go 템플릿(Helm) 대비 더 강력한 프로그래밍 기능을 제공합니다.

### 기본 사용법

```bash
# 단일 파일 렌더링
ytt -f deployment.yaml

# 디렉토리 렌더링
ytt -f ./config/

# values 파일 지정
ytt -f ./config/ -f values.yaml

# 커맨드라인 값 오버라이드
ytt -f ./config/ --data-value image.tag=1.26

# 파일로 저장
ytt -f ./config/ -f values.yaml > rendered.yaml

# kapp과 파이프라인
ytt -f ./config/ -f values.yaml | kapp deploy -a myapp -f - --yes
```

### 데이터 값 정의 (schema)

```yaml
# schema.yaml
#@data/values-schema
---
app:
  name: myapp
  replicas: 2
  
image:
  repository: nginx
  tag: "1.25"
  
service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  host: ""
```

### 데이터 값 오버라이드

```yaml
# values.yaml
#@data/values
---
app:
  replicas: 5

image:
  tag: "1.26"

ingress:
  enabled: true
  host: myapp.example.com
```

### Deployment 템플릿

```yaml
# deployment.yaml
#@ load("@ytt:data", "data")

apiVersion: apps/v1
kind: Deployment
metadata:
  name: #@ data.values.app.name
  labels:
    app: #@ data.values.app.name
spec:
  replicas: #@ data.values.app.replicas
  selector:
    matchLabels:
      app: #@ data.values.app.name
  template:
    metadata:
      labels:
        app: #@ data.values.app.name
    spec:
      containers:
        - name: #@ data.values.app.name
          image: #@ data.values.image.repository + ":" + data.values.image.tag
          ports:
            - containerPort: #@ data.values.service.port
```

### 조건문 (if/else)

```yaml
# ingress.yaml
#@ load("@ytt:data", "data")

#@ if data.values.ingress.enabled:
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: #@ data.values.app.name
spec:
  rules:
    - host: #@ data.values.ingress.host
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: #@ data.values.app.name
                port:
                  number: #@ data.values.service.port
#@ end
```

### 반복문 (for loop)

```yaml
# configmap.yaml
#@ load("@ytt:data", "data")

#@ def make_env(envs):
#@   result = {}
#@   for env in envs:
#@     result[env.name] = env.value
#@   end
#@   return result
#@ end

apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data: #@ make_env(data.values.env)
```

```yaml
# values.yaml
#@data/values
---
env:
  - name: LOG_LEVEL
    value: info
  - name: DB_HOST
    value: postgres.default.svc
  - name: MAX_CONN
    value: "100"
```

### 함수 정의 및 재사용

```yaml
# _helpers.lib.yaml
#@ def labels(name):
app.kubernetes.io/name: #@ name
app.kubernetes.io/managed-by: kapp
#@ end

#@ def resource_limits(cpu, memory):
limits:
  cpu: #@ cpu
  memory: #@ memory
requests:
  cpu: #@ int(int(cpu.rstrip("m")) / 4).__str__() + "m"
  memory: #@ int(int(memory.rstrip("Mi")) / 2).__str__() + "Mi"
#@ end
```

```yaml
# deployment.yaml
#@ load("@ytt:data", "data")
#@ load("_helpers.lib.yaml", "labels", "resource_limits")

apiVersion: apps/v1
kind: Deployment
metadata:
  name: #@ data.values.app.name
  labels: #@ labels(data.values.app.name)
spec:
  template:
    spec:
      containers:
        - name: app
          resources: #@ resource_limits("500m", "256Mi")
```

### 오버레이(Overlay) — 기존 YAML 수정

```yaml
# overlay.yaml
#@ load("@ytt:overlay", "overlay")

#@overlay/match by=overlay.subset({"kind": "Deployment"})
---
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      #@overlay/match missing_ok=True
      nodeSelector:
        kubernetes.io/os: linux
```

```bash
# 오버레이 적용
ytt -f ./base/ -f overlay.yaml
```

---

## 5. kbld 기초

### kbld란?

kbld(Kubernetes Build and Lock)는 컨테이너 이미지 태그를 **digest(sha256 해시)로 교체**하는 도구입니다.  
`nginx:1.25` → `nginx@sha256:abc123...` 형태로 변환하여 재현 가능한 배포를 보장합니다.

### 기본 사용법

```bash
# 이미지 태그를 digest로 교체
kbld -f deployment.yaml

# 디렉토리 전체
kbld -f ./manifests/

# lock 파일 생성 (digest 정보 저장)
kbld -f ./manifests/ --lock-output .kbld/lock.yaml

# lock 파일 사용하여 재현 가능한 배포
kbld -f ./manifests/ --lock .kbld/lock.yaml

# ytt + kbld + kapp 파이프라인
ytt -f ./config/ -f values.yaml | kbld -f - | kapp deploy -a myapp -f - --yes
```

### kbld 설정 (이미지 빌드/교체 설정)

```yaml
# .kbld/config.yaml
apiVersion: kbld.k14s.io/v1alpha1
kind: Config
sources:
  # 로컬 소스에서 이미지 빌드
  - image: myregistry/myapp
    path: .
    docker:
      buildArgs:
        - --no-cache
      
  # 특정 이미지 교체 매핑
  - image: myapp-backend
    path: ./backend/

destinations:
  # 빌드된 이미지를 특정 레지스트리에 푸시
  - image: myregistry/myapp
    newImage: registry.example.com/myapp

# 특정 이미지를 다른 이미지로 교체
overrides:
  - image: nginx
    newImage: registry.example.com/nginx:1.25
```

### lock 파일 예시

```yaml
# .kbld/lock.yaml (자동 생성됨)
apiVersion: kbld.k14s.io/v1alpha1
kind: Config
minimumRequiredVersion: 0.28.0
overrides:
  - image: nginx:1.25
    newImage: index.docker.io/library/nginx@sha256:a484819eb60211f5299034ac80f6a681b06f89e65866ce91f356ed7c72af059c
    preresolved: true
  - image: myapp:latest
    newImage: registry.example.com/myapp@sha256:bb3d23a6f7...
    preresolved: true
```

### 실전 활용

```bash
# 1. 이미지 빌드 + digest 고정 + 배포
kbld -f ./manifests/ --lock-output .kbld/lock.yaml | \
  kapp deploy -a myapp -f - --yes

# 2. lock 파일로 재현 가능한 배포
kbld -f ./manifests/ --lock .kbld/lock.yaml | \
  kapp deploy -a myapp -f - --yes

# 3. 전체 파이프라인
ytt -f ./config/ -f values/production.yaml | \
  kbld -f - --lock-output .kbld/lock.yaml | \
  kapp deploy -a myapp -f - -n production --yes
```

---

## 6. kapp-controller & App CRD (GitOps)

### kapp-controller란?

kapp-controller는 kapp을 **Kubernetes Operator**로 구현한 것입니다.  
`App` CRD를 통해 GitOps 방식으로 애플리케이션을 지속적으로 동기화합니다.

### 설치

```bash
# kapp-controller 설치
kapp deploy -a kapp-controller \
  -f https://github.com/carvel-dev/kapp-controller/releases/latest/download/release.yml \
  --yes

# 설치 확인
kubectl get pods -n kapp-controller
kubectl get crds | grep kappctrl
```

### App CRD 구조

```yaml
apiVersion: kappctrl.k14s.io/v1alpha1
kind: App
metadata:
  name: myapp
  namespace: production
spec:
  # 동기화 주기
  syncPeriod: 5m
  
  # 소스 설정 (Git, Helm, HTTP, imgpkg 중 선택)
  fetch:
    - git:
        url: https://github.com/myorg/myapp-config
        ref: origin/main
        secretRef:
          name: git-credentials  # 프라이빗 레포의 경우
  
  # 템플릿 처리
  template:
    - ytt:
        paths:
          - config/
        valuesFrom:
          - secretRef:
              name: myapp-values
    - kbld:
        paths:
          - "-"  # stdin (이전 단계 결과)
  
  # 배포 방법
  deploy:
    - kapp:
        intoNs: production
        rawOptions:
          - --wait-timeout=5m
```

### 다양한 소스 설정

```yaml
# Git 소스
fetch:
  - git:
      url: https://github.com/myorg/config
      ref: refs/tags/v1.5.0  # 특정 태그
      subPath: apps/myapp    # 서브디렉토리만

# Helm Chart 소스
fetch:
  - helmChart:
      name: nginx
      version: "15.0.0"
      repository:
        url: https://charts.bitnami.com/bitnami

# HTTP URL 소스
fetch:
  - http:
      url: https://example.com/manifests.yaml

# imgpkg 번들 소스
fetch:
  - imgpkgBundle:
      image: registry.example.com/myapp-bundle:v1.5.0
      secretRef:
        name: registry-credentials

# ConfigMap 소스 (로컬)
fetch:
  - inline:
      paths:
        deployment.yaml: |
          apiVersion: apps/v1
          kind: Deployment
          ...
```

### PackageRepository & Package (Carvel 패키지 관리)

```yaml
# PackageRepository — 패키지 저장소 등록
apiVersion: packaging.carvel.dev/v1alpha1
kind: PackageRepository
metadata:
  name: carvel-packages
  namespace: kapp-controller
spec:
  fetch:
    imgpkgBundle:
      image: registry.example.com/packages:v1.0.0

---
# Package — 사용 가능한 패키지 정의
apiVersion: data.packaging.carvel.dev/v1alpha1
kind: Package
metadata:
  name: myapp.example.com.1.5.0
spec:
  refName: myapp.example.com
  version: 1.5.0
  releaseNotes: "Bug fixes and improvements"
  valuesSchema:
    openAPIv3:
      properties:
        replicaCount:
          type: integer
          default: 2
  template:
    spec:
      fetch:
        - imgpkgBundle:
            image: registry.example.com/myapp:1.5.0
      template:
        - ytt:
            paths: ["config/"]
      deploy:
        - kapp: {}

---
# PackageInstall — 패키지 설치
apiVersion: packaging.carvel.dev/v1alpha1
kind: PackageInstall
metadata:
  name: myapp
  namespace: production
spec:
  packageRef:
    refName: myapp.example.com
    versionSelection:
      constraints: ">=1.5.0 <2.0.0"
  values:
    - secretRef:
        name: myapp-values
```

### GitOps 워크플로우

```
┌─────────────────────────────────────────────────────────┐
│                  kapp-controller GitOps 흐름             │
│                                                         │
│  개발자                    Git Repo          클러스터    │
│    │                          │                  │      │
│    │── Push (values 변경) ──▶ │                  │      │
│    │                          │                  │      │
│    │                     kapp-controller          │      │
│    │                          │◀─ sync (5분마다) ─│      │
│    │                          │                  │      │
│    │              Git에서 최신 설정 가져오기       │      │
│    │                          │                  │      │
│    │              ytt 렌더링 + kbld 이미지 고정   │      │
│    │                          │                  │      │
│    │              kapp deploy (변경 사항만 적용) ──▶     │
│    │                                             │      │
│    │◀──── 상태 확인 (App CRD status) ─────────────│      │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Carvel vs Helm 비교표

### 핵심 기능 비교

| 기능 | Helm | Carvel (kapp + ytt + kbld) |
|------|------|---------------------------|
| **패키지 관리** | ✅ Chart(tgz) 형식 | ✅ imgpkg 번들 (OCI 형식) |
| **템플릿 엔진** | ✅ Go 템플릿 (helm 내장) | ✅ ytt (Starlark 기반, 별도 도구) |
| **배포 관리** | ✅ helm install/upgrade | ✅ kapp deploy |
| **변경 diff** | ⚠️ helm-diff 플러그인 필요 | ✅ 기본 내장 |
| **의존성 순서** | ⚠️ 제한적 (weight annotation) | ✅ 자동 (리소스 타입별) |
| **이미지 해시 고정** | ❌ 없음 | ✅ kbld |
| **GitOps** | ⚠️ ArgoCD/FluxCD 필요 | ✅ kapp-controller |
| **외부 소스 동기화** | ❌ 없음 | ✅ vendir |
| **롤백** | ✅ helm rollback | ⚠️ 제한적 (이전 Git ref로 재배포) |
| **릴리즈 히스토리** | ✅ Secret에 저장 | ⚠️ app-change로 확인 |
| **학습 곡선** | 낮음 (단일 도구) | 높음 (여러 도구 조합) |
| **생태계** | 매우 넓음 (Artifact Hub) | 제한적 (성장 중) |
| **CRD 처리** | ⚠️ 별도 처리 필요 | ✅ 자동 순서 보장 |
| **다중 클러스터** | ⚠️ 별도 설정 | ✅ kapp-controller 지원 |

### 언제 무엇을 선택할까?

```
Helm을 선택해야 할 때:
  ✅ 기존 Helm Chart를 그대로 사용할 때 (nginx-ingress, cert-manager 등)
  ✅ 팀이 Helm에 익숙하고 생태계 활용이 중요할 때
  ✅ 빠른 시작과 넓은 커뮤니티 지원이 필요할 때
  ✅ 단순한 배포 워크플로우일 때

Carvel을 선택해야 할 때:
  ✅ 이미지 재현성이 중요한 보안/컴플라이언스 환경
  ✅ 복잡한 의존성 순서가 있는 대규모 앱
  ✅ 변경 사항의 정확한 diff가 필요한 경우
  ✅ kapp-controller로 GitOps를 네이티브 구현할 때
  ✅ 복잡한 YAML 로직이 필요한 경우 (ytt의 강력한 표현력)
  ✅ VMware/Tanzu 생태계를 사용할 때

함께 사용:
  ✅ Helm Chart를 kapp으로 배포 (Helm fetch + kapp deploy)
  ✅ ytt로 Helm values 동적 생성 후 helm install
```

---

## 8. 실무 활용 예시

### 예시 1: 전체 파이프라인 (ytt + kbld + kapp)

```
project/
├── config/
│   ├── schema.yaml        # ytt 스키마
│   ├── deployment.yaml    # ytt 템플릿
│   ├── service.yaml
│   ├── ingress.yaml
│   └── _helpers.lib.yaml  # 공통 함수
├── values/
│   ├── base.yaml
│   ├── staging.yaml
│   └── production.yaml
└── .kbld/
    └── config.yaml
```

```bash
# 스테이징 배포
ytt -f config/ -f values/base.yaml -f values/staging.yaml | \
  kbld -f - --lock-output .kbld/staging-lock.yaml | \
  kapp deploy -a myapp-staging -f - -n staging --yes

# 프로덕션 배포 (lock 파일 사용으로 동일 이미지 보장)
ytt -f config/ -f values/base.yaml -f values/production.yaml | \
  kbld -f - --lock .kbld/staging-lock.yaml | \
  kapp deploy -a myapp -f - -n production --yes
```

### 예시 2: Helm Chart를 kapp으로 배포

```bash
# Helm Chart를 렌더링하여 kapp으로 배포
helm template ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  -f ingress-values.yaml | \
  kapp deploy -a ingress-nginx -f - -n ingress-nginx --yes

# 변경 사항 확인
helm template ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  -f ingress-values.yaml | \
  kapp deploy -a ingress-nginx -f - -n ingress-nginx --diff-run
```

### 예시 3: kapp-controller로 GitOps 구성

```yaml
# app-production.yaml
apiVersion: kappctrl.k14s.io/v1alpha1
kind: App
metadata:
  name: myapp-production
  namespace: kapp-controller
spec:
  serviceAccountName: kapp-controller-sa
  syncPeriod: 3m
  
  fetch:
    - git:
        url: https://github.com/myorg/config-repo
        ref: refs/heads/main
        subPath: apps/myapp
        secretRef:
          name: github-credentials
  
  template:
    - ytt:
        paths:
          - "."
        valuesFrom:
          - secretRef:
              name: myapp-production-values
    - kbld:
        paths:
          - "-"
  
  deploy:
    - kapp:
        intoNs: production
        rawOptions:
          - --wait-timeout=10m
          - --diff-changes=true
```

```bash
# App 배포
kubectl apply -f app-production.yaml

# 동기화 상태 확인
kubectl get app myapp-production -n kapp-controller
kubectl describe app myapp-production -n kapp-controller

# 즉시 동기화 트리거 (어노테이션 추가)
kubectl annotate app myapp-production \
  -n kapp-controller \
  kapp.k14s.io/update-strategy=always \
  --overwrite
```

### 예시 4: 멀티 환경 관리

```bash
# 환경별 App CRD 관리
# staging-apps.yaml
---
apiVersion: kappctrl.k14s.io/v1alpha1
kind: App
metadata:
  name: myapp-staging
  namespace: kapp-controller
spec:
  syncPeriod: 1m  # 스테이징은 자주 동기화
  fetch:
    - git:
        url: https://github.com/myorg/config
        ref: refs/heads/develop  # develop 브랜치 추적
  template:
    - ytt:
        valuesFrom:
          - secretRef:
              name: staging-values
  deploy:
    - kapp:
        intoNs: staging
---
apiVersion: kappctrl.k14s.io/v1alpha1
kind: App
metadata:
  name: myapp-production
  namespace: kapp-controller
spec:
  syncPeriod: 5m  # 프로덕션은 더 보수적으로
  fetch:
    - git:
        url: https://github.com/myorg/config
        ref: refs/tags/latest-prod  # 태그 추적
  template:
    - ytt:
        valuesFrom:
          - secretRef:
              name: production-values
  deploy:
    - kapp:
        intoNs: production
```

### 예시 5: imgpkg로 번들 만들기

```bash
# 번들 디렉토리 구조
mkdir -p bundle/.imgpkg bundle/config

# 매니페스트 복사
cp ./manifests/*.yaml bundle/config/

# 이미지 목록 파일 생성 (kbld 사용)
kbld -f bundle/config/ --imgpkg-lock-output bundle/.imgpkg/images.yml

# 번들을 레지스트리에 푸시
imgpkg push -b registry.example.com/myapp-bundle:v1.5.0 -f bundle/

# 번들 내용 확인
imgpkg pull -b registry.example.com/myapp-bundle:v1.5.0 -o /tmp/bundle
ls /tmp/bundle/

# 번들에서 배포 (이미지 재배치 포함)
imgpkg pull -b registry.example.com/myapp-bundle:v1.5.0 -o /tmp/bundle
kbld -f /tmp/bundle/config/ --lock /tmp/bundle/.imgpkg/images.yml | \
  kapp deploy -a myapp -f - --yes
```

### 예시 6: vendir로 외부 소스 동기화

```yaml
# vendir.yml
apiVersion: vendir.k14s.io/v1alpha1
kind: Config
directories:
  # Git 레포 동기화
  - path: vendor/k8s-configs
    contents:
      - path: .
        git:
          url: https://github.com/myorg/k8s-configs
          ref: refs/tags/v2.0.0

  # Helm Chart 동기화
  - path: vendor/charts/ingress-nginx
    contents:
      - path: .
        helmChart:
          name: ingress-nginx
          version: "4.9.0"
          repository:
            url: https://kubernetes.github.io/ingress-nginx

  # GitHub 릴리즈 파일 동기화
  - path: vendor/cert-manager
    contents:
      - path: .
        githubRelease:
          slug: cert-manager/cert-manager
          tag: v1.14.0
          assetNames:
            - cert-manager.yaml
```

```bash
# 동기화 실행
vendir sync

# vendor/ 디렉토리에 최신 파일 저장됨
ls vendor/k8s-configs/
ls vendor/charts/ingress-nginx/
ls vendor/cert-manager/

# vendir.lock.yml 생성 (정확한 버전 기록)
cat vendir.lock.yml
```

### 예시 7: CI/CD 파이프라인 통합

```yaml
# .github/workflows/deploy.yaml
name: Deploy to Production

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Carvel tools
        run: |
          wget -O- https://carvel.dev/install.sh | bash
          sudo mv ~/bin/* /usr/local/bin/
      
      - name: Configure kubectl
        uses: azure/k8s-set-context@v3
        with:
          kubeconfig: ${{ secrets.KUBECONFIG }}
      
      - name: Build and push image
        run: |
          docker build -t ${{ env.REGISTRY }}/myapp:${{ github.ref_name }} .
          docker push ${{ env.REGISTRY }}/myapp:${{ github.ref_name }}
      
      - name: Deploy with Carvel
        run: |
          ytt -f config/ \
            -f values/base.yaml \
            -f values/production.yaml \
            --data-value image.tag=${{ github.ref_name }} | \
          kbld -f - --lock-output .kbld/lock.yaml | \
          kapp deploy -a myapp \
            -f - \
            -n production \
            --yes \
            --wait-timeout=10m
      
      - name: Verify deployment
        run: |
          kapp inspect -a myapp -n production
          kubectl get pods -n production
```

---

*최종 업데이트: 2026-05-08*
