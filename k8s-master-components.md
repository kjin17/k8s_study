# Kubernetes 마스터 노드(Control Plane) 핵심 컴포넌트 교육

> Kubernetes 클러스터의 **두뇌** 역할을 하는 마스터 노드(Control Plane)의 핵심 컴포넌트를 다룹니다.
> 각 컴포넌트가 어떤 역할을 하고, 서로 어떻게 상호작용하는지 이해하는 것을 목표로 합니다.

---

## 목차

1. [Control Plane 개요](#1-control-plane-개요)
2. [kube-apiserver](#2-kube-apiserver)
3. [etcd](#3-etcd)
4. [kube-scheduler](#4-kube-scheduler)
5. [kube-controller-manager](#5-kube-controller-manager)
6. [cloud-controller-manager](#6-cloud-controller-manager)
7. [컴포넌트 간 상호작용 흐름](#7-컴포넌트-간-상호작용-흐름)
8. [워커 노드 컴포넌트와의 관계](#8-워커-노드-컴포넌트와의-관계)
9. [고가용성(HA) 구성](#9-고가용성ha-구성)
10. [트러블슈팅 가이드](#10-트러블슈팅-가이드)
11. [실습: 컴포넌트 상태 확인](#11-실습-컴포넌트-상태-확인)
12. [정리 및 핵심 요약](#12-정리-및-핵심-요약)

---

## 1. Control Plane 개요

### 한 문장 정의

> **Control Plane(마스터 노드)**은 클러스터 전체의 상태를 관리하고, 사용자의 요청을 처리하며, 워커 노드에서 실행되는 워크로드를 조율하는 Kubernetes의 중앙 관리 시스템입니다.

### 비유로 이해하기

```
┌─────────────────────────────────────────────────────────────┐
│                    공항 관제탑 비유                            │
│                                                             │
│   Control Plane = 공항 관제탑                                 │
│                                                             │
│   ┌─────────────┐                                           │
│   │   관제탑     │  ← 모든 비행기의 이착륙을 관리               │
│   │  (Master)   │                                           │
│   └──────┬──────┘                                           │
│          │                                                  │
│   ┌──────┼──────────────────────┐                           │
│   │      │                      │                           │
│   ▼      ▼                      ▼                           │
│  ✈️      ✈️                     ✈️                          │
│ 활주로A  활주로B                활주로C                        │
│ (Worker1)(Worker2)             (Worker3)                    │
│                                                             │
│  관제탑이 없으면? → 비행기들이 충돌, 활주로 혼란!               │
│  Master가 없으면? → Pod 배치 불가, 클러스터 관리 불가!          │
└─────────────────────────────────────────────────────────────┘
```

### Control Plane 컴포넌트 전체 구조

```
┌─────────────────────── Master Node ───────────────────────┐
│                                                           │
│  ┌──────────────┐  ┌───────────┐  ┌───────────────────┐   │
│  │              │  │           │  │                   │   │
│  │ kube-apiserver│  │   etcd    │  │  kube-scheduler   │   │
│  │              │  │           │  │                   │   │
│  │  (API 게이트 │  │ (클러스터 │  │ (Pod 배치 결정)   │   │
│  │   웨이)      │  │  데이터   │  │                   │   │
│  │              │  │  저장소)  │  │                   │   │
│  └──────┬───────┘  └─────┬─────┘  └───────────────────┘   │
│         │                │                                │
│         │                │        ┌───────────────────┐   │
│         │                │        │ kube-controller   │   │
│         │                │        │ -manager          │   │
│         │                │        │                   │   │
│         │                │        │ (상태 유지 루프)   │   │
│         │                │        └───────────────────┘   │
│         │                │                                │
│         │                │        ┌───────────────────┐   │
│         │                │        │ cloud-controller  │   │
│         │                │        │ -manager          │   │
│         │                │        │                   │   │
│         │                │        │ (클라우드 연동)    │   │
│         │                │        └───────────────────┘   │
└─────────┼────────────────┼────────────────────────────────┘
          │                │
          ▼                │
    ┌── Worker Nodes ──┐   │
    │  kubelet         │   │
    │  kube-proxy      │   │
    │  Container       │   │
    │  Runtime         │   │
    └──────────────────┘   │
                           │
     모든 컴포넌트는 apiserver를 통해 etcd에 접근
```

### 컴포넌트 요약

| 컴포넌트 | 역할 | 비유 |
|---------|------|------|
| **kube-apiserver** | 모든 요청의 진입점, 인증/인가 | 공항 안내 데스크 |
| **etcd** | 클러스터 상태 저장소 | 공항 운항 기록부 |
| **kube-scheduler** | Pod를 어떤 노드에 배치할지 결정 | 게이트 배정 담당자 |
| **kube-controller-manager** | 원하는 상태와 현재 상태를 맞추는 컨트롤러 모음 | 각 부서 관리자 |
| **cloud-controller-manager** | 클라우드 제공자와 연동 | 외부 서비스 연결 담당 |

---

## 2. kube-apiserver

### 역할

> **kube-apiserver**는 Kubernetes 클러스터의 **중앙 통신 허브**입니다. 모든 컴포넌트와 사용자의 요청은 반드시 API Server를 거칩니다.

```
┌─────────────────────────────────────────────────────────┐
│                  kube-apiserver의 역할                    │
│                                                         │
│   사용자 ──── kubectl ────┐                              │
│   대시보드 ───────────────┤                              │
│   CI/CD ─────────────────┤     ┌──────────────┐         │
│                          ├────▶│              │         │
│   scheduler ─────────────┤     │ kube-apiserver│         │
│   controller-manager ────┤     │              │         │
│   kubelet ───────────────┤     │  인증 → 인가  │         │
│                          │     │  → 검증 → 저장│         │
│                          │     └──────┬───────┘         │
│                          │            │                  │
│                          │            ▼                  │
│                          │     ┌──────────────┐         │
│                          │     │     etcd     │         │
│                          │     └──────────────┘         │
└─────────────────────────────────────────────────────────┘
```

### 핵심 기능

| 기능 | 설명 |
|------|------|
| **RESTful API 제공** | 모든 리소스를 REST API로 CRUD 가능 |
| **인증(Authentication)** | 요청자가 누구인지 확인 (인증서, 토큰, OIDC 등) |
| **인가(Authorization)** | 요청자가 해당 작업을 할 권한이 있는지 확인 (RBAC) |
| **Admission Control** | 요청이 정책에 부합하는지 검증/변환 |
| **etcd 통신** | 유일하게 etcd와 직접 통신하는 컴포넌트 |
| **Watch 메커니즘** | 리소스 변경을 실시간으로 다른 컴포넌트에 알림 |

### API 요청 처리 흐름

```
kubectl apply -f deployment.yaml
        │
        ▼
┌─── API Server 내부 처리 흐름 ────────────────────────────┐
│                                                         │
│  1단계: 인증 (Authentication)                            │
│  ├── 클라이언트 인증서 확인                                │
│  ├── Bearer 토큰 검증                                    │
│  └── "이 요청은 user:admin 이 보낸 것이다"                 │
│         │                                               │
│         ▼                                               │
│  2단계: 인가 (Authorization)                              │
│  ├── RBAC 정책 확인                                      │
│  └── "admin은 default NS에 Deployment를 생성할 수 있다"    │
│         │                                               │
│         ▼                                               │
│  3단계: Admission Control                                │
│  ├── Mutating Webhooks (리소스 수정)                      │
│  │   └── 예: 사이드카 자동 주입, 기본값 설정                │
│  ├── 스키마 검증                                          │
│  └── Validating Webhooks (정책 검증)                      │
│      └── 예: "latest 태그 사용 금지"                       │
│         │                                               │
│         ▼                                               │
│  4단계: etcd 저장                                         │
│  └── 리소스 상태를 etcd에 영구 저장                         │
│         │                                               │
│         ▼                                               │
│  5단계: Watch 알림                                        │
│  └── 관심 있는 컴포넌트에게 변경 사항 알림                   │
│      (scheduler, controller-manager 등)                  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 주요 실행 옵션

```bash
# API Server의 주요 설정 확인
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# 자주 보는 주요 옵션:
# --advertise-address        : API Server가 광고하는 IP 주소
# --service-cluster-ip-range : Service에 할당할 IP 대역
# --etcd-servers             : etcd 서버 주소
# --authorization-mode       : 인가 모드 (Node, RBAC)
# --enable-admission-plugins : 활성화할 Admission Controller
# --tls-cert-file            : API Server TLS 인증서
# --tls-private-key-file     : API Server TLS 개인키
```

### API 그룹 구조

```
/api/v1                          ← Core API (Pod, Service, ConfigMap 등)
/apis/apps/v1                    ← apps 그룹 (Deployment, StatefulSet 등)
/apis/batch/v1                   ← batch 그룹 (Job, CronJob)
/apis/networking.k8s.io/v1       ← networking 그룹 (Ingress, NetworkPolicy)
/apis/rbac.authorization.k8s.io  ← RBAC 그룹 (Role, ClusterRole)

# API 리소스 목록 확인
kubectl api-resources

# 특정 리소스의 API 버전 확인
kubectl api-versions
```

---

## 3. etcd

### 역할

> **etcd**는 Kubernetes 클러스터의 **모든 상태 데이터를 저장하는 분산 키-값(Key-Value) 저장소**입니다. 클러스터의 "진실의 원천(Source of Truth)"입니다.

```
┌─────────────────────────────────────────────────────────┐
│                    etcd 저장 데이터                       │
│                                                         │
│   etcd는 클러스터의 모든 것을 기억합니다:                   │
│                                                         │
│   /registry/pods/default/nginx-abc123                   │
│   /registry/deployments/default/my-app                  │
│   /registry/services/default/my-service                 │
│   /registry/configmaps/kube-system/coredns              │
│   /registry/secrets/default/my-secret                   │
│   /registry/nodes/worker-1                              │
│   /registry/namespaces/production                       │
│   ...                                                   │
│                                                         │
│   Pod 정보, Deployment 설정, Service 매핑, Secret,        │
│   ConfigMap, 노드 정보, RBAC 정책 등 모든 것!              │
└─────────────────────────────────────────────────────────┘
```

### 핵심 특성

| 특성 | 설명 |
|------|------|
| **분산 합의(Raft)** | 여러 노드 간 데이터 일관성을 보장하는 Raft 합의 알고리즘 사용 |
| **Key-Value 저장** | 계층적 키-값 구조로 모든 리소스 상태 저장 |
| **Watch 지원** | 특정 키의 변경을 실시간으로 감지하여 알림 |
| **강한 일관성** | 모든 읽기가 최신 데이터를 반환 (Linearizable) |
| **트랜잭션 지원** | 원자적 비교-설정(Compare-and-Swap) 연산 지원 |

### Raft 합의 알고리즘

```
┌─────────────────────────────────────────────────────────┐
│                  Raft 합의 과정                           │
│                                                         │
│  etcd는 홀수 개(3, 5, 7)로 배포하는 것을 권장합니다.        │
│  과반수(Quorum)가 동의해야 데이터를 저장합니다.              │
│                                                         │
│  3개 노드 구성일 때:                                      │
│                                                         │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐       │
│  │  etcd #1   │   │  etcd #2   │   │  etcd #3   │       │
│  │  (Leader)  │──▶│ (Follower) │   │ (Follower) │       │
│  │            │──▶│            │   │            │       │
│  └────────────┘   └────────────┘   └────────────┘       │
│                                                         │
│  쓰기 요청 → Leader 수신 → 2/3 이상 복제 완료 → 커밋      │
│                                                         │
│  장애 허용:                                               │
│  ├── 3개 중 1개 장애 → 정상 동작 (2/3 = Quorum 충족)      │
│  ├── 5개 중 2개 장애 → 정상 동작 (3/5 = Quorum 충족)      │
│  └── 3개 중 2개 장애 → 서비스 불가 (1/3 < Quorum)         │
└─────────────────────────────────────────────────────────┘
```

### etcd가 중요한 이유

```
┌─────────────────────────────────────────────────────────┐
│  etcd가 손실되면?                                         │
│                                                         │
│  ❌ 클러스터의 모든 설정 정보가 사라짐                       │
│  ❌ Pod, Service, Deployment 등 모든 리소스 정보 손실       │
│  ❌ RBAC 정책, Secret, ConfigMap 전부 유실                 │
│  ❌ 클러스터를 처음부터 다시 구축해야 함                     │
│                                                         │
│  → 그래서 etcd 백업은 운영의 최우선 과제입니다!              │
└─────────────────────────────────────────────────────────┘
```

### 백업과 복원

```bash
# etcd 스냅샷 백업
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 스냅샷 상태 확인
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db --write-out=table

# 스냅샷 복원
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restored
```

### 성능 권장 사항

| 항목 | 권장값 |
|------|--------|
| 디스크 | SSD 필수 (etcd는 디스크 I/O에 민감) |
| 네트워크 지연 | etcd 노드 간 1ms 이하 |
| 데이터 크기 | 기본 제한 2GB, 최대 8GB |
| 노드 수 | 3개 또는 5개 (홀수 권장) |

---

## 4. kube-scheduler

### 역할

> **kube-scheduler**는 새로 생성된 Pod가 **어떤 노드에서 실행될지 결정**하는 컴포넌트입니다. 배치만 결정할 뿐, 실제 Pod 실행은 해당 노드의 kubelet이 담당합니다.

```
┌─────────────────────────────────────────────────────────┐
│               Scheduler의 동작 방식                       │
│                                                         │
│   새 Pod 생성 요청 (nodeName이 비어있는 Pod)               │
│         │                                               │
│         ▼                                               │
│   ┌─────────────────────────┐                           │
│   │     kube-scheduler      │                           │
│   │                         │                           │
│   │  1. 필터링 (Filtering)  │ → 부적합한 노드 제외         │
│   │  2. 점수 매기기 (Scoring)│ → 남은 노드에 점수 부여      │
│   │  3. 최적 노드 선택       │ → 최고 점수 노드 선택        │
│   │                         │                           │
│   └────────────┬────────────┘                           │
│                │                                        │
│                ▼                                        │
│   Pod의 nodeName 필드에 선택된 노드 기록                    │
│   (= Binding)                                           │
│                │                                        │
│                ▼                                        │
│   해당 노드의 kubelet이 Pod를 실행                         │
└─────────────────────────────────────────────────────────┘
```

### 스케줄링 2단계 프로세스

#### 1단계: 필터링 (Filtering)

실행 불가능한 노드를 제거합니다.

```
전체 노드 목록: [Node-A, Node-B, Node-C, Node-D]
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│              필터링 조건들                         │
│                                                 │
│  ✅ 리소스 충분한가? (CPU, 메모리)                 │
│     Node-A: CPU 4코어 중 3.5 사용 → ❌ 부족       │
│     Node-B: CPU 4코어 중 1.0 사용 → ✅            │
│     Node-C: CPU 4코어 중 2.0 사용 → ✅            │
│     Node-D: CPU 4코어 중 0.5 사용 → ✅            │
│                                                 │
│  ✅ nodeSelector 조건 충족?                       │
│     Pod: nodeSelector: disk=ssd                 │
│     Node-D: disk=hdd → ❌ 불일치                  │
│                                                 │
│  ✅ Taint/Toleration 확인?                       │
│     Node-B: taint: gpu=true:NoSchedule          │
│     Pod에 toleration 없음 → ❌ 제외               │
│                                                 │
│  필터링 결과: [Node-C]                             │
└─────────────────────────────────────────────────┘
```

#### 2단계: 점수 매기기 (Scoring)

필터링을 통과한 노드들에 점수를 매깁니다.

```
필터링 통과 노드: [Node-B, Node-C, Node-D] (예시)
                    │
                    ▼
┌─────────────────────────────────────────────────┐
│              점수 매기기 기준                       │
│                                                 │
│  리소스 균형 (LeastRequestedPriority):            │
│     Node-B: 남은 리소스 60% → 6점                 │
│     Node-C: 남은 리소스 40% → 4점                 │
│     Node-D: 남은 리소스 80% → 8점                 │
│                                                 │
│  Pod 분산 (InterPodAffinity):                    │
│     Node-B: 같은 앱 Pod 0개 → 3점                 │
│     Node-C: 같은 앱 Pod 2개 → 1점                 │
│     Node-D: 같은 앱 Pod 0개 → 3점                 │
│                                                 │
│  총점:                                           │
│     Node-B: 9점                                  │
│     Node-C: 5점                                  │
│     Node-D: 11점 ← 최고점! 이 노드에 배치          │
└─────────────────────────────────────────────────┘
```

### 스케줄링에 영향을 주는 설정들

| 설정 | 용도 | 예시 |
|------|------|------|
| **nodeSelector** | 특정 라벨의 노드에만 배치 | `disk: ssd` |
| **nodeAffinity** | 노드 선호도 규칙 (유연한 nodeSelector) | preferred/required |
| **podAffinity** | 특정 Pod와 같은 노드에 배치 | 캐시 서버와 같은 노드 |
| **podAntiAffinity** | 특정 Pod와 다른 노드에 배치 | 고가용성을 위해 분산 |
| **Taint/Toleration** | 특정 노드에 Pod 접근 제한 | GPU 노드 전용 |
| **resources.requests** | Pod의 최소 리소스 요구 | `cpu: 500m, memory: 256Mi` |

### YAML 예시: 스케줄링 제어

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: scheduling-example
spec:
  # 1. nodeSelector - 간단한 노드 선택
  nodeSelector:
    disk: ssd

  # 2. nodeAffinity - 유연한 노드 선택
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: zone
            operator: In
            values: ["zone-a", "zone-b"]
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 80
        preference:
          matchExpressions:
          - key: instance-type
            operator: In
            values: ["large"]

    # 3. podAntiAffinity - Pod 분산 배치
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: my-app
        topologyKey: kubernetes.io/hostname

  # 4. Toleration - Taint된 노드에 배치 허용
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"

  containers:
  - name: app
    image: nginx
    resources:
      requests:        # 스케줄러가 참고하는 최소 리소스
        cpu: "500m"
        memory: "256Mi"
      limits:          # 컨테이너의 최대 리소스
        cpu: "1000m"
        memory: "512Mi"
```

---

## 5. kube-controller-manager

### 역할

> **kube-controller-manager**는 클러스터의 **현재 상태를 원하는 상태(Desired State)로 맞추는 컨트롤 루프들의 모음**입니다. 하나의 바이너리 안에 여러 개의 컨트롤러가 들어있습니다.

### 컨트롤 루프 개념

```
┌─────────────────────────────────────────────────────────┐
│            에어컨 온도 조절기 = 컨트롤 루프                 │
│                                                         │
│   원하는 상태(Desired State): 24°C                        │
│   현재 상태(Current State):  28°C                         │
│                                                         │
│   ┌─────────────────────────────────────────┐            │
│   │                                         │            │
│   │   현재 28°C  ──▶  비교  ──▶  차이 발견!   │            │
│   │       ▲              │                   │            │
│   │       │              ▼                   │            │
│   │   온도 측정    냉방 가동 (조치)             │            │
│   │       ▲              │                   │            │
│   │       │              ▼                   │            │
│   │       └──── 24°C 도달 → 유지 ────────────│            │
│   │                                         │            │
│   └─────────────────────────────────────────┘            │
│                                                         │
│   Kubernetes도 동일한 방식:                                │
│   Desired: replicas=3  /  Current: Pod 2개 실행 중         │
│   → Controller가 Pod 1개 추가 생성!                        │
└─────────────────────────────────────────────────────────┘
```

### 주요 내장 컨트롤러

| 컨트롤러 | 감시 대상 | 하는 일 |
|---------|----------|---------|
| **Deployment Controller** | Deployment | ReplicaSet 생성/업데이트, 롤링 업데이트 관리 |
| **ReplicaSet Controller** | ReplicaSet | Pod 수를 replicas에 맞게 유지 |
| **StatefulSet Controller** | StatefulSet | 순서대로 Pod 생성/삭제, 고유 네트워크 ID 유지 |
| **DaemonSet Controller** | DaemonSet | 모든 노드에 Pod 1개씩 배치 |
| **Job Controller** | Job | 지정 횟수만큼 Pod를 성공적으로 완료 |
| **CronJob Controller** | CronJob | 스케줄에 따라 Job 생성 |
| **Node Controller** | Node | 노드 상태 모니터링, 응답 없는 노드의 Pod 축출 |
| **Service Account Controller** | Namespace | 새 Namespace에 기본 ServiceAccount 자동 생성 |
| **Endpoint Controller** | Service, Pod | Service에 연결된 Pod의 IP 목록 관리 |
| **Namespace Controller** | Namespace | 삭제된 Namespace의 리소스 정리 |

### Deployment Controller 동작 예시

```
사용자: "replicas를 3에서 5로 변경해줘"
        │
        ▼
┌─── Deployment Controller 동작 ──────────────────────────┐
│                                                         │
│  1. Watch: Deployment 변경 감지                          │
│     └── replicas: 3 → 5 로 변경됨                        │
│                                                         │
│  2. 현재 상태 확인                                        │
│     └── ReplicaSet에 Pod 3개 실행 중                      │
│                                                         │
│  3. 차이 계산                                            │
│     └── 원하는 상태(5) - 현재 상태(3) = 2개 부족            │
│                                                         │
│  4. 조치 실행                                            │
│     └── ReplicaSet의 replicas를 5로 업데이트               │
│                                                         │
│  5. ReplicaSet Controller가 이어받음                      │
│     └── Pod 2개 추가 생성                                 │
│                                                         │
│  6. Scheduler가 새 Pod 2개에 노드 할당                    │
│                                                         │
│  7. 각 노드의 kubelet이 Pod 실행                          │
│                                                         │
│  결과: Pod 5개 → 원하는 상태 달성!                          │
└─────────────────────────────────────────────────────────┘
```

### Node Controller의 장애 처리

```
┌─────────────────────────────────────────────────────────┐
│              Node Controller 장애 감지                    │
│                                                         │
│  정상 상태:                                               │
│  Worker-1 ──── Heartbeat 전송 (매 10초) ──▶ API Server   │
│                                                         │
│  장애 발생:                                               │
│  Worker-1 ──── ✕ Heartbeat 중단 ──────────▶ API Server   │
│                                                         │
│  타임라인:                                                │
│  ├── 0~40초   : Heartbeat 미수신, 아직 대기               │
│  ├── 40초     : 노드 상태를 "Unknown"으로 변경             │
│  ├── ~5분     : Pod 축출(Eviction) 시작                   │
│  │   ├── 해당 노드의 모든 Pod에 삭제 명령                   │
│  │   └── Controller들이 다른 노드에 Pod 재생성              │
│  └── 복구 시  : 노드 상태 "Ready"로 복귀                   │
│                                                         │
│  ※ --pod-eviction-timeout으로 축출 대기 시간 조정 가능       │
└─────────────────────────────────────────────────────────┘
```

---

## 6. cloud-controller-manager

### 역할

> **cloud-controller-manager(CCM)**는 클라우드 제공자(AWS, GCP, Azure, vSphere 등)의 API와 Kubernetes를 연결하는 컴포넌트입니다. 온프레미스 환경에서는 사용하지 않을 수 있습니다.

```
┌─────────────────────────────────────────────────────────┐
│          cloud-controller-manager 구조                   │
│                                                         │
│  ┌──────────────────────────────────┐                    │
│  │    cloud-controller-manager     │                    │
│  │                                  │                    │
│  │  ┌──────────────────────────┐    │                    │
│  │  │  Node Controller         │    │  ← 클라우드 VM     │
│  │  │  (노드 정보 동기화)        │    │    상태 확인       │
│  │  └──────────────────────────┘    │                    │
│  │                                  │                    │
│  │  ┌──────────────────────────┐    │                    │
│  │  │  Route Controller        │    │  ← 클라우드 VPC    │
│  │  │  (네트워크 경로 설정)      │    │    라우팅 설정     │
│  │  └──────────────────────────┘    │                    │
│  │                                  │                    │
│  │  ┌──────────────────────────┐    │                    │
│  │  │  Service Controller      │    │  ← 클라우드 LB     │
│  │  │  (로드밸런서 관리)         │    │    프로비저닝      │
│  │  └──────────────────────────┘    │                    │
│  │                                  │                    │
│  └──────────────┬───────────────────┘                    │
│                 │                                       │
│                 ▼                                       │
│    ┌────────────────────────┐                            │
│    │    Cloud Provider API  │                            │
│    │  (AWS / GCP / Azure)   │                            │
│    └────────────────────────┘                            │
└─────────────────────────────────────────────────────────┘
```

### 주요 컨트롤러

| 컨트롤러 | 역할 | 예시 |
|---------|------|------|
| **Node Controller** | 클라우드 VM 존재 여부 확인, 노드 주소/라벨 설정 | 삭제된 VM의 Node 오브젝트 정리 |
| **Route Controller** | Pod 네트워크 경로를 클라우드 VPC에 등록 | AWS VPC route table 업데이트 |
| **Service Controller** | `type: LoadBalancer` Service에 클라우드 LB 연결 | AWS ELB, GCP GLB 자동 생성 |

### LoadBalancer 동작 예시

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-web-service
spec:
  type: LoadBalancer      # ← 이 타입이 CCM을 트리거
  selector:
    app: my-web
  ports:
  - port: 80
    targetPort: 8080
```

```
Service 생성 (type: LoadBalancer)
        │
        ▼
  CCM의 Service Controller 감지
        │
        ▼
  클라우드 API 호출 (예: AWS)
  ├── ELB 생성
  ├── 보안 그룹 설정
  ├── 타겟 그룹에 Worker 노드 등록
  └── Health Check 구성
        │
        ▼
  Service에 External IP 할당
  └── status.loadBalancer.ingress[0].hostname = "xxx.elb.amazonaws.com"
```

---

## 7. 컴포넌트 간 상호작용 흐름

### Pod 생성 전체 흐름

사용자가 `kubectl create deployment nginx --image=nginx --replicas=3`을 실행했을 때:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pod 생성 전체 흐름                              │
│                                                                 │
│  ① kubectl → API Server                                         │
│     "Deployment nginx를 만들어주세요 (replicas=3)"                │
│         │                                                       │
│         ▼                                                       │
│  ② API Server: 인증 → 인가 → Admission → etcd 저장              │
│     etcd에 Deployment 오브젝트 저장                                │
│         │                                                       │
│         ▼                                                       │
│  ③ Deployment Controller (Watch로 감지)                          │
│     "새 Deployment 발견! ReplicaSet을 만들자"                      │
│     → API Server에 ReplicaSet 생성 요청                           │
│         │                                                       │
│         ▼                                                       │
│  ④ ReplicaSet Controller (Watch로 감지)                          │
│     "ReplicaSet에 Pod 3개 필요! 현재 0개!"                        │
│     → API Server에 Pod 3개 생성 요청                               │
│         │                                                       │
│         ▼                                                       │
│  ⑤ Scheduler (Watch로 감지)                                     │
│     "nodeName이 비어있는 Pod 3개 발견!"                            │
│     → 각 Pod에 최적의 노드 할당 (Binding)                          │
│     Pod-1 → Worker-1,  Pod-2 → Worker-2,  Pod-3 → Worker-1      │
│         │                                                       │
│         ▼                                                       │
│  ⑥ kubelet (각 Worker 노드에서)                                  │
│     "내 노드에 할당된 새 Pod 발견!"                                 │
│     → Container Runtime(containerd)에 컨테이너 실행 요청           │
│     → 컨테이너 실행 후 상태를 API Server에 보고                     │
│         │                                                       │
│         ▼                                                       │
│  ⑦ 완료!                                                        │
│     kubectl get pods → nginx Pod 3개 Running 상태                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 각 단계에서의 etcd 상태 변화

```
시점          etcd에 저장된 데이터
─────         ──────────────────
②            Deployment: nginx (replicas=3)
③            + ReplicaSet: nginx-abc123 (replicas=3)
④            + Pod: nginx-abc123-x1 (nodeName: "")
             + Pod: nginx-abc123-x2 (nodeName: "")
             + Pod: nginx-abc123-x3 (nodeName: "")
⑤            Pod: nginx-abc123-x1 (nodeName: "worker-1")
             Pod: nginx-abc123-x2 (nodeName: "worker-2")
             Pod: nginx-abc123-x3 (nodeName: "worker-1")
⑥            Pod: nginx-abc123-x1 (status: Running)
             Pod: nginx-abc123-x2 (status: Running)
             Pod: nginx-abc123-x3 (status: Running)
```

---

## 8. 워커 노드 컴포넌트와의 관계

### 워커 노드 컴포넌트 개요

마스터 노드와 함께 동작하는 워커 노드의 핵심 컴포넌트를 이해해야 전체 그림이 완성됩니다.

```
┌─────── Master Node ────────┐          ┌─────── Worker Node ────────┐
│                            │          │                            │
│  API Server ◀──────────────┼──────────┼──▶ kubelet                 │
│      │                     │          │      │                     │
│      │  "Pod를 Worker-1에  │          │      │ "이 Pod를 실행해야   │
│      │   배치하세요"        │          │      │  하는군!"            │
│      │                     │          │      │                     │
│  etcd ◀────────────────────┼──────────┼──────│ 상태 보고            │
│      │                     │          │      ▼                     │
│  Scheduler                 │          │  Container Runtime         │
│      │ "Worker-1이 적합"    │          │  (containerd)              │
│      │                     │          │      │                     │
│  Controller Manager        │          │      ▼                     │
│      │ "replicas 유지"      │          │  ┌─────┐ ┌─────┐          │
│      │                     │          │  │Pod-1│ │Pod-2│          │
│                            │          │  └─────┘ └─────┘          │
│                            │          │                            │
│                            │          │  kube-proxy                │
│                            │          │  (네트워크 규칙 관리)        │
└────────────────────────────┘          └────────────────────────────┘
```

| 워커 노드 컴포넌트 | 역할 | 통신 대상 |
|---------|------|----------|
| **kubelet** | Pod 생명주기 관리, 컨테이너 실행/모니터링 | API Server |
| **kube-proxy** | Service 네트워크 규칙(iptables/IPVS) 관리 | API Server |
| **Container Runtime** | 실제 컨테이너 실행 (containerd, CRI-O) | kubelet |

---

## 9. 고가용성(HA) 구성

### 왜 HA가 필요한가?

```
┌─────────────────────────────────────────────────────────┐
│  마스터 노드가 1개일 때의 위험                              │
│                                                         │
│  Master (단일) ────── ✕ 장애 발생!                        │
│      │                                                  │
│      ├── API Server 중단 → kubectl 사용 불가              │
│      ├── Scheduler 중단 → 새 Pod 배치 불가                │
│      ├── Controller 중단 → 장애 복구 불가                  │
│      └── etcd 데이터 손실 위험                             │
│                                                         │
│  ※ 기존 실행 중인 Pod는 계속 동작하지만,                     │
│    새로운 작업(배포, 스케일링, 복구)이 불가능해집니다.         │
└─────────────────────────────────────────────────────────┘
```

### HA 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│              HA Control Plane 구성 (3 Master)            │
│                                                         │
│                  ┌──────────────┐                        │
│                  │ Load Balancer│                        │
│                  │ (L4/L7 LB)  │                        │
│                  └──────┬───────┘                        │
│            ┌────────────┼────────────┐                   │
│            │            │            │                   │
│            ▼            ▼            ▼                   │
│  ┌──────────────┐┌──────────────┐┌──────────────┐       │
│  │  Master-1    ││  Master-2    ││  Master-3    │       │
│  │              ││              ││              │       │
│  │ API Server   ││ API Server   ││ API Server   │       │
│  │ (Active)     ││ (Active)     ││ (Active)     │       │
│  │              ││              ││              │       │
│  │ Scheduler    ││ Scheduler    ││ Scheduler    │       │
│  │ (Leader)     ││ (Standby)    ││ (Standby)    │       │
│  │              ││              ││              │       │
│  │ Ctrl-Mgr     ││ Ctrl-Mgr     ││ Ctrl-Mgr     │       │
│  │ (Leader)     ││ (Standby)    ││ (Standby)    │       │
│  │              ││              ││              │       │
│  │ etcd         ││ etcd         ││ etcd         │       │
│  │ (Leader)     ││ (Follower)   ││ (Follower)   │       │
│  └──────────────┘└──────────────┘└──────────────┘       │
│                                                         │
│  API Server: 모두 Active (상태 비저장, LB로 분산)          │
│  Scheduler:  Leader 1개만 동작 (Leader Election)          │
│  Ctrl-Mgr:   Leader 1개만 동작 (Leader Election)          │
│  etcd:       Raft 합의로 Leader 선출, 데이터 동기화        │
└─────────────────────────────────────────────────────────┘
```

### Leader Election

```bash
# Scheduler의 Leader Election 확인
kubectl get lease kube-scheduler -n kube-system -o yaml

# Controller Manager의 Leader Election 확인
kubectl get lease kube-controller-manager -n kube-system -o yaml

# 출력 예시:
# holderIdentity: master-1_xxxxx
# leaseDurationSeconds: 15
# renewTime: "2024-01-15T10:30:00Z"
```

---

## 10. 트러블슈팅 가이드

### 컴포넌트별 확인 명령어

```bash
# ─── 전체 컴포넌트 상태 확인 ───
kubectl get componentstatuses            # 또는 kubectl get cs (deprecated)
kubectl get pods -n kube-system          # Control Plane Pod 상태 확인

# ─── API Server ───
kubectl cluster-info                     # API Server 접속 정보
kubectl get --raw /healthz               # API Server 헬스 체크
kubectl get --raw /readyz                # API Server 준비 상태

# ─── etcd ───
# etcd 헬스 체크
ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# etcd 멤버 목록
ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# ─── Scheduler ───
kubectl get events --field-selector reason=FailedScheduling
kubectl describe pod <pending-pod-name>  # 스케줄링 실패 원인 확인

# ─── Controller Manager ───
kubectl get events --sort-by='.lastTimestamp'
kubectl logs kube-controller-manager-<master> -n kube-system
```

### 자주 발생하는 문제와 해결

| 증상 | 원인 | 확인 명령 | 해결 방법 |
|------|------|----------|----------|
| kubectl 명령 타임아웃 | API Server 다운 | `systemctl status kubelet` | API Server Pod/프로세스 확인 |
| Pod가 Pending 상태 유지 | Scheduler 문제 또는 리소스 부족 | `kubectl describe pod <name>` | 노드 리소스 확인, Scheduler 로그 확인 |
| Deployment 변경 미반영 | Controller Manager 문제 | `kubectl get events` | Controller Manager 로그 확인 |
| 클러스터 데이터 불일치 | etcd 장애 | `etcdctl endpoint health` | etcd 로그 확인, 백업에서 복원 |
| 노드 NotReady | kubelet 통신 문제 | `kubectl describe node <name>` | kubelet 상태/로그 확인 |

### Static Pod 매니페스트 위치

Control Plane 컴포넌트는 Static Pod로 실행되므로 매니페스트 파일을 직접 확인할 수 있습니다.

```bash
# Static Pod 매니페스트 위치 (kubeadm 기반)
ls /etc/kubernetes/manifests/
# ├── etcd.yaml
# ├── kube-apiserver.yaml
# ├── kube-controller-manager.yaml
# └── kube-scheduler.yaml

# 각 컴포넌트의 설정 확인
cat /etc/kubernetes/manifests/kube-apiserver.yaml
cat /etc/kubernetes/manifests/kube-scheduler.yaml
cat /etc/kubernetes/manifests/kube-controller-manager.yaml
cat /etc/kubernetes/manifests/etcd.yaml

# kubelet이 이 디렉터리를 감시하여 자동으로 Pod를 생성/업데이트합니다.
# 파일을 수정하면 kubelet이 자동으로 Pod를 재시작합니다.
```

---

## 11. 실습: 컴포넌트 상태 확인

### 실습 1: Control Plane Pod 확인

```bash
# Control Plane 컴포넌트 Pod 목록 확인
kubectl get pods -n kube-system -l tier=control-plane

# 또는 전체 kube-system Pod 확인
kubectl get pods -n kube-system -o wide

# 출력 예시:
# NAME                                READY   STATUS    RESTARTS   NODE
# etcd-master                         1/1     Running   0          master
# kube-apiserver-master               1/1     Running   0          master
# kube-controller-manager-master      1/1     Running   0          master
# kube-scheduler-master               1/1     Running   0          master
# coredns-xxxxx                       1/1     Running   0          master
# kube-proxy-xxxxx                    1/1     Running   0          worker-1
```

### 실습 2: API Server 동작 확인

```bash
# API Server 버전 확인
kubectl version --short

# API 리소스 목록 (어떤 리소스를 관리할 수 있는지)
kubectl api-resources | head -20

# API Server에 직접 요청 (인증 정보 포함)
kubectl get --raw /api/v1/namespaces | python3 -m json.tool | head -20

# API Server 헬스 체크 상세
kubectl get --raw /healthz/etcd
kubectl get --raw /healthz/poststarthook/start-kube-apiserver-admission-initializer
```

### 실습 3: Scheduler 동작 관찰

```bash
# 1. Pod 하나 생성
kubectl run scheduler-test --image=nginx

# 2. Pod의 이벤트에서 Scheduler 동작 확인
kubectl describe pod scheduler-test | grep -A 5 "Events:"
# 출력 예시:
# Events:
#   Type    Reason     Age   From               Message
#   ----    ------     ----  ----               -------
#   Normal  Scheduled  10s   default-scheduler  Successfully assigned default/scheduler-test to worker-1
#   Normal  Pulling    8s    kubelet            Pulling image "nginx"
#   Normal  Pulled     5s    kubelet            Successfully pulled image "nginx"
#   Normal  Created    5s    kubelet            Created container scheduler-test
#   Normal  Started    4s    kubelet            Started container scheduler-test

# 3. 정리
kubectl delete pod scheduler-test
```

### 실습 4: Controller Manager 동작 관찰

```bash
# 1. Deployment 생성 (replicas=3)
kubectl create deployment ctrl-test --image=nginx --replicas=3

# 2. ReplicaSet 확인 (Deployment Controller가 생성)
kubectl get replicaset -l app=ctrl-test

# 3. Pod 하나 삭제하여 Controller 동작 관찰
kubectl get pods -l app=ctrl-test
kubectl delete pod <pod-name-하나>

# 4. 잠시 후 Pod 개수 확인 (자동으로 3개 유지)
kubectl get pods -l app=ctrl-test
# → Pod가 다시 3개! ReplicaSet Controller가 복구함

# 5. 정리
kubectl delete deployment ctrl-test
```

### 실습 5: etcd 데이터 확인 (Master 노드에서 실행)

```bash
# etcd에 저장된 키 목록 확인 (주의: 운영 환경에서는 신중하게)
ETCDCTL_API=3 etcdctl get / --prefix --keys-only --limit=20 \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 출력 예시:
# /registry/configmaps/kube-system/coredns
# /registry/deployments/default/my-app
# /registry/namespaces/default
# /registry/pods/default/nginx-xxx
# /registry/services/default/kubernetes

# etcd 클러스터 상태 확인
ETCDCTL_API=3 etcdctl endpoint status --write-out=table \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

## 12. 정리 및 핵심 요약

### 한눈에 보는 Control Plane

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│                    ┌────────────────────┐                        │
│   사용자/kubectl ──▶│   kube-apiserver   │◀── 모든 통신의 중심     │
│                    └─────────┬──────────┘                        │
│                              │                                  │
│              ┌───────────────┼───────────────┐                   │
│              │               │               │                   │
│              ▼               ▼               ▼                   │
│      ┌──────────┐    ┌─────────────┐  ┌──────────────┐          │
│      │   etcd   │    │  scheduler  │  │  controller  │          │
│      │          │    │             │  │  manager     │          │
│      │ 모든 상태│    │ Pod 배치    │  │ 상태 유지    │          │
│      │ 저장     │    │ 결정       │  │ (컨트롤 루프)│          │
│      └──────────┘    └─────────────┘  └──────────────┘          │
│                                                                 │
│   핵심 원리: "원하는 상태(Desired State)를 선언하면,              │
│              Control Plane이 현재 상태를 그에 맞춘다"             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 포인트 5가지

| # | 포인트 | 설명 |
|---|--------|------|
| 1 | **API Server가 유일한 진입점** | 모든 컴포넌트는 API Server를 통해서만 통신. 직접 etcd 접근 불가 |
| 2 | **etcd는 유일한 저장소** | 클러스터의 모든 상태는 etcd에만 저장. 백업이 최우선 |
| 3 | **Scheduler는 결정만 한다** | 어떤 노드에 배치할지 결정할 뿐, 실제 실행은 kubelet이 담당 |
| 4 | **Controller는 루프로 동작** | 끊임없이 현재 상태를 감시하고 원하는 상태로 맞춤 |
| 5 | **선언적 모델이 핵심** | "어떻게"가 아니라 "무엇을 원하는지" 선언하면 시스템이 알아서 처리 |

### CKA/CKAD 시험 빈출 포인트

| 주제 | 자주 나오는 문제 유형 |
|------|---------------------|
| Static Pod | `/etc/kubernetes/manifests/` 경로에서 매니페스트 수정 |
| etcd 백업/복원 | `etcdctl snapshot save/restore` 명령 |
| Scheduler | nodeSelector, nodeAffinity, Taint/Toleration 설정 |
| Controller | Deployment replicas 변경 후 동작 확인 |
| API Server | 인증서 경로 확인, kubeconfig 문제 해결 |
| HA 구성 | Leader Election 이해, 컴포넌트 역할 구분 |

---

> **다음 단계**: 이 교육 자료를 학습한 후, [`k8s-learn.sh`](k8s-learn.sh) 스크립트를 통해 실제 Kubernetes 오브젝트를 생성하며 실습해 보세요. Control Plane이 어떻게 동작하는지 직접 관찰할 수 있습니다.
