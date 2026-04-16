# Kubernetes CRD와 Cluster API 교육

> Kubernetes를 **확장하는 핵심 메커니즘인 CRD(Custom Resource Definition)**와, CRD를 활용하여 **Kubernetes 클러스터 자체를 Kubernetes 리소스로 관리하는 Cluster API**를 다룹니다.
> 나아가 VMware vSphere 환경에서 **VKS(vSphere Kubernetes Service)**가 Cluster API를 활용하여 클러스터를 CRD로 생성·관리하는 실제 사례까지 이해하는 것을 목표로 합니다.

---

## 목차

1. [CRD 개요](#1-crd-개요)
2. [CRD 동작 원리](#2-crd-동작-원리)
3. [Custom Controller와 Operator 패턴](#3-custom-controller와-operator-패턴)
4. [CRD 실전 예시](#4-crd-실전-예시)
5. [Cluster API 개요](#5-cluster-api-개요)
6. [Cluster API 아키텍처](#6-cluster-api-아키텍처)
7. [Cluster API 핵심 리소스](#7-cluster-api-핵심-리소스)
8. [CAPV — Cluster API Provider vSphere](#8-capv--cluster-api-provider-vsphere)
9. [VKS (vSphere Kubernetes Service)](#9-vks-vsphere-kubernetes-service)
10. [VKS에서 클러스터를 CRD로 관리하기](#10-vks에서-클러스터를-crd로-관리하기)
11. [실습: CRD 생성과 활용](#11-실습-crd-생성과-활용)
12. [정리 및 핵심 요약](#12-정리-및-핵심-요약)

---

## 1. CRD 개요

### 한 문장 정의

> **CRD(Custom Resource Definition)**는 Kubernetes API를 확장하여 **사용자가 직접 정의한 새로운 리소스 유형**을 추가할 수 있게 해주는 메커니즘입니다. Pod, Service처럼 `kubectl`로 관리할 수 있는 나만의 리소스를 만들 수 있습니다.

### 비유로 이해하기

```
┌─────────────────────────────────────────────────────────────┐
│                  레고 블록 비유                                 │
│                                                             │
│   Kubernetes 기본 리소스 = 레고 기본 블록                       │
│   ┌─────┐ ┌─────────┐ ┌────────┐ ┌────────────┐            │
│   │ Pod │ │Deployment│ │Service │ │ ConfigMap  │            │
│   └─────┘ └─────────┘ └────────┘ └────────────┘            │
│   → 기본 블록만으로도 많은 것을 만들 수 있지만...               │
│                                                             │
│   CRD = 나만의 특수 블록을 직접 설계                           │
│   ┌──────────┐ ┌─────────────┐ ┌──────────────┐            │
│   │ Database │ │ Certificate │ │   Cluster    │            │
│   │  (CRD)   │ │   (CRD)     │ │    (CRD)     │            │
│   └──────────┘ └─────────────┘ └──────────────┘            │
│   → 복잡한 운영 작업을 하나의 리소스로 추상화!                  │
│                                                             │
│   kubectl get databases                                    │
│   kubectl get certificates                                 │
│   kubectl get clusters        ← 마치 기본 리소스처럼 사용!    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 왜 CRD가 필요한가?

```
┌─────────────────────────────────────────────────────────────┐
│              CRD 없이 MySQL 클러스터를 운영한다면?               │
│                                                             │
│  수동으로 해야 할 일:                                          │
│                                                             │
│  1. StatefulSet YAML 작성 (Primary + Replica)                │
│  2. Service 생성 (Primary용, Replica 읽기용)                  │
│  3. ConfigMap 작성 (my.cnf 설정)                             │
│  4. Secret 생성 (Root 비밀번호, Replication 계정)              │
│  5. PVC 생성 (각 Pod마다)                                     │
│  6. 초기화 스크립트 작성                                       │
│  7. Replication 설정 수동 실행                                │
│  8. 백업 CronJob 설정                                        │
│  9. 모니터링 설정                                             │
│  10. 장애 시 수동 Failover                                    │
│                                                             │
│  → YAML 10개 이상, 수동 작업 다수, 운영 부담 막대!              │
│                                                             │
│  ─────────────────────────────────────────────               │
│                                                             │
│  CRD + Operator 사용 시:                                      │
│                                                             │
│  apiVersion: mysql.example.com/v1                            │
│  kind: MySQLCluster          ← CRD로 정의한 리소스            │
│  metadata:                                                   │
│    name: production-db                                       │
│  spec:                                                       │
│    replicas: 3                                               │
│    version: "8.0"                                            │
│    backup:                                                   │
│      schedule: "0 2 * * *"                                   │
│      storage: s3://my-backup                                 │
│                                                             │
│  → YAML 1개로 끝! Operator가 나머지를 모두 자동 처리!           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### CRD를 사용하는 대표 프로젝트

| 프로젝트 | CRD 예시 | 용도 |
|---------|---------|------|
| **cert-manager** | Certificate, Issuer | TLS 인증서 자동 발급/갱신 |
| **Prometheus Operator** | Prometheus, ServiceMonitor | 모니터링 스택 관리 |
| **Istio** | VirtualService, Gateway | 서비스 메시 트래픽 관리 |
| **ArgoCD** | Application, AppProject | GitOps 배포 관리 |
| **Crossplane** | CompositeResource | 클라우드 인프라를 K8s로 관리 |
| **Cluster API** | Cluster, Machine | K8s 클러스터 생명주기 관리 |
| **Kyverno** | ClusterPolicy, Policy | K8s 정책 관리 |
| **Velero** | Backup, Restore | 백업/복구 관리 |
| **VKS (vSphere)** | TanzuKubernetesCluster | vSphere 위 K8s 클러스터 관리 |

---

## 2. CRD 동작 원리

### CRD가 Kubernetes API를 확장하는 방식

```
┌─────────────────────────────────────────────────────────────┐
│            CRD 등록 전 vs 등록 후                              │
│                                                             │
│  등록 전:                                                     │
│  $ kubectl get databases                                    │
│  error: the server doesn't have a resource type "databases" │
│  → API Server가 "databases"라는 리소스를 모름!                 │
│                                                             │
│  CRD 등록:                                                    │
│  $ kubectl apply -f database-crd.yaml                       │
│  customresourcedefinition.apiextensions.k8s.io/              │
│    databases.example.com created                            │
│                                                             │
│  등록 후:                                                     │
│  $ kubectl get databases                                    │
│  No resources found in default namespace.                   │
│  → API Server가 "databases"를 인식! kubectl로 관리 가능!      │
│                                                             │
│  $ kubectl create -f my-database.yaml                       │
│  database.example.com/production-db created                 │
│  → 실제 리소스 생성 완료!                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### CRD 등록 흐름

```
┌─────────────────────────────────────────────────────────────┐
│                CRD 등록 → CR 생성 → 처리 흐름                  │
│                                                             │
│  ① CRD 등록 (관리자)                                          │
│     kubectl apply -f database-crd.yaml                      │
│         │                                                   │
│         ▼                                                   │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  API Server                                          │    │
│  │                                                      │    │
│  │  기존 API 엔드포인트:                                  │    │
│  │  /api/v1/pods                                        │    │
│  │  /api/v1/services                                    │    │
│  │  /apis/apps/v1/deployments                           │    │
│  │                                                      │    │
│  │  + 새로 추가됨:                                       │    │
│  │  /apis/example.com/v1/databases  ← CRD로 자동 생성!  │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
│         │                                                   │
│         ▼                                                   │
│  ② CR(Custom Resource) 생성 (개발자)                         │
│     kubectl apply -f my-database.yaml                       │
│         │                                                   │
│         ▼                                                   │
│  ③ API Server: 검증 → etcd 저장                              │
│     (CRD의 스키마에 따라 YAML 검증)                            │
│         │                                                   │
│         ▼                                                   │
│  ④ Controller(Operator)가 Watch로 감지                       │
│     "새 Database CR이 생성됐다! 처리하자"                       │
│         │                                                   │
│         ▼                                                   │
│  ⑤ Controller가 실제 리소스 생성                              │
│     StatefulSet, Service, ConfigMap, Secret 등               │
│     → MySQL 클러스터 자동 구축!                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### CRD YAML 구조

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databases.example.com          # 반드시 <plural>.<group> 형식
spec:
  group: example.com                    # API 그룹
  names:
    plural: databases                   # 복수형 (kubectl get databases)
    singular: database                  # 단수형
    kind: Database                      # 리소스 종류 (YAML의 kind)
    shortNames:                         # 축약 이름
    - db                                # kubectl get db 로 사용 가능
  scope: Namespaced                     # Namespaced 또는 Cluster
  versions:
  - name: v1                            # API 버전
    served: true                        # 이 버전을 제공할지
    storage: true                       # etcd에 이 버전으로 저장할지
    schema:
      openAPIV3Schema:                  # 스키마 검증 (필수)
        type: object
        properties:
          spec:
            type: object
            required: ["engine", "version", "replicas"]
            properties:
              engine:
                type: string
                enum: ["mysql", "postgresql", "mariadb"]
                description: "데이터베이스 엔진 종류"
              version:
                type: string
                description: "데이터베이스 버전"
              replicas:
                type: integer
                minimum: 1
                maximum: 7
                description: "레플리카 수"
              storage:
                type: object
                properties:
                  size:
                    type: string
                    description: "스토리지 크기 (예: 10Gi)"
                  storageClassName:
                    type: string
                    description: "StorageClass 이름"
          status:
            type: object
            properties:
              phase:
                type: string
              readyReplicas:
                type: integer
    additionalPrinterColumns:           # kubectl get 출력 커스터마이징
    - name: Engine
      type: string
      jsonPath: .spec.engine
    - name: Version
      type: string
      jsonPath: .spec.version
    - name: Replicas
      type: integer
      jsonPath: .spec.replicas
    - name: Status
      type: string
      jsonPath: .status.phase
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
    subresources:
      status: {}                        # /status 서브리소스 활성화
```

### CR(Custom Resource) 예시

```yaml
# 위 CRD를 기반으로 생성하는 실제 리소스
apiVersion: example.com/v1
kind: Database
metadata:
  name: production-db
  namespace: default
spec:
  engine: mysql
  version: "8.0"
  replicas: 3
  storage:
    size: 50Gi
    storageClassName: fast-ssd
```

```bash
# CRD 등록 후 사용 예시
$ kubectl get databases
NAME            ENGINE   VERSION   REPLICAS   STATUS   AGE
production-db   mysql    8.0       3          Ready    5m

$ kubectl get db          # shortName 사용
$ kubectl describe db production-db
$ kubectl delete db production-db
```

---

## 3. Custom Controller와 Operator 패턴

### CRD만으로는 부족한 이유

```
┌─────────────────────────────────────────────────────────────┐
│              CRD만 있으면 어떻게 되나?                          │
│                                                             │
│  CRD = "새 리소스 유형을 API에 등록"                           │
│  → etcd에 데이터를 저장/조회할 수 있음                          │
│  → 하지만 아무 일도 일어나지 않음!                               │
│                                                             │
│  kubectl apply -f my-database.yaml                          │
│  → etcd에 Database CR이 저장됨                               │
│  → ... 그리고 끝. MySQL이 설치되지 않음!                       │
│                                                             │
│  CRD + Controller(Operator) = "새 리소스를 감시하고 처리"       │
│  → CR 생성을 감지                                             │
│  → 실제 MySQL StatefulSet, Service 등을 자동 생성              │
│  → 지속적으로 상태 관리 (Reconciliation Loop)                  │
│                                                             │
│  ┌──────────┐     ┌──────────────┐                          │
│  │   CRD    │  +  │  Controller  │  =  Operator             │
│  │ (구조정의)│     │ (자동화 로직) │                           │
│  └──────────┘     └──────────────┘                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Operator 패턴

```
┌─────────────────────────────────────────────────────────────┐
│                Operator = CRD + Controller                   │
│                                                             │
│  "운영자(Operator)의 지식을 코드로 자동화한 것"                 │
│                                                             │
│  사람 운영자가 하던 일:                  Operator가 하는 일:    │
│  ├── MySQL 설치                       ├── CR 감지 → 자동 설치│
│  ├── Replication 설정                 ├── 자동 설정          │
│  ├── 백업 스케줄 관리                  ├── CronJob 자동 생성  │
│  ├── 장애 시 Failover                 ├── 자동 Failover     │
│  ├── 버전 업그레이드                   ├── 롤링 업그레이드    │
│  └── 스케일 아웃/인                    └── replicas 변경 감지│
│                                                             │
│  ┌──────────────────────────────────────────────────────┐    │
│  │              Operator 동작 루프                        │    │
│  │                                                      │    │
│  │   ┌─── Watch ───┐                                    │    │
│  │   │ CR 변경 감지 │                                    │    │
│  │   └──────┬──────┘                                    │    │
│  │          │                                           │    │
│  │          ▼                                           │    │
│  │   ┌─── Reconcile ───────────────────────────┐        │    │
│  │   │                                          │        │    │
│  │   │  원하는 상태(CR spec) vs 현재 상태 비교     │        │    │
│  │   │                                          │        │    │
│  │   │  차이가 있으면:                             │        │    │
│  │   │  ├── 리소스 생성/수정/삭제                   │        │    │
│  │   │  ├── 외부 시스템 호출                       │        │    │
│  │   │  └── CR status 업데이트                    │        │    │
│  │   │                                          │        │    │
│  │   └──────────────────────────────────────────┘        │    │
│  │          │                                           │    │
│  │          └──── 다시 Watch로 돌아감 (무한 루프)         │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Operator 개발 프레임워크

| 프레임워크 | 언어 | 특징 |
|-----------|------|------|
| **Kubebuilder** | Go | K8s 공식 SIG 관리, 가장 표준적 |
| **Operator SDK** | Go, Ansible, Helm | Red Hat 주도, 다양한 방식 지원 |
| **Metacontroller** | 모든 언어 | Webhook 기반, 진입장벽 낮음 |
| **KUDO** | YAML | 코드 없이 YAML만으로 Operator 생성 |
| **kopf** | Python | Python 기반 Operator 개발 |

### Operator Maturity Model

```
┌─────────────────────────────────────────────────────────────┐
│           Operator 성숙도 레벨 (Capability Level)              │
│                                                             │
│  Level 5: Auto Pilot                                        │
│  ├── 이상 탐지, 자동 튜닝, 자동 스케일링                       │
│  │                                                          │
│  Level 4: Deep Insights                                     │
│  ├── 메트릭, 알림, 로그 분석, 대시보드                         │
│  │                                                          │
│  Level 3: Full Lifecycle                                    │
│  ├── 백업/복구, 업그레이드, 장애 복구                          │
│  │                                                          │
│  Level 2: Seamless Upgrades                                 │
│  ├── 패치 적용, 마이너 버전 업그레이드                         │
│  │                                                          │
│  Level 1: Basic Install        ← 대부분의 Operator 시작점     │
│  ├── 자동 설치, 설정 관리                                     │
│  │                                                          │
│  Level 0: Planning                                          │
│  └── CRD 정의, 기본 구조 설계                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. CRD 실전 예시

### 예시 1: cert-manager의 Certificate CRD

```yaml
# cert-manager가 정의한 CRD를 사용하여 TLS 인증서 자동 발급
apiVersion: cert-manager.io/v1
kind: Certificate                     # cert-manager의 CRD
metadata:
  name: my-app-tls
  namespace: default
spec:
  secretName: my-app-tls-secret       # 인증서가 저장될 Secret
  issuerRef:
    name: letsencrypt-prod            # 인증서 발급자 (이것도 CRD!)
    kind: ClusterIssuer
  dnsNames:
  - myapp.example.com
  - www.myapp.example.com
```

```
사용자: Certificate CR 생성
    │
    ▼
cert-manager Controller (Watch):
    │
    ├── Let's Encrypt에 인증서 발급 요청
    ├── ACME 챌린지 처리 (DNS/HTTP)
    ├── 인증서 수신 → Secret 생성 (my-app-tls-secret)
    ├── 만료 30일 전 자동 갱신
    └── Certificate status 업데이트
```

### 예시 2: Prometheus Operator의 ServiceMonitor CRD

```yaml
# Prometheus가 어떤 서비스를 모니터링할지 CRD로 정의
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor                  # Prometheus Operator의 CRD
metadata:
  name: my-app-monitor
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### 예시 3: ArgoCD의 Application CRD

```yaml
# GitOps 배포를 CRD로 선언
apiVersion: argoproj.io/v1alpha1
kind: Application                     # ArgoCD의 CRD
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/my-app.git
    targetRevision: main
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## 5. Cluster API 개요

### 한 문장 정의

> **Cluster API(CAPI)**는 Kubernetes 클러스터의 **생성, 설정, 업그레이드, 삭제를 Kubernetes의 CRD로 관리**하는 프로젝트입니다. "Kubernetes로 Kubernetes를 관리"하는 것입니다.

### 비유로 이해하기

```
┌─────────────────────────────────────────────────────────────┐
│                  공장의 공장 비유                               │
│                                                             │
│   일반적인 Kubernetes:                                        │
│   "공장에서 제품(Pod)을 만든다"                                 │
│                                                             │
│   ┌─────────────────┐                                        │
│   │  K8s 클러스터    │  Pod, Deployment, Service 관리         │
│   │  (공장)          │  = 제품 생산                           │
│   └─────────────────┘                                        │
│                                                             │
│   Cluster API:                                               │
│   "공장(클러스터)을 만드는 공장(Management Cluster)"             │
│                                                             │
│   ┌─────────────────────────────────────────────┐            │
│   │  Management Cluster (공장의 공장)             │            │
│   │                                               │            │
│   │  kubectl apply -f cluster.yaml                │            │
│   │  → "새 공장을 만들어라!"                        │            │
│   │                                               │            │
│   │  ┌──────────┐ ┌──────────┐ ┌──────────┐       │            │
│   │  │ Cluster  │ │ Cluster  │ │ Cluster  │       │            │
│   │  │  dev     │ │ staging  │ │  prod    │       │            │
│   │  │  (CRD)   │ │  (CRD)   │ │  (CRD)   │       │            │
│   │  └──────────┘ └──────────┘ └──────────┘       │            │
│   └─────────────────────────────────────────────┘            │
│        │                │                │                   │
│        ▼                ▼                ▼                   │
│   ┌────────┐      ┌────────┐      ┌────────┐                │
│   │ Dev    │      │Staging │      │ Prod   │                │
│   │Cluster │      │Cluster │      │Cluster │                │
│   │(실제VM)│      │(실제VM)│      │(실제VM)│                │
│   └────────┘      └────────┘      └────────┘                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 왜 Cluster API가 필요한가?

```
┌─────────────────────────────────────────────────────────────┐
│        Cluster API 없이 클러스터 100개를 관리한다면?             │
│                                                             │
│  ❌ 수동 관리의 문제:                                          │
│  ├── 각 클러스터마다 kubeadm init/join 수동 실행               │
│  ├── 업그레이드 시 100개 클러스터를 하나씩 작업                  │
│  ├── 노드 추가/제거 시 VM 생성 → K8s 조인 수동                 │
│  ├── 장애 노드 교체 시 수동 개입                               │
│  ├── 클러스터마다 다른 설정, 일관성 유지 어려움                  │
│  └── 인프라(VM, 네트워크, LB)와 K8s 설정이 분리되어 관리 복잡   │
│                                                             │
│  ✅ Cluster API 사용 시:                                      │
│  ├── YAML 하나로 클러스터 생성 (kubectl apply)                 │
│  ├── K8s 버전 변경 → YAML 수정 → 자동 롤링 업그레이드          │
│  ├── replicas 변경 → 노드 자동 추가/제거                       │
│  ├── 장애 노드 → Machine Health Check로 자동 교체              │
│  ├── GitOps로 모든 클러스터를 선언적 관리                       │
│  └── 인프라 + K8s 설정을 하나의 리소스로 통합                   │
│                                                             │
│  핵심 가치: "클러스터도 Pod처럼 선언적으로 관리"                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Cluster API 아키텍처

### 전체 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cluster API 아키텍처                           │
│                                                                 │
│  ┌─── Management Cluster ─────────────────────────────────────┐ │
│  │                                                             │ │
│  │  ┌─── CAPI Core Controller ──────────────────────────┐      │ │
│  │  │                                                    │      │ │
│  │  │  Cluster Controller        : Cluster CR 관리       │      │ │
│  │  │  Machine Controller        : Machine CR 관리       │      │ │
│  │  │  MachineSet Controller     : 머신 수 유지          │      │ │
│  │  │  MachineDeployment Ctrl    : 롤링 업데이트 관리     │      │ │
│  │  │  MachineHealthCheck Ctrl   : 노드 건강 확인/교체    │      │ │
│  │  │                                                    │      │ │
│  │  └────────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  │  ┌─── Infrastructure Provider (예: CAPV) ───────────┐       │ │
│  │  │                                                    │      │ │
│  │  │  VSphereCluster Controller : vSphere 인프라 관리   │      │ │
│  │  │  VSphereMachine Controller : VM 생성/삭제 관리     │      │ │
│  │  │                                                    │      │ │
│  │  └────────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  │  ┌─── Bootstrap Provider (예: CABPK) ───────────────┐       │ │
│  │  │                                                    │      │ │
│  │  │  KubeadmConfig Controller  : kubeadm 설정 관리     │      │ │
│  │  │  → cloud-init 스크립트 생성                        │      │ │
│  │  │                                                    │      │ │
│  │  └────────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  │  ┌─── Control Plane Provider (예: KCP) ─────────────┐       │ │
│  │  │                                                    │      │ │
│  │  │  KubeadmControlPlane Ctrl  : Control Plane 관리    │      │ │
│  │  │  → etcd, API Server 등 관리                        │      │ │
│  │  │                                                    │      │ │
│  │  └────────────────────────────────────────────────────┘      │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│         │                    │                    │               │
│         ▼                    ▼                    ▼               │
│  ┌──────────┐         ┌──────────┐         ┌──────────┐         │
│  │ Workload │         │ Workload │         │ Workload │         │
│  │Cluster 1 │         │Cluster 2 │         │Cluster 3 │         │
│  │ (dev)    │         │(staging) │         │ (prod)   │         │
│  └──────────┘         └──────────┘         └──────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Provider 체계

```
┌─────────────────────────────────────────────────────────────┐
│              Cluster API의 Provider 분류                      │
│                                                             │
│  ┌─── Infrastructure Provider ────────────────────────┐     │
│  │  VM/베어메탈/클라우드 인프라 관리                      │     │
│  │                                                     │     │
│  │  CAPV  : vSphere     (VM 생성/삭제)                 │     │
│  │  CAPA  : AWS         (EC2 인스턴스 관리)             │     │
│  │  CAPZ  : Azure       (Azure VM 관리)                │     │
│  │  CAPG  : GCP         (GCE 인스턴스 관리)             │     │
│  │  CAPO  : OpenStack   (OpenStack 인스턴스)            │     │
│  │  CAPD  : Docker      (테스트용, Docker 컨테이너)      │     │
│  │  CAPBM : Metal3      (베어메탈 서버)                 │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  ┌─── Bootstrap Provider ─────────────────────────────┐     │
│  │  노드 초기화 방법 관리                                │     │
│  │                                                     │     │
│  │  CABPK : kubeadm     (가장 일반적)                   │     │
│  │  CABPT : Talos       (Talos Linux)                  │     │
│  │  CABPM : MicroK8s                                   │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  ┌─── Control Plane Provider ─────────────────────────┐     │
│  │  Control Plane 생명주기 관리                          │     │
│  │                                                     │     │
│  │  KCP   : KubeadmControlPlane (가장 일반적)           │     │
│  │  TKCP  : Talos Control Plane                        │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Cluster API 핵심 리소스

### 리소스 관계도

```
┌─────────────────────────────────────────────────────────────────┐
│              Cluster API 리소스 계층 구조                          │
│                                                                 │
│  ┌─── Cluster ──────────────────────────────────────────────┐   │
│  │  클러스터 전체를 대표하는 최상위 리소스                       │   │
│  │  + InfrastructureRef → VSphereCluster (인프라 설정)        │   │
│  │                                                           │   │
│  │  ┌─── KubeadmControlPlane ─────────────────────────┐      │   │
│  │  │  Control Plane 노드 관리 (Master 노드)             │      │   │
│  │  │  replicas: 3 → Master VM 3개 생성/관리             │      │   │
│  │  │  + InfrastructureTemplate → VSphereMachineTemplate │      │   │
│  │  │                                                   │      │   │
│  │  │  ┌── Machine ─┐ ┌── Machine ─┐ ┌── Machine ─┐    │      │   │
│  │  │  │  master-0   │ │  master-1   │ │  master-2   │    │      │   │
│  │  │  └─────────────┘ └─────────────┘ └─────────────┘    │      │   │
│  │  └─────────────────────────────────────────────────┘      │   │
│  │                                                           │   │
│  │  ┌─── MachineDeployment ───────────────────────────┐      │   │
│  │  │  Worker 노드 관리 (Deployment처럼 동작)            │      │   │
│  │  │  replicas: 5 → Worker VM 5개 생성/관리             │      │   │
│  │  │  + InfrastructureTemplate → VSphereMachineTemplate │      │   │
│  │  │                                                   │      │   │
│  │  │  ┌── MachineSet ──────────────────────────────┐   │      │   │
│  │  │  │                                             │   │      │   │
│  │  │  │  ┌── Machine ┐ ┌── Machine ┐ ... (5개)     │   │      │   │
│  │  │  │  │  worker-0  │ │  worker-1  │              │   │      │   │
│  │  │  │  └────────────┘ └────────────┘              │   │      │   │
│  │  │  └─────────────────────────────────────────────┘   │      │   │
│  │  └─────────────────────────────────────────────────┘      │   │
│  │                                                           │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Kubernetes 비유:                                                │
│  Cluster        ≈ 네임스페이스 (전체 범위)                        │
│  KubeadmCP      ≈ StatefulSet (Master 노드, 순서/고유성 보장)     │
│  MachineDeployment ≈ Deployment (Worker 노드, 롤링 업데이트)     │
│  MachineSet     ≈ ReplicaSet (머신 수 유지)                      │
│  Machine        ≈ Pod (개별 노드, 실제 VM과 1:1 매핑)            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 리소스 설명

| 리소스 | 역할 | K8s 비유 |
|--------|------|----------|
| **Cluster** | 클러스터 전체 정의 (네트워크, 인프라 참조) | Namespace |
| **Machine** | 개별 노드(VM/서버). 실제 인프라와 1:1 매핑 | Pod |
| **MachineSet** | Machine 수를 유지하는 컨트롤러 | ReplicaSet |
| **MachineDeployment** | Worker 노드의 롤링 업데이트 관리 | Deployment |
| **KubeadmControlPlane** | Control Plane 노드 관리 (etcd, API Server) | StatefulSet |
| **MachineHealthCheck** | 노드 건강 감시, 불량 노드 자동 교체 | - |

### 클러스터 생성 흐름

```
kubectl apply -f cluster.yaml (Management Cluster에서)
        │
        ▼
┌─── CAPI Core Controller ────────────────────────────────┐
│  Cluster CR 생성 감지                                     │
│  → Infrastructure Provider에 인프라 생성 요청              │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌─── Infrastructure Provider (예: CAPV) ───────────────────┐
│  VSphereCluster CR 처리:                                  │
│  ├── vCenter에 리소스 풀/폴더 확인                         │
│  ├── HAProxy LB VM 생성 (Control Plane 앞단)              │
│  └── 네트워크 설정                                        │
│                                                          │
│  VSphereMachine CR 처리 (Machine당):                      │
│  ├── vCenter API → VM 생성 (템플릿에서 클론)               │
│  ├── disk.EnableUUID = TRUE 설정                          │
│  ├── cloud-init 데이터 주입                                │
│  └── VM 파워 온                                           │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌─── Bootstrap Provider (CABPK) ───────────────────────────┐
│  KubeadmConfig CR 처리:                                   │
│  ├── cloud-init 스크립트 생성                              │
│  │   ├── containerd 설치                                  │
│  │   ├── kubeadm 설치                                     │
│  │   ├── kubeadm init (Master) 또는 join (Worker)         │
│  │   └── CNI 설치                                         │
│  └── 스크립트를 Secret으로 저장 → VM의 cloud-init에 전달    │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌─── Control Plane Provider (KCP) ─────────────────────────┐
│  KubeadmControlPlane CR 처리:                              │
│  ├── Master Machine 순차 생성 (master-0 → 1 → 2)          │
│  ├── etcd 클러스터 구성                                    │
│  ├── kubeconfig 생성 → Secret으로 저장                     │
│  └── Control Plane 정상 확인 후 Worker 생성 허용            │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
                    Workload Cluster 생성 완료!
                    kubeconfig를 가져와서 접속 가능
```

---

## 8. CAPV — Cluster API Provider vSphere

### CAPV란?

> **CAPV(Cluster API Provider vSphere)**는 Cluster API의 Infrastructure Provider로서, **vSphere 환경에서 VM을 생성/삭제하여 Kubernetes 노드를 관리**합니다.

```
┌─────────────────────────────────────────────────────────────┐
│                CAPV가 관리하는 vSphere 리소스                   │
│                                                             │
│  Cluster API CR                    vSphere 리소스            │
│                                                             │
│  VSphereCluster ─────────────────▶ 리소스 풀, 폴더, 네트워크  │
│  VSphereMachine ─────────────────▶ 개별 VM                   │
│  VSphereMachineTemplate ─────────▶ VM 템플릿 (OVA)           │
│  VSphereDeploymentZone ──────────▶ vSphere 클러스터/호스트    │
│                                                             │
│  CAPV Controller의 동작:                                      │
│  ├── Machine CR 생성 감지                                    │
│  ├── vCenter API 호출 → VM 템플릿에서 클론                    │
│  ├── VM 설정 (CPU, 메모리, 디스크, 네트워크)                   │
│  ├── cloud-init 데이터 주입 (Guestinfo)                      │
│  ├── VM 파워 온                                              │
│  ├── VM IP 주소 확인 → Machine status 업데이트                │
│  └── Machine 삭제 시 → VM 삭제                               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### CAPV 클러스터 YAML 예시

```yaml
# 1. Cluster 정의
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-vsphere-cluster
  namespace: default
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: my-vsphere-cluster-cp
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: VSphereCluster
    name: my-vsphere-cluster
---
# 2. vSphere 인프라 설정
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: VSphereCluster
metadata:
  name: my-vsphere-cluster
spec:
  controlPlaneEndpoint:
    host: 192.168.1.100                # Control Plane VIP
    port: 6443
  identityRef:
    kind: Secret
    name: vsphere-credentials
  server: vcenter.example.com          # vCenter 주소
  thumbprint: "AA:BB:CC:..."           # vCenter TLS 인증서 thumbprint
---
# 3. Control Plane 정의
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: my-vsphere-cluster-cp
spec:
  replicas: 3                          # Master 노드 3개
  version: v1.31.0                     # K8s 버전
  machineTemplate:
    infrastructureRef:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: VSphereMachineTemplate
      name: my-vsphere-cluster-cp
  kubeadmConfigSpec:
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: external
    joinConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: external
---
# 4. VM 템플릿 (Control Plane용)
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: VSphereMachineTemplate
metadata:
  name: my-vsphere-cluster-cp
spec:
  template:
    spec:
      cloneMode: linkedClone
      datacenter: DC1
      datastore: /DC1/datastore/vsanDatastore
      folder: /DC1/vm/kubernetes
      resourcePool: /DC1/host/Cluster1/Resources/k8s
      network:
        devices:
        - networkName: VM Network
          dhcp4: true
      numCPUs: 4
      memoryMiB: 8192
      diskGiB: 50
      template: /DC1/vm/templates/ubuntu-2204-kube-v1.31.0
```

---

## 9. VKS (vSphere Kubernetes Service)

### VKS란?

> **VKS(vSphere Kubernetes Service)**는 VMware vSphere 환경에서 **Kubernetes 클러스터를 CRD로 선언적으로 생성·관리하는 서비스**입니다. vSphere with Tanzu(이전 vSphere with Kubernetes)의 핵심 기능으로, Supervisor Cluster 위에서 Guest Cluster(Workload Cluster)를 YAML 하나로 생성합니다.

```
┌─────────────────────────────────────────────────────────────┐
│                    VKS 전체 아키텍처                            │
│                                                             │
│  ┌─── vSphere 인프라 ──────────────────────────────────────┐│
│  │                                                         ││
│  │  ┌─── Supervisor Cluster ───────────────────────────┐   ││
│  │  │                                                   │   ││
│  │  │  vSphere 관리자가 운영하는 특수 K8s 클러스터         │   ││
│  │  │  (ESXi 호스트에 내장, vCenter가 관리)               │   ││
│  │  │                                                   │   ││
│  │  │  ┌─── Tanzu Controller ──────────────────────┐    │   ││
│  │  │  │                                            │    │   ││
│  │  │  │  TanzuKubernetesCluster CR을 Watch         │    │   ││
│  │  │  │  → Guest Cluster 생성/관리                  │    │   ││
│  │  │  │                                            │    │   ││
│  │  │  │  내부적으로 Cluster API 활용:                │    │   ││
│  │  │  │  ├── VM 생성 (vSphere API)                  │    │   ││
│  │  │  │  ├── K8s 설치 (kubeadm)                    │    │   ││
│  │  │  │  ├── CNI 설치 (Antrea)                     │    │   ││
│  │  │  │  └── CSI 설치 (vSphere CSI)                │    │   ││
│  │  │  │                                            │    │   ││
│  │  │  └────────────────────────────────────────────┘    │   ││
│  │  │                                                   │   ││
│  │  │  사용자: kubectl apply -f tkc.yaml                 │   ││
│  │  │  → TanzuKubernetesCluster CR 생성                  │   ││
│  │  │                                                   │   ││
│  │  └───────────────────────────────────────────────────┘   ││
│  │           │                    │                    │     ││
│  │           ▼                    ▼                    ▼     ││
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   ││
│  │  │ Guest Cluster│  │ Guest Cluster│  │ Guest Cluster│   ││
│  │  │   (dev)      │  │  (staging)   │  │   (prod)     │   ││
│  │  │              │  │              │  │              │   ││
│  │  │ Master x1    │  │ Master x3    │  │ Master x3    │   ││
│  │  │ Worker x2    │  │ Worker x3    │  │ Worker x5    │   ││
│  │  │              │  │              │  │              │   ││
│  │  │ (실제 VM들)  │  │ (실제 VM들)  │  │ (실제 VM들)  │   ││
│  │  └──────────────┘  └──────────────┘  └──────────────┘   ││
│  │                                                         ││
│  │  ┌─── vSphere 리소스 ─────────────────────────────┐     ││
│  │  │  ESXi 호스트 / vSAN / 네트워크 / vCenter        │     ││
│  │  └─────────────────────────────────────────────────┘     ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Supervisor Cluster vs Guest Cluster

| 항목 | Supervisor Cluster | Guest Cluster (TKC) |
|------|-------------------|-------------------|
| **관리 주체** | vSphere 관리자 (vCenter) | 개발팀/플랫폼팀 |
| **생성 방법** | vCenter에서 활성화 | kubectl apply (CRD) |
| **용도** | Guest Cluster 관리, 플랫폼 서비스 | 사용자 워크로드 실행 |
| **Control Plane** | ESXi에 내장 (Spherelet) | VM으로 실행 |
| **업그레이드** | vCenter 업그레이드와 연동 | TKC YAML 수정으로 롤링 업그레이드 |
| **네임스페이스** | vSphere Namespace로 격리 | 일반 K8s Namespace |

---

## 10. VKS에서 클러스터를 CRD로 관리하기 (VCF 9.0)

### VCF 9.0에서의 변화

```
┌─────────────────────────────────────────────────────────────┐
│           VCF 9.0 — VKS의 진화                                │
│                                                             │
│  이전 (vSphere 8.x / Tanzu):                                 │
│  ├── CRD: TanzuKubernetesCluster (TKC)                      │
│  ├── CLI: kubectl vsphere login --tanzu-kubernetes-cluster-* │
│  ├── 버전: TanzuKubernetesRelease (TKR)                      │
│  └── 브랜딩: vSphere with Tanzu                              │
│                                                             │
│  현재 (VCF 9.0):                                              │
│  ├── CRD: Cluster (CAPI 표준 Cluster API 리소스 직접 사용)    │
│  ├── CLI: kubectl vcf login                                  │
│  ├── 버전: KubernetesRelease (VKR, Tanzu 접두사 제거)         │
│  └── 브랜딩: VMware Cloud Foundation — VKS                    │
│                                                             │
│  핵심 변화:                                                   │
│  ✅ Tanzu 전용 CRD → Cluster API 표준 리소스로 전환            │
│  ✅ kubectl vsphere → kubectl vcf 로 CLI 변경                 │
│  ✅ 더 표준적인 Cluster API 기반 워크플로우                     │
│  ✅ ClusterClass를 활용한 템플릿 기반 클러스터 생성             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### VCF 9.0 VKS 클러스터 CRD

VCF 9.0에서는 TanzuKubernetesCluster 대신 **Cluster API 표준 Cluster 리소스**와 **ClusterClass**를 사용합니다.

```yaml
# VCF 9.0 — Cluster API 표준 Cluster 리소스로 K8s 클러스터 생성
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: dev-cluster
  namespace: dev-namespace              # vSphere Namespace
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
  topology:
    class: tanzukubernetescluster       # ClusterClass 참조
    version: v1.31.0+vmware.1           # K8s 버전 (KubernetesRelease)
    controlPlane:
      replicas: 1                       # Master 노드 수
      metadata: {}
    workers:
      machineDeployments:
      - class: node-pool
        name: worker-pool-1
        replicas: 3                     # Worker 노드 수
        metadata: {}
    variables:
    - name: vmClass
      value: best-effort-medium         # Control Plane VM 사양
    - name: workerVmClass
      value: best-effort-large          # Worker VM 사양
    - name: storageClass
      value: vsan-default-storage-policy
    - name: defaultStorageClass
      value: vsan-default-storage-policy
    - name: ntp
      value: time.example.com
```

### ClusterClass란?

```
┌─────────────────────────────────────────────────────────────┐
│          ClusterClass — 클러스터 템플릿                        │
│                                                             │
│  VCF 9.0에서는 ClusterClass가 클러스터의 "설계도" 역할         │
│  관리자가 ClusterClass를 정의하면,                             │
│  사용자는 Cluster CR에서 class를 참조하여 생성                  │
│                                                             │
│  ┌─── ClusterClass ──────────────────────────────────┐      │
│  │  (관리자가 정의하는 클러스터 템플릿)                  │      │
│  │                                                    │      │
│  │  ├── Control Plane 구성 (KubeadmControlPlane)      │      │
│  │  ├── Worker Node 구성 (MachineDeployment 템플릿)    │      │
│  │  ├── Infrastructure 구성 (VSphereMachineTemplate)  │      │
│  │  ├── 허용 변수 정의 (vmClass, storageClass 등)      │      │
│  │  └── 기본값, 검증 규칙                               │      │
│  └────────────────────────────────────────────────────┘      │
│           │                                                  │
│           │  참조 (spec.topology.class)                       │
│           ▼                                                  │
│  ┌─── Cluster CR (사용자가 생성) ─────────────────────┐      │
│  │                                                    │      │
│  │  class: tanzukubernetescluster                     │      │
│  │  version: v1.31.0+vmware.1                         │      │
│  │  controlPlane.replicas: 3                          │      │
│  │  workers.replicas: 5                               │      │
│  │  variables: vmClass=guaranteed-large               │      │
│  │                                                    │      │
│  │  → ClusterClass 템플릿 + 사용자 변수를 결합하여      │      │
│  │    실제 클러스터 생성!                                │      │
│  └────────────────────────────────────────────────────┘      │
│                                                             │
│  장점:                                                       │
│  ├── 클러스터 구성의 표준화 (조직 전체 일관성)                 │
│  ├── 사용자는 변수(replicas, vmClass 등)만 지정               │
│  ├── 인프라 세부사항은 ClusterClass에 캡슐화                   │
│  └── Cluster API 표준 → 벤더 독립적                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 클러스터 생성부터 사용까지

```bash
# 1. Supervisor Cluster에 접속 (VCF 9.0 — kubectl vcf 사용)
kubectl vcf login --server=supervisor.example.com \
  --vsphere-username=admin@vsphere.local

# 컨텍스트 전환 (vSphere Namespace)
kubectl config use-context dev-namespace

# 2. 사용 가능한 ClusterClass 확인
kubectl get clusterclass
# NAME                        AGE
# tanzukubernetescluster      30d

# 3. 사용 가능한 VM Class 확인
kubectl get virtualmachineclasses
# NAME                   CPU   MEMORY   AGE
# best-effort-small      2     4Gi      30d
# best-effort-medium     4     8Gi      30d
# best-effort-large      4     16Gi     30d
# guaranteed-medium      4     8Gi      30d
# guaranteed-large       4     16Gi     30d

# 4. 사용 가능한 K8s 버전(VKR) 확인
kubectl get kubernetesreleases
# NAME                     VERSION        READY   COMPATIBLE
# v1.31.0---vmware.1       1.31.0         True    True
# v1.30.4---vmware.1       1.30.4         True    True
# v1.29.8---vmware.1       1.29.8         True    True

# 5. 사용 가능한 StorageClass 확인
kubectl get storageclass
# NAME                             PROVISIONER
# vsan-default-storage-policy      csi.vsphere.vmware.com

# 6. Cluster 생성!
kubectl apply -f dev-cluster.yaml

# 7. 클러스터 생성 진행 상태 확인
kubectl get cluster dev-cluster -w
# NAME          CLUSTERCLASS                PHASE          AGE   VERSION
# dev-cluster   tanzukubernetescluster      Provisioning   1m    v1.31.0+vmware.1
# dev-cluster   tanzukubernetescluster      Provisioning   3m    v1.31.0+vmware.1
# dev-cluster   tanzukubernetescluster      Provisioned    7m    v1.31.0+vmware.1

# Control Plane과 Worker 상태 상세 확인
kubectl get machines -l cluster.x-k8s.io/cluster-name=dev-cluster
# NAME                                  CLUSTER       PHASE     AGE   VERSION
# dev-cluster-cp-xxxxx                  dev-cluster   Running   5m    v1.31.0
# dev-cluster-worker-pool-1-yyyyy-0     dev-cluster   Running   4m    v1.31.0
# dev-cluster-worker-pool-1-yyyyy-1     dev-cluster   Running   4m    v1.31.0
# dev-cluster-worker-pool-1-yyyyy-2     dev-cluster   Running   3m    v1.31.0
```

### Guest Cluster에 접속

```bash
# 방법 1: kubectl vcf login (VCF 9.0)
kubectl vcf login --server=supervisor.example.com \
  --vsphere-username=admin@vsphere.local \
  --workload-cluster-name=dev-cluster \
  --workload-cluster-namespace=dev-namespace

# 방법 2: kubeconfig Secret에서 직접 추출
kubectl get secret dev-cluster-kubeconfig -n dev-namespace \
  -o jsonpath='{.data.value}' | base64 -d > dev-cluster.kubeconfig

export KUBECONFIG=dev-cluster.kubeconfig
kubectl get nodes
# NAME                                STATUS   ROLES           VERSION
# dev-cluster-cp-xxxxx                Ready    control-plane   v1.31.0
# dev-cluster-worker-pool-1-yyyyy-0   Ready    <none>          v1.31.0
# dev-cluster-worker-pool-1-yyyyy-1   Ready    <none>          v1.31.0
# dev-cluster-worker-pool-1-yyyyy-2   Ready    <none>          v1.31.0
```

### 클러스터 스케일링 (Worker 노드 추가/제거)

```bash
# Worker 노드를 3개 → 5개로 스케일 아웃
kubectl edit cluster dev-cluster -n dev-namespace
# spec.topology.workers.machineDeployments[0].replicas: 3 → 5 로 변경

# 또는 kubectl patch 사용
kubectl patch cluster dev-cluster -n dev-namespace --type merge -p '
spec:
  topology:
    workers:
      machineDeployments:
      - class: node-pool
        name: worker-pool-1
        replicas: 5
'

# 스케일링 진행 확인
kubectl get machines -l cluster.x-k8s.io/cluster-name=dev-cluster -w
# 새 Machine이 Provisioning → Running 으로 전이되는 것을 확인

# vCenter에서 확인하면:
# → 새 VM 2개가 자동으로 생성되고 클러스터에 조인됨!
```

### 클러스터 업그레이드 (K8s 버전 변경)

```bash
# K8s 버전을 1.30.4 → 1.31.0 으로 업그레이드
kubectl edit cluster dev-cluster -n dev-namespace
# spec.topology.version: v1.31.0+vmware.1 로 변경

# 또는 kubectl patch 사용
kubectl patch cluster dev-cluster -n dev-namespace --type merge -p '
spec:
  topology:
    version: v1.31.0+vmware.1
'

# 업그레이드 진행 확인
kubectl get cluster dev-cluster -w
# PHASE 가 Provisioned → Upgrading → Provisioned 으로 변경

kubectl get machines -l cluster.x-k8s.io/cluster-name=dev-cluster -w
# 기존 Machine이 삭제되고 새 버전의 Machine이 생성되는 것을 확인

# 내부 동작:
# 1. 새 버전의 Control Plane VM 생성 (1대씩 롤링)
# 2. 이전 버전 Control Plane VM drain → 삭제
# 3. 새 버전의 Worker VM 생성 (롤링)
# 4. 이전 버전 Worker VM drain → 삭제
# → 무중단 롤링 업그레이드!
```

### 클러스터 삭제

```bash
# Cluster 리소스 삭제 → 모든 VM 자동 정리!
kubectl delete cluster dev-cluster -n dev-namespace

# 확인
kubectl get cluster -n dev-namespace
# No resources found

# vCenter에서 확인하면:
# → 관련 VM들이 모두 자동 삭제됨!
# → PVC, VMDK도 reclaimPolicy에 따라 정리됨
```

### VKS에서 생성되는 리소스 계층 (VCF 9.0)

```
┌─────────────────────────────────────────────────────────────┐
│  kubectl apply -f dev-cluster.yaml 실행 시 자동 생성 리소스    │
│                                                             │
│  Cluster: dev-cluster                                       │
│  │  (topology.class: tanzukubernetescluster)                │
│  │                                                          │
│  ├── ClusterClass: tanzukubernetescluster (참조)            │
│  │   └── 클러스터 템플릿 (인프라, 부트스트랩, CP 구성 포함)    │
│  │                                                          │
│  ├── VSphereCluster: dev-cluster (자동 생성)                 │
│  │   └── vSphere 인프라 설정 (네트워크, 리소스 풀)            │
│  │                                                          │
│  ├── KubeadmControlPlane: dev-cluster-cp                    │
│  │   ├── Machine: dev-cluster-cp-xxxxx                      │
│  │   │   └── VSphereMachine → vCenter VM (master-0)         │
│  │   └── KubeadmConfig: dev-cluster-cp-xxxxx                │
│  │       └── cloud-init Secret                              │
│  │                                                          │
│  ├── MachineDeployment: dev-cluster-worker-pool-1           │
│  │   └── MachineSet: dev-cluster-worker-pool-1-yyyyy        │
│  │       ├── Machine: ...-yyyyy-0                           │
│  │       │   └── VSphereMachine → vCenter VM (worker-0)     │
│  │       ├── Machine: ...-yyyyy-1                           │
│  │       │   └── VSphereMachine → vCenter VM (worker-1)     │
│  │       └── Machine: ...-yyyyy-2                           │
│  │           └── VSphereMachine → vCenter VM (worker-2)     │
│  │                                                          │
│  ├── Secret: dev-cluster-kubeconfig                         │
│  ├── Secret: dev-cluster-ca                                 │
│  └── Secret: dev-cluster-sa                                 │
│                                                             │
│  사용자는 Cluster YAML만 관리하면 됨!                          │
│  ClusterClass + Cluster API Controller가 나머지 자동 생성     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Tanzu → VCF 9.0 명령어 매핑

| 이전 (Tanzu / vSphere 8.x) | 현재 (VCF 9.0) |
|---------------------------|---------------|
| `kubectl vsphere login --tanzu-kubernetes-cluster-*` | `kubectl vcf login --workload-cluster-*` |
| `kubectl get tanzukubernetescluster` (`tkc`) | `kubectl get cluster` |
| `kubectl get tanzukubernetesreleases` (`tkr`) | `kubectl get kubernetesreleases` (`vkr`) |
| `TanzuKubernetesCluster` CRD | `Cluster` CRD (CAPI 표준) + ClusterClass |
| `spec.topology.controlPlane.tkr.reference.name` | `spec.topology.version` |
| `spec.topology.nodePools` | `spec.topology.workers.machineDeployments` |
| `spec.settings.network.cni.name` | ClusterClass 변수 또는 기본값 (Antrea) |

### VM Class (가상머신 사양)

```
┌─────────────────────────────────────────────────────────────┐
│        VM Class — VCF에서 제공하는 VM 사양 프리셋               │
│                                                             │
│  ┌─── best-effort 계열 ───────────────────────────────┐     │
│  │  리소스를 다른 VM과 공유 (오버커밋 가능)               │     │
│  │                                                     │     │
│  │  best-effort-xsmall   : 2 CPU,  2Gi Memory          │     │
│  │  best-effort-small    : 2 CPU,  4Gi Memory          │     │
│  │  best-effort-medium   : 4 CPU,  8Gi Memory          │     │
│  │  best-effort-large    : 4 CPU, 16Gi Memory          │     │
│  │  best-effort-xlarge   : 8 CPU, 32Gi Memory          │     │
│  │  best-effort-2xlarge  : 16 CPU, 64Gi Memory         │     │
│  │                                                     │     │
│  │  적합: 개발/테스트 환경                                │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  ┌─── guaranteed 계열 ────────────────────────────────┐     │
│  │  리소스를 예약하여 보장 (오버커밋 없음)                │     │
│  │                                                     │     │
│  │  guaranteed-small     : 2 CPU,  4Gi Memory          │     │
│  │  guaranteed-medium    : 4 CPU,  8Gi Memory          │     │
│  │  guaranteed-large     : 4 CPU, 16Gi Memory          │     │
│  │  guaranteed-xlarge    : 8 CPU, 32Gi Memory          │     │
│  │                                                     │     │
│  │  적합: 프로덕션 환경                                  │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  커스텀 VM Class도 생성 가능:                                  │
│  vCenter → Workload Management → VM Classes → New            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 11. 실습: CRD 생성과 활용

### 실습 1: 간단한 CRD 만들기

```bash
# 1. CRD 정의 (Website라는 새 리소스 유형)
cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: websites.example.com
spec:
  group: example.com
  names:
    plural: websites
    singular: website
    kind: Website
    shortNames:
    - ws
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: ["domain", "replicas"]
            properties:
              domain:
                type: string
                description: "웹사이트 도메인"
              replicas:
                type: integer
                minimum: 1
                maximum: 10
                description: "인스턴스 수"
              image:
                type: string
                description: "컨테이너 이미지"
                default: "nginx:latest"
          status:
            type: object
            properties:
              availableReplicas:
                type: integer
              phase:
                type: string
    additionalPrinterColumns:
    - name: Domain
      type: string
      jsonPath: .spec.domain
    - name: Replicas
      type: integer
      jsonPath: .spec.replicas
    - name: Image
      type: string
      jsonPath: .spec.image
    - name: Age
      type: date
      jsonPath: .metadata.creationTimestamp
    subresources:
      status: {}
EOF

# 2. CRD 등록 확인
kubectl get crd websites.example.com
# NAME                    CREATED AT
# websites.example.com    2024-01-15T10:00:00Z

# 3. API 리소스에 등록되었는지 확인
kubectl api-resources | grep website
# websites   ws   example.com/v1   true   Website
```

### 실습 2: CR(Custom Resource) 생성 및 관리

```bash
# 1. Website CR 생성
cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: Website
metadata:
  name: my-blog
spec:
  domain: blog.example.com
  replicas: 3
  image: nginx:alpine
---
apiVersion: example.com/v1
kind: Website
metadata:
  name: my-shop
spec:
  domain: shop.example.com
  replicas: 5
EOF

# 2. CR 목록 확인 (커스텀 컬럼 출력!)
kubectl get websites
# NAME      DOMAIN              REPLICAS   IMAGE          AGE
# my-blog   blog.example.com    3          nginx:alpine   10s
# my-shop   shop.example.com    5          nginx:latest   10s

# 3. shortName 사용
kubectl get ws

# 4. 상세 정보 확인
kubectl describe website my-blog

# 5. YAML 출력
kubectl get website my-blog -o yaml

# 6. CR 수정
kubectl patch website my-blog --type merge -p '{"spec":{"replicas":5}}'
kubectl get ws my-blog
# REPLICAS: 5 로 변경됨

# 7. CR 삭제
kubectl delete website my-shop

# 8. 정리
kubectl delete website my-blog
kubectl delete crd websites.example.com
```

### 실습 3: 스키마 검증 동작 확인

```bash
# 위의 CRD가 등록된 상태에서...

# 잘못된 CR 생성 시도 1: 필수 필드 누락
cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: Website
metadata:
  name: bad-website
spec:
  domain: test.example.com
  # replicas 누락! (required 필드)
EOF
# Error: validation failure: spec.replicas is required

# 잘못된 CR 생성 시도 2: 범위 초과
cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: Website
metadata:
  name: bad-website
spec:
  domain: test.example.com
  replicas: 100     # maximum: 10 초과!
EOF
# Error: spec.replicas: Invalid value: 100: must be less than or equal to 10

# → CRD의 openAPIV3Schema가 자동으로 검증!
```

### 실습 4: CRD 확인 명령어 모음

```bash
# ─── CRD 관리 ───
# 모든 CRD 목록
kubectl get crd

# 특정 CRD 상세 정보
kubectl describe crd websites.example.com

# CRD가 정의한 API 버전 확인
kubectl get crd websites.example.com -o jsonpath='{.spec.versions[*].name}'

# ─── CR 관리 ───
# 특정 CRD의 모든 CR 목록
kubectl get websites --all-namespaces

# CR을 JSON으로 출력
kubectl get website my-blog -o json

# CR에 라벨 추가
kubectl label website my-blog env=production

# 라벨로 필터링
kubectl get ws -l env=production

# ─── 시스템에 설치된 모든 CRD 확인 ───
# (Operator/애드온이 설치한 CRD 목록)
kubectl get crd | wc -l            # 총 CRD 수
kubectl get crd | grep cert-manager  # cert-manager 관련 CRD
kubectl get crd | grep monitoring    # Prometheus 관련 CRD
kubectl get crd | grep cluster       # Cluster API 관련 CRD
```

---

## 12. 정리 및 핵심 요약

### 한눈에 보는 CRD → Cluster API → VKS

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  CRD (기반 기술)                                                 │
│  "K8s API를 확장하여 새로운 리소스 유형을 정의"                     │
│     │                                                           │
│     │  이 기술을 활용하여...                                       │
│     ▼                                                           │
│  Cluster API (프로젝트)                                          │
│  "K8s 클러스터를 CRD(Cluster, Machine 등)로 관리"                 │
│     │                                                           │
│     │  vSphere 환경에 특화한 구현이...                             │
│     ▼                                                           │
│  CAPV (Provider)                                                │
│  "Cluster API + vSphere (VM 생성/삭제 자동화)"                    │
│     │                                                           │
│     │  이것을 vSphere에 통합하여 제품화한 것이...                   │
│     ▼                                                           │
│  VKS (vSphere Kubernetes Service)                               │
│  "TanzuKubernetesCluster CRD 하나로 클러스터 생성·관리"            │
│  "kubectl apply 한 번으로 VM 생성 → K8s 설치 → CNI/CSI 구성"      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 포인트 7가지

| # | 포인트 | 설명 |
|---|--------|------|
| 1 | **CRD = K8s API 확장** | Pod, Service처럼 kubectl로 관리할 수 있는 나만의 리소스 정의 |
| 2 | **CRD + Controller = Operator** | CRD만으로는 아무 일도 안 함. Controller가 실제 로직 수행 |
| 3 | **선언적 관리의 확장** | "무엇을 원하는지"만 YAML로 선언하면 Operator가 알아서 처리 |
| 4 | **Cluster API = K8s로 K8s 관리** | 클러스터 자체를 CRD(Cluster, Machine)로 선언적 관리 |
| 5 | **Provider로 인프라 추상화** | CAPV(vSphere), CAPA(AWS) 등 어떤 인프라든 같은 API로 관리 |
| 6 | **VKS = vSphere + Cluster API 통합** | TanzuKubernetesCluster CRD 하나로 전체 클러스터 라이프사이클 관리 |
| 7 | **스케일/업그레이드도 YAML 수정** | replicas 변경, TKR 버전 변경만으로 자동 스케일링/롤링 업그레이드 |

### CKA 시험 빈출 포인트

| 주제 | 자주 나오는 문제 유형 |
|------|---------------------|
| CRD 생성 | CRD YAML 작성, group/names/schema 설정 |
| CR 관리 | kubectl로 CR 생성/조회/수정/삭제 |
| API 그룹 | CRD가 생성하는 API 엔드포인트 이해 |
| 스키마 검증 | openAPIV3Schema로 필수 필드/범위 제한 설정 |
| Operator 이해 | CRD + Controller 관계, Reconciliation Loop 개념 |

---

> **다음 단계**: CRD 개념을 이해했다면, 실제 Operator를 설치하여 CRD가 어떻게 동작하는지 체험해 보세요. [`k8s-addon.sh`](k8s-addon.sh)에서 **Prometheus Operator**(ServiceMonitor CRD), **Kyverno**(ClusterPolicy CRD) 등을 설치하면 CRD의 강력함을 실감할 수 있습니다. vSphere 환경이라면 VKS를 통해 TanzuKubernetesCluster CRD로 클러스터를 직접 생성해 보세요.
