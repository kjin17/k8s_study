# Harbor & Trivy — 프라이빗 컨테이너 레지스트리 교육

> Kubernetes 환경에서 **컨테이너 이미지를 안전하게 저장·관리·배포**하기 위한
> Harbor(프라이빗 레지스트리)와 Trivy(취약점 스캔)를 다룹니다.
> 컨테이너 레지스트리를 처음 접하는 분을 대상으로 작성되었습니다.

---

## 목차

1. [컨테이너 레지스트리란?](#1-컨테이너-레지스트리란)
2. [왜 프라이빗 레지스트리가 필요한가?](#2-왜-프라이빗-레지스트리가-필요한가)
3. [Harbor 소개](#3-harbor-소개)
4. [Harbor 설치](#4-harbor-설치)
5. [Harbor 웹 UI 사용법](#5-harbor-웹-ui-사용법)
6. [Docker CLI로 Harbor 사용하기](#6-docker-cli로-harbor-사용하기)
7. [Helm 차트 저장소로 Harbor 사용하기](#7-helm-차트-저장소로-harbor-사용하기)
8. [Trivy를 활용한 이미지 취약점 스캔](#8-trivy를-활용한-이미지-취약점-스캔)
9. [이미지 관리 전략](#9-이미지-관리-전략)
10. [보안 모범 사례](#10-보안-모범-사례)
11. [CI/CD 파이프라인 연동](#11-cicd-파이프라인-연동)
12. [문제 해결 가이드](#12-문제-해결-가이드)

---

## 1. 컨테이너 레지스트리란?

### 한 문장 정의

> **컨테이너 레지스트리**는 컨테이너 이미지를 저장하고 배포하는 중앙 저장소입니다.
> Git이 소스 코드의 저장소라면, 레지스트리는 **빌드된 컨테이너 이미지의 저장소**입니다.

### 비유로 이해하기

```
┌───────────────────────────────────────────────────────────┐
│                  도서관에 비유하면...                         │
│                                                           │
│   [소스 코드]           [컨테이너 이미지]                    │
│   원고 (작가가 쓴 글)     인쇄된 책                          │
│         ↓                      ↓                          │
│   GitHub (원고 보관소)   레지스트리 (도서관)                  │
│         ↓                      ↓                          │
│   코드 수정/리뷰          이미지 보관/배포                    │
│                                ↓                          │
│                    kubectl (독자가 책을 빌려감)              │
└───────────────────────────────────────────────────────────┘
```

### 퍼블릭 vs 프라이빗 레지스트리

| 구분 | 퍼블릭 레지스트리 | 프라이빗 레지스트리 |
|------|-------------------|---------------------|
| 예시 | Docker Hub, ghcr.io, quay.io | Harbor, Nexus, AWS ECR |
| 접근 | 누구나 Pull 가능 | 인증된 사용자만 접근 |
| 비용 | 무료 (제한적) | 자체 운영 또는 유료 |
| 보안 | 제한적 스캔 | 자체 보안 정책 적용 |
| 속도 | 인터넷 속도 의존 | 내부 네트워크 속도 |
| 용도 | 오픈소스, 공개 이미지 | 기업 내부 이미지 |

### 이미지 주소 구조

```
docker.io/library/nginx:1.25
├────────┤ ├─────┤ ├───┤ ├──┤
레지스트리   프로젝트  이미지  태그

harbor.company.com/backend/api-server:v2.1.0
├────────────────┤ ├─────┤ ├────────┤ ├────┤
  레지스트리       프로젝트   이미지     태그
```

---

## 2. 왜 프라이빗 레지스트리가 필요한가?

### 기업 환경에서의 문제

```
[Docker Hub만 사용할 때]

개발자 A ──push──→  Docker Hub  ←──pull── 운영 서버
개발자 B ──push──→  (퍼블릭)    ←──pull── 스테이징 서버
                       │
                       ├── Rate Limit (무료: 100회/6시간)
                       ├── 소스 코드 유출 위험 (Public Repo)
                       ├── 인터넷 장애 시 Pull 불가
                       └── 취약점 스캔 제한적
```

### 프라이빗 레지스트리가 해결하는 문제

| 문제 | Docker Hub | 프라이빗 레지스트리 |
|------|-----------|---------------------|
| Pull 횟수 제한 | 100회/6시간 (무료) | 무제한 |
| 이미지 보안 | 공개 노출 위험 | 사내 네트워크 격리 |
| 취약점 스캔 | 유료 플랜 필요 | Trivy 통합 무료 |
| 접근 제어 | 기본적 | RBAC, 프로젝트별 권한 |
| 감사 로그 | 제한적 | 모든 Push/Pull 기록 |
| 네트워크 속도 | 인터넷 의존 | 내부 네트워크 (고속) |
| 가용성 | 외부 서비스 의존 | 자체 운영/HA 구성 |

### 프라이빗 레지스트리 비교

| 레지스트리 | 라이선스 | 특징 |
|------------|----------|------|
| **Harbor** | Apache 2.0 (무료) | CNCF Graduated, 취약점 스캔 통합, 복제, RBAC |
| Nexus Repository | 무료/상용 | Maven, npm 등 다목적 저장소 |
| AWS ECR | 종량제 | AWS 네이티브, IAM 연동 |
| GCR/Artifact Registry | 종량제 | GCP 네이티브 |
| Azure ACR | 종량제 | Azure 네이티브 |
| GitLab Registry | 무료 (GitLab 포함) | GitLab CI 통합 |

> **이 교육에서는 CNCF 졸업 프로젝트이자 기능이 가장 풍부한 Harbor를 다룹니다.**

---

## 3. Harbor 소개

### Harbor란?

> **Harbor**는 VMware가 시작하고 CNCF에서 졸업(Graduated)한 오픈소스
> 컨테이너 이미지 레지스트리입니다. Docker Distribution(Registry v2) 위에
> 보안, 접근 제어, 이미지 스캔 등 엔터프라이즈 기능을 추가했습니다.

### 아키텍처

```
┌─────────────────────────────── Harbor ────────────────────────────────┐
│                                                                      │
│  ┌──────────────────────────────────────────────────────────┐        │
│  │                    Nginx (Reverse Proxy)                 │        │
│  │              외부 요청 → 내부 서비스 라우팅                 │        │
│  └──────────┬────────────────────┬──────────────────────────┘        │
│             │                    │                                    │
│  ┌──────────▼──────────┐  ┌─────▼──────────────┐                    │
│  │     Core Service    │  │   Registry (v2)    │                    │
│  │                     │  │                    │                    │
│  │  • 프로젝트 관리     │  │  • 이미지 저장/배포  │                    │
│  │  • 사용자 인증       │  │  • Blob Storage    │                    │
│  │  • RBAC 정책        │  │  • Manifest 관리    │                    │
│  │  • Webhook          │  │                    │                    │
│  └──────┬──────────────┘  └────────────────────┘                    │
│         │                                                            │
│  ┌──────▼──────┐  ┌─────────────┐  ┌──────────────┐                │
│  │  Database   │  │    Redis    │  │  Job Service │                │
│  │ (PostgreSQL)│  │   (Cache)   │  │              │                │
│  │             │  │             │  │ • 복제 작업   │                │
│  │ • 메타데이터 │  │ • 세션 캐시  │  │ • GC 작업    │                │
│  │ • 사용자 정보│  │ • 임시 데이터│  │ • 스캔 작업   │                │
│  └─────────────┘  └─────────────┘  └──────┬───────┘                │
│                                           │                         │
│                                    ┌──────▼───────┐                 │
│                                    │    Trivy      │                 │
│                                    │ (취약점 스캐너) │                 │
│                                    │               │                 │
│                                    │ • CVE 데이터베이스│                │
│                                    │ • 이미지 분석   │                │
│                                    └───────────────┘                 │
└──────────────────────────────────────────────────────────────────────┘
```

### 핵심 기능

| 기능 | 설명 |
|------|------|
| **RBAC** | 프로젝트별 역할 기반 접근 제어 (Admin, Developer, Guest 등) |
| **취약점 스캔** | Trivy 통합 — Push 시 자동 스캔, 정책 기반 배포 차단 |
| **이미지 서명** | Cosign/Notation 지원 — 신뢰할 수 있는 이미지만 배포 |
| **복제** | 레지스트리 간 이미지 자동 복제 (Push/Pull 모드) |
| **Garbage Collection** | 사용하지 않는 이미지 레이어 정리 |
| **Retention Policy** | 보관 정책에 따라 오래된 이미지 자동 삭제 |
| **Webhook** | Push/Pull/Scan 이벤트를 외부 서비스에 알림 |
| **OIDC/LDAP** | 외부 인증 시스템 연동 |
| **감사 로그** | 모든 사용자 활동 기록 |
| **Proxy Cache** | Docker Hub 등 외부 레지스트리 캐싱 |

---

## 4. Harbor 설치

### 4-1. Helm으로 Kubernetes에 설치 (권장)

#### 사전 요구사항

| 항목 | 최솟값 |
|------|--------|
| Kubernetes | 1.22 이상 |
| Helm | 3.x |
| 가용 메모리 | 4 GB 이상 |
| 가용 디스크 | 40 GB 이상 |
| StorageClass | PV 동적 프로비저닝 가능 |

#### 설치 과정

```bash
# 1. Helm 저장소 추가
helm repo add harbor https://helm.goharbor.io
helm repo update

# 2. Namespace 생성
kubectl create namespace harbor

# 3. Harbor 설치 (기본 설정)
helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=nodePort \
  --set expose.tls.auto.commonName=harbor.local \
  --set externalURL=https://harbor.local:30003 \
  --set harborAdminPassword=Harbor12345 \
  --set persistence.persistentVolumeClaim.registry.size=50Gi \
  --set persistence.persistentVolumeClaim.database.size=5Gi \
  --set persistence.persistentVolumeClaim.redis.size=1Gi \
  --set persistence.persistentVolumeClaim.trivy.size=5Gi \
  --wait --timeout 10m

# 4. 설치 확인
kubectl get pods -n harbor
kubectl get svc -n harbor
```

#### Expose 방식 비교

| 방식 | 옵션 | 장점 | 단점 |
|------|------|------|------|
| **NodePort** | `expose.type=nodePort` | 설정 간단 | 포트 번호 고정 필요 |
| **Ingress** | `expose.type=ingress` | 도메인 기반 접근 | Ingress Controller 필요 |
| **LoadBalancer** | `expose.type=loadBalancer` | 외부 IP 자동 할당 | 클라우드/MetalLB 필요 |

#### Ingress 방식 설치 예시

```bash
helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=ingress \
  --set expose.ingress.hosts.core=harbor.example.com \
  --set expose.ingress.className=nginx \
  --set externalURL=https://harbor.example.com \
  --set harborAdminPassword=Harbor12345 \
  --wait --timeout 10m
```

### 4-2. Docker Compose로 설치 (단일 서버)

```bash
# 1. Harbor 오프라인 설치 파일 다운로드
curl -LO https://github.com/goharbor/harbor/releases/download/v2.11.0/harbor-offline-installer-v2.11.0.tgz
tar xzf harbor-offline-installer-v2.11.0.tgz
cd harbor

# 2. 설정 파일 복사 및 수정
cp harbor.yml.tmpl harbor.yml
vi harbor.yml   # hostname, https 설정, 비밀번호 등 수정

# 3. 설치 실행 (Trivy 포함)
./install.sh --with-trivy

# 4. 서비스 확인
docker compose ps
```

#### harbor.yml 주요 설정

```yaml
# 외부 접근 주소
hostname: harbor.example.com

# HTTPS 설정
https:
  port: 443
  certificate: /data/cert/server.crt
  private_key: /data/cert/server.key

# 관리자 초기 비밀번호
harbor_admin_password: Harbor12345

# 데이터 저장 경로
data_volume: /data/harbor

# 데이터베이스 설정
database:
  password: root123
  max_idle_conns: 100
  max_open_conns: 900
```

---

## 5. Harbor 웹 UI 사용법

### 로그인

```
브라우저: https://<harbor-주소>
  사용자: admin
  비밀번호: (설치 시 설정한 비밀번호)
```

### 프로젝트 생성

```
┌────────────────── Harbor 프로젝트 구조 ──────────────────┐
│                                                          │
│  harbor.example.com                                      │
│  ├── library/          ← 기본 프로젝트 (Public)           │
│  │   ├── nginx:1.25                                      │
│  │   └── redis:7.0                                       │
│  ├── backend/          ← 백엔드 팀 프로젝트 (Private)      │
│  │   ├── api-server:v2.1                                 │
│  │   └── worker:v1.3                                     │
│  ├── frontend/         ← 프론트엔드 팀 프로젝트 (Private)  │
│  │   └── web-app:v3.0                                    │
│  └── infra/            ← 인프라 팀 프로젝트 (Private)      │
│      ├── fluentbit:custom                                │
│      └── prometheus:custom                               │
└──────────────────────────────────────────────────────────┘
```

**프로젝트 생성 단계:**
1. 좌측 메뉴 → **Projects** → **+ New Project**
2. 프로젝트 이름 입력 (예: `backend`)
3. Access Level: **Public** 또는 **Private** 선택
4. Storage quota 설정 (선택)
5. **OK** 클릭

### 사용자 관리

| 역할 | 권한 |
|------|------|
| **Project Admin** | 프로젝트 설정 변경, 멤버 관리, 이미지 Push/Pull |
| **Maintainer** | 이미지 Push/Pull, 스캔 실행, 태그 삭제 |
| **Developer** | 이미지 Push/Pull |
| **Guest** | 이미지 Pull만 가능 |
| **Limited Guest** | 특정 이미지만 Pull 가능 |

### Robot Account (자동화용 계정)

CI/CD 파이프라인에서 사용할 서비스 계정입니다.

```
프로젝트 → Robot Accounts → + New Robot Account
  이름: cicd-bot
  만료: 30일 / 영구
  권한: Push + Pull
  → 생성 후 표시되는 Token을 안전하게 보관
```

---

## 6. Docker CLI로 Harbor 사용하기

### 6-1. 자체 서명 인증서 신뢰 설정

Harbor가 자체 서명 인증서(Self-signed Certificate)를 사용하는 경우:

```bash
# Harbor의 CA 인증서 가져오기
# 방법 1: Harbor에서 직접 다운로드
curl -k https://harbor.example.com/api/v2.0/systeminfo/getcert -o ca.crt

# 방법 2: openssl로 추출
openssl s_client -connect harbor.example.com:443 -showcerts </dev/null 2>/dev/null \
  | openssl x509 -outform PEM > ca.crt

# Docker에 인증서 등록
sudo mkdir -p /etc/docker/certs.d/harbor.example.com
sudo cp ca.crt /etc/docker/certs.d/harbor.example.com/ca.crt

# Docker 재시작
sudo systemctl restart docker
```

### 6-2. Docker Login

```bash
# Harbor에 로그인
docker login harbor.example.com
# Username: admin
# Password: Harbor12345

# 로그인 확인
cat ~/.docker/config.json | grep harbor
```

### 6-3. 이미지 Push

```bash
# 1. 퍼블릭 이미지 Pull
docker pull nginx:1.25

# 2. Harbor 주소로 태그 변경
#    형식: <harbor-주소>/<프로젝트>/<이미지>:<태그>
docker tag nginx:1.25 harbor.example.com/library/nginx:1.25

# 3. Harbor에 Push
docker push harbor.example.com/library/nginx:1.25
```

### 6-4. 이미지 Pull

```bash
# Harbor에서 이미지 Pull
docker pull harbor.example.com/backend/api-server:v2.1.0

# Kubernetes에서 사용할 경우 (imagePullSecrets 필요)
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.example.com \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n default
```

### Kubernetes Pod에서 프라이빗 이미지 사용

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: harbor.example.com/backend/api-server:v2.1.0
  imagePullSecrets:
  - name: harbor-secret
```

### 6-5. 자주 쓰는 Docker 명령어 정리

```bash
# 로그인 / 로그아웃
docker login harbor.example.com
docker logout harbor.example.com

# 이미지 태그 변경
docker tag <원본이미지> harbor.example.com/<프로젝트>/<이미지>:<태그>

# Push / Pull
docker push harbor.example.com/<프로젝트>/<이미지>:<태그>
docker pull harbor.example.com/<프로젝트>/<이미지>:<태그>

# 로컬 이미지 목록에서 Harbor 이미지 확인
docker images | grep harbor

# 이미지 검색 (Harbor API)
curl -s -u admin:Harbor12345 \
  https://harbor.example.com/api/v2.0/projects/library/repositories \
  | python3 -m json.tool
```

---

## 7. Helm 차트 저장소로 Harbor 사용하기

Harbor 2.x부터 **OCI 기반 Helm 차트 저장소**를 지원합니다.
Helm 차트도 컨테이너 이미지처럼 Harbor에 저장할 수 있습니다.

### 7-1. OCI 방식 (Helm 3.8+ 권장)

```bash
# 1. Harbor에 OCI 로그인
helm registry login harbor.example.com
# Username: admin
# Password: Harbor12345

# 2. 샘플 차트 생성
helm create my-chart
cd my-chart

# 3. 차트 패키징
helm package .
# → my-chart-0.1.0.tgz 생성

# 4. Harbor에 Push (OCI)
helm push my-chart-0.1.0.tgz oci://harbor.example.com/library

# 5. Harbor에서 Pull
helm pull oci://harbor.example.com/library/my-chart --version 0.1.0

# 6. Harbor에서 직접 설치
helm install my-release oci://harbor.example.com/library/my-chart --version 0.1.0
```

### 7-2. ChartMuseum 방식 (레거시)

Harbor 설정에서 ChartMuseum이 활성화된 경우:

```bash
# Helm 저장소 추가
helm repo add my-harbor https://harbor.example.com/chartrepo/library \
  --username admin \
  --password Harbor12345

# 저장소 업데이트
helm repo update

# 차트 검색
helm search repo my-harbor/

# 차트 설치
helm install my-release my-harbor/my-chart
```

### OCI vs ChartMuseum 비교

| 항목 | OCI (권장) | ChartMuseum |
|------|-----------|-------------|
| Helm 버전 | 3.8 이상 | 3.x |
| Harbor 버전 | 2.0 이상 | 1.x / 2.x |
| 프로토콜 | OCI Distribution | Chart Repository API |
| 명령어 | `helm push/pull oci://` | `helm repo add` + `helm push` |
| 추세 | 표준화 진행 중 | 점차 deprecated |

---

## 8. Trivy를 활용한 이미지 취약점 스캔

### Trivy란?

> **Trivy**는 Aqua Security가 개발한 오픈소스 취약점 스캐너입니다.
> 컨테이너 이미지, 파일시스템, Git 저장소, Kubernetes 클러스터의
> 보안 취약점을 빠르고 정확하게 검출합니다.

### 스캔 동작 원리

```
┌─────────────────────── Trivy 스캔 과정 ───────────────────────┐
│                                                               │
│  ┌──────────┐    ┌──────────────┐    ┌────────────────┐       │
│  │ 컨테이너  │───→│  이미지 분석   │───→│  CVE DB 조회   │       │
│  │  이미지   │    │              │    │                │       │
│  └──────────┘    │  • OS 패키지  │    │  • NVD         │       │
│                  │  • 언어 라이브 │    │  • Red Hat     │       │
│                  │  • 설정 파일  │    │  • Ubuntu      │       │
│                  └──────────────┘    │  • Alpine      │       │
│                                     │  • etc.        │       │
│                                     └───────┬────────┘       │
│                                             │                │
│                                     ┌───────▼────────┐       │
│                                     │   결과 리포트    │       │
│                                     │                │       │
│                                     │  CRITICAL: 2   │       │
│                                     │  HIGH: 5       │       │
│                                     │  MEDIUM: 12    │       │
│                                     │  LOW: 8        │       │
│                                     └────────────────┘       │
└───────────────────────────────────────────────────────────────┘
```

### 취약점 심각도 등급

| 등급 | 설명 | CVSS 점수 | 조치 |
|------|------|-----------|------|
| **CRITICAL** | 원격 코드 실행 등 치명적 취약점 | 9.0 ~ 10.0 | 즉시 패치 필수 |
| **HIGH** | 권한 상승, 정보 유출 가능 | 7.0 ~ 8.9 | 빠른 패치 권장 |
| **MEDIUM** | 제한된 조건에서 악용 가능 | 4.0 ~ 6.9 | 계획 패치 |
| **LOW** | 낮은 위험도 | 0.1 ~ 3.9 | 모니터링 |
| **UNKNOWN** | 아직 CVSS 점수 미할당 | - | 추적 관찰 |

### 8-1. Trivy CLI 독립 사용

```bash
# Trivy 설치
# macOS
brew install trivy

# Ubuntu/Debian
sudo apt-get install -y trivy

# CentOS/RHEL
sudo yum install -y trivy

# 또는 스크립트로 설치
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
```

#### 이미지 스캔

```bash
# 기본 스캔
trivy image nginx:1.25

# 심각도 필터링 (CRITICAL, HIGH만)
trivy image --severity CRITICAL,HIGH nginx:1.25

# JSON 출력 (CI/CD 연동용)
trivy image --format json --output result.json nginx:1.25

# 테이블 출력 (사람이 읽기 좋은 형식)
trivy image --format table nginx:1.25

# 특정 CVE 무시
trivy image --ignore-unfixed nginx:1.25

# 프라이빗 레지스트리 이미지 스캔
trivy image harbor.example.com/backend/api-server:v2.1.0
```

#### 스캔 결과 예시

```
harbor.example.com/backend/api-server:v2.1.0 (ubuntu 22.04)

Total: 27 (CRITICAL: 2, HIGH: 5, MEDIUM: 12, LOW: 8)

┌──────────────┬──────────────────┬──────────┬────────┬─────────────────────┐
│   Library    │  Vulnerability   │ Severity │ Version│   Fixed Version     │
├──────────────┼──────────────────┼──────────┼────────┼─────────────────────┤
│ libssl3      │ CVE-2024-0727   │ CRITICAL │ 3.0.2  │ 3.0.13             │
│ libcurl4     │ CVE-2023-46218  │ HIGH     │ 7.81.0 │ 7.81.0-1ubuntu1.15 │
│ zlib1g       │ CVE-2023-45853  │ MEDIUM   │ 1.2.11 │ 1.2.11.dfsg-2+deb  │
└──────────────┴──────────────────┴──────────┴────────┴─────────────────────┘
```

#### 기타 스캔 대상

```bash
# 파일시스템 스캔 (프로젝트 디렉터리)
trivy fs ./my-project

# Dockerfile 스캔 (설정 오류 검출)
trivy config ./Dockerfile

# Kubernetes 클러스터 스캔
trivy k8s --report summary

# SBOM(Software Bill of Materials) 생성
trivy image --format spdx-json --output sbom.json nginx:1.25
```

### 8-2. Harbor 통합 스캔

Harbor에 Trivy가 내장되어 있어 웹 UI 또는 API로 스캔할 수 있습니다.

#### 웹 UI에서 스캔

```
1. Projects → 프로젝트 선택 → Repositories → 이미지 선택
2. 이미지 태그 옆의 "SCAN" 버튼 클릭
3. 스캔 완료 후 취약점 목록 확인
```

#### API로 스캔 트리거

```bash
# 특정 이미지 스캔 실행
curl -s -X POST \
  -u admin:Harbor12345 \
  "https://harbor.example.com/api/v2.0/projects/library/repositories/nginx/artifacts/1.25/scan"

# 스캔 결과 조회
curl -s -u admin:Harbor12345 \
  "https://harbor.example.com/api/v2.0/projects/library/repositories/nginx/artifacts/1.25?with_scan_overview=true" \
  | python3 -m json.tool
```

#### Push 시 자동 스캔 설정

```
Harbor 웹 UI → Projects → 프로젝트 선택 → Configuration
  ☑ Automatically scan images on push
```

또는 API로:

```bash
curl -s -X PUT \
  -u admin:Harbor12345 \
  -H "Content-Type: application/json" \
  -d '{"metadata":{"auto_scan":"true"}}' \
  "https://harbor.example.com/api/v2.0/projects/1"
```

#### 취약점 기반 배포 차단

CRITICAL 취약점이 있는 이미지의 Pull을 차단할 수 있습니다:

```
Harbor 웹 UI → Projects → Configuration
  ☑ Prevent vulnerable images from running
  Severity: Critical / High / Medium / Low
```

---

## 9. 이미지 관리 전략

### 태그 전략

```
권장하는 태그 규칙:

harbor.example.com/backend/api-server:v2.1.0        ← 시맨틱 버전 (운영용)
harbor.example.com/backend/api-server:v2.1.0-rc1    ← 릴리스 후보
harbor.example.com/backend/api-server:main-abc1234  ← 브랜치-커밋해시 (개발용)
harbor.example.com/backend/api-server:pr-42         ← PR 번호 (리뷰용)

⚠️  피해야 할 태그:
harbor.example.com/backend/api-server:latest        ← 어떤 버전인지 알 수 없음
```

| 환경 | 태그 규칙 | 예시 |
|------|-----------|------|
| 개발 | `<branch>-<commit>` | `main-a1b2c3d` |
| 스테이징 | `<version>-rc<N>` | `v2.1.0-rc1` |
| 운영 | `<semver>` | `v2.1.0` |

### Retention Policy (보관 정책)

오래된 이미지를 자동 삭제하여 스토리지를 절약합니다.

```
Harbor 웹 UI → Projects → 프로젝트 → Policy → Tag Retention

  규칙 예시:
  ├── 최근 10개 태그 유지, 나머지 삭제
  ├── 30일 이내 Push된 이미지만 유지
  ├── "v*" 패턴 태그는 항상 유지 (운영 버전 보호)
  └── "latest" 태그는 항상 유지
```

### Garbage Collection

삭제된 이미지의 실제 스토리지 레이어를 정리합니다.

```
Harbor 웹 UI → Administration → Garbage Collection
  → GC Now (즉시 실행)
  → Schedule (주기적 실행 — 예: 매주 일요일 새벽 2시)
```

> **주의:** GC 실행 중에는 Push가 잠시 중단될 수 있습니다.
> 사용량이 적은 시간대에 실행하세요.

### 레지스트리 간 복제

```
┌─────────────────┐   복제(Replication)   ┌─────────────────┐
│  Harbor (본사)   │ ─────────────────→   │  Harbor (지사)   │
│                 │   Push 모드           │                 │
│  api-server:v2  │                      │  api-server:v2  │
└─────────────────┘                      └─────────────────┘

또는

┌─────────────────┐   복제(Replication)   ┌─────────────────┐
│  Docker Hub     │ ←─────────────────   │  Harbor (캐시)   │
│                 │   Pull 모드           │                 │
│  nginx:1.25     │                      │  nginx:1.25     │
└─────────────────┘                      └─────────────────┘
```

설정 방법:
```
Harbor 웹 UI → Administration → Registries → + New Endpoint
  → 대상 레지스트리 정보 입력

Harbor 웹 UI → Administration → Replications → + New Rule
  → 복제 방향, 필터, 스케줄 설정
```

---

## 10. 보안 모범 사례

### 10-1. 이미지 서명 (Content Trust)

```bash
# Cosign 설치
brew install cosign   # macOS
# 또는
go install github.com/sigstore/cosign/v2/cmd/cosign@latest

# 키 쌍 생성
cosign generate-key-pair

# 이미지 서명
cosign sign --key cosign.key harbor.example.com/backend/api-server:v2.1.0

# 서명 검증
cosign verify --key cosign.pub harbor.example.com/backend/api-server:v2.1.0
```

### 10-2. RBAC 설계 원칙

```
최소 권한 원칙 적용:

┌─────────────────────────────────────────┐
│            Harbor RBAC 예시              │
│                                         │
│  [운영팀]                                │
│    backend-prod → Project Admin          │
│    frontend-prod → Project Admin         │
│                                         │
│  [개발팀]                                │
│    backend-dev → Developer (Push+Pull)   │
│    frontend-dev → Developer (Push+Pull)  │
│                                         │
│  [QA팀]                                  │
│    backend-prod → Guest (Pull only)      │
│    backend-dev → Guest (Pull only)       │
│                                         │
│  [CI/CD]                                 │
│    모든 프로젝트 → Robot Account           │
│    (Push+Pull, 토큰 자동 만료)             │
└─────────────────────────────────────────┘
```

### 10-3. 네트워크 보안

```yaml
# Kubernetes NetworkPolicy — Harbor 접근 제한 예시
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-harbor-access
  namespace: harbor
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          harbor-access: "true"
    - ipBlock:
        cidr: 10.0.0.0/8      # 사내 네트워크만 허용
```

### 10-4. TLS 설정

운영 환경에서는 반드시 신뢰할 수 있는 인증서를 사용하세요:

```bash
# Let's Encrypt 인증서 사용 (cert-manager 활용)
# cert-manager가 설치된 Kubernetes 환경에서:

helm install harbor harbor/harbor \
  --namespace harbor \
  --set expose.type=ingress \
  --set expose.ingress.hosts.core=harbor.example.com \
  --set expose.tls.certSource=secret \
  --set expose.tls.secret.secretName=harbor-tls \
  --set expose.ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt-prod
```

---

## 11. CI/CD 파이프라인 연동

### Jenkins Pipeline 예시

```groovy
pipeline {
    agent any

    environment {
        HARBOR_URL = 'harbor.example.com'
        HARBOR_PROJECT = 'backend'
        IMAGE_NAME = 'api-server'
        HARBOR_CRED = credentials('harbor-credentials')
    }

    stages {
        stage('Build') {
            steps {
                sh "docker build -t ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${BUILD_NUMBER} ."
            }
        }

        stage('Scan') {
            steps {
                sh "trivy image --exit-code 1 --severity CRITICAL ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${BUILD_NUMBER}"
            }
        }

        stage('Push') {
            steps {
                sh "echo ${HARBOR_CRED_PSW} | docker login ${HARBOR_URL} -u ${HARBOR_CRED_USR} --password-stdin"
                sh "docker push ${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${BUILD_NUMBER}"
            }
        }

        stage('Deploy') {
            steps {
                sh "kubectl set image deployment/api-server api-server=${HARBOR_URL}/${HARBOR_PROJECT}/${IMAGE_NAME}:${BUILD_NUMBER}"
            }
        }
    }
}
```

### GitLab CI 예시

```yaml
# .gitlab-ci.yml
variables:
  HARBOR_URL: harbor.example.com
  HARBOR_PROJECT: backend
  IMAGE_NAME: api-server

stages:
  - build
  - scan
  - push
  - deploy

build:
  stage: build
  script:
    - docker build -t $HARBOR_URL/$HARBOR_PROJECT/$IMAGE_NAME:$CI_COMMIT_SHORT_SHA .

scan:
  stage: scan
  script:
    - trivy image --exit-code 1 --severity CRITICAL,HIGH $HARBOR_URL/$HARBOR_PROJECT/$IMAGE_NAME:$CI_COMMIT_SHORT_SHA
  allow_failure: false

push:
  stage: push
  script:
    - echo "$HARBOR_PASSWORD" | docker login $HARBOR_URL -u $HARBOR_USERNAME --password-stdin
    - docker push $HARBOR_URL/$HARBOR_PROJECT/$IMAGE_NAME:$CI_COMMIT_SHORT_SHA
    - docker tag $HARBOR_URL/$HARBOR_PROJECT/$IMAGE_NAME:$CI_COMMIT_SHORT_SHA $HARBOR_URL/$HARBOR_PROJECT/$IMAGE_NAME:latest
    - docker push $HARBOR_URL/$HARBOR_PROJECT/$IMAGE_NAME:latest

deploy:
  stage: deploy
  script:
    - kubectl set image deployment/api-server api-server=$HARBOR_URL/$HARBOR_PROJECT/$IMAGE_NAME:$CI_COMMIT_SHORT_SHA
  only:
    - main
```

### CI/CD 워크플로우

```
┌──────┐    ┌──────┐    ┌───────┐    ┌──────┐    ┌────────┐
│ Code │───→│Build │───→│ Trivy │───→│ Push │───→│ Deploy │
│ Push │    │Image │    │ Scan  │    │Harbor│    │  K8s   │
└──────┘    └──────┘    └───┬───┘    └──────┘    └────────┘
                            │
                      CRITICAL 발견?
                       ├── Yes → ❌ 파이프라인 중단
                       └── No  → ✅ 다음 단계 진행
```

---

## 12. 문제 해결 가이드

### 인증서 오류

```
Error: x509: certificate signed by unknown authority
```

**해결:**
```bash
# Docker에 Harbor CA 인증서 등록
sudo mkdir -p /etc/docker/certs.d/<harbor-domain>
sudo cp ca.crt /etc/docker/certs.d/<harbor-domain>/ca.crt
sudo systemctl restart docker

# 또는 insecure registry 설정 (테스트 환경만!)
# /etc/docker/daemon.json
{
  "insecure-registries": ["harbor.example.com"]
}
```

### Docker Login 실패

```
Error: unauthorized: authentication required
```

**해결:**
```bash
# 1. 비밀번호 확인
# 2. Robot Account인 경우 이름 형식 확인 (robot$프로젝트+이름)
docker login harbor.example.com -u 'robot$backend+cicd-bot'

# 3. 기존 인증 정보 삭제 후 재로그인
docker logout harbor.example.com
docker login harbor.example.com
```

### Push 실패

```
Error: denied: requested access to the resource is denied
```

**해결:**
```bash
# 1. 프로젝트 존재 여부 확인
# 2. 이미지 태그에 프로젝트명 포함 확인
docker tag myapp:v1 harbor.example.com/backend/myapp:v1  # ✅ 프로젝트명 포함
docker tag myapp:v1 harbor.example.com/myapp:v1          # ❌ 프로젝트명 누락

# 3. 사용자 권한 확인 (Developer 이상 필요)
```

### Trivy 스캔 실패

```
Error: failed to scan image: DB not found
```

**해결:**
```bash
# Trivy DB 수동 업데이트
trivy image --download-db-only

# Harbor 내장 Trivy의 경우 — Pod 재시작
kubectl rollout restart deployment harbor-trivy -n harbor
```

### Harbor Pod 상태 이상

```bash
# Pod 상태 확인
kubectl get pods -n harbor

# 비정상 Pod 로그 확인
kubectl logs <pod-name> -n harbor

# PVC 상태 확인 (Pending이면 StorageClass 문제)
kubectl get pvc -n harbor

# Harbor 전체 재시작
kubectl rollout restart deployment -n harbor
```

### 스토리지 부족

```bash
# PVC 사용량 확인
kubectl exec -n harbor <registry-pod> -- df -h /storage

# Garbage Collection 실행 (Harbor 웹 UI)
# Administration → Garbage Collection → GC Now

# Retention Policy 설정으로 오래된 이미지 자동 삭제
```

---

## 부록: 주요 Harbor API 정리

| 용도 | 메서드 | 엔드포인트 |
|------|--------|-----------|
| 프로젝트 목록 | GET | `/api/v2.0/projects` |
| 프로젝트 생성 | POST | `/api/v2.0/projects` |
| 이미지 목록 | GET | `/api/v2.0/projects/{name}/repositories` |
| 태그 목록 | GET | `/api/v2.0/projects/{name}/repositories/{repo}/artifacts` |
| 스캔 실행 | POST | `/api/v2.0/projects/{name}/repositories/{repo}/artifacts/{tag}/scan` |
| 스캔 결과 | GET | `/api/v2.0/projects/{name}/repositories/{repo}/artifacts/{tag}?with_scan_overview=true` |
| 시스템 정보 | GET | `/api/v2.0/systeminfo` |
| 사용자 목록 | GET | `/api/v2.0/users` |
| GC 실행 | POST | `/api/v2.0/system/gc/schedule` |

```bash
# API 사용 예시 — 기본 인증
curl -s -u admin:Harbor12345 \
  "https://harbor.example.com/api/v2.0/projects" \
  | python3 -m json.tool
```

---

> **다음 단계:** `harbor-registry.sh` 스크립트를 실행하여 실제 Harbor 설치와
> Docker/Helm/Trivy 실습을 인터랙티브하게 진행해 보세요.
