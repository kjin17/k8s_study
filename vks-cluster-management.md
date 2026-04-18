# VKS(vSphere Kubernetes Service) 클러스터 관리 교육

> VCF 환경에서 **VKS 클러스터의 전체 생명주기** — 프로비저닝, 접근/인증, 운영, 업데이트, 오토스케일링, 워크로드 배포, 스토리지, 네트워킹, 보안, 백업/복구, 트러블슈팅까지 — 를 다룹니다.
> VKS는 **vSphere Supervisor 위에서 Cluster API(CAPI)를 활용**하여 Kubernetes 클러스터를 선언적으로 관리하는 서비스입니다.

---

## 목차

1. [VKS 클러스터 개요](#1-vks-클러스터-개요)
2. [인증 및 접근 관리](#2-인증-및-접근-관리)
3. [클러스터 프로비저닝](#3-클러스터-프로비저닝)
4. [ClusterClass와 API 버전](#4-clusterclass와-api-버전)
5. [멀티 OS 노드 풀](#5-멀티-os-노드-풀)
6. [클러스터 운영 및 모니터링](#6-클러스터-운영-및-모니터링)
7. [클러스터 업데이트](#7-클러스터-업데이트)
8. [오토스케일링](#8-오토스케일링)
9. [애드온 및 표준 패키지](#9-애드온-및-표준-패키지)
10. [워크로드 배포](#10-워크로드-배포)
11. [스토리지 관리](#11-스토리지-관리)
12. [네트워킹 관리](#12-네트워킹-관리)
13. [보안 관리](#13-보안-관리)
14. [프라이빗 레지스트리](#14-프라이빗-레지스트리)
15. [백업 및 복구 (Velero)](#15-백업-및-복구-velero)
16. [트러블슈팅](#16-트러블슈팅)
17. [정리 및 요약](#17-정리-및-요약)

---

## 1. VKS 클러스터 개요

### 한 문장 정의

> **VKS(vSphere Kubernetes Service)**는 vSphere Supervisor를 관리 클러스터로 사용하여 **Cluster API(CAPI) 기반으로 Kubernetes 워크로드 클러스터를 선언적으로 프로비저닝하고 관리**하는 서비스입니다.

### VKS 아키텍처 전체 구조

```
┌─────────────────────────────────────────────────────────────────┐
│                     VKS 전체 아키텍처                              │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  vSphere Supervisor (Management Cluster 역할)          │     │
│  │                                                        │     │
│  │  ┌──────────┐ ┌──────────┐ ┌───────────┐              │     │
│  │  │   CAPI   │ │   CAPV   │ │    VKS    │              │     │
│  │  │Controller│ │(vSphere  │ │Controller │              │     │
│  │  │          │ │Provider) │ │ Manager   │              │     │
│  │  └──────────┘ └──────────┘ └───────────┘              │     │
│  │                                                        │     │
│  │  ┌──────────────────────────────────────────────┐     │     │
│  │  │          vSphere Namespace                    │     │     │
│  │  │  ┌───────┐ ┌───────┐ ┌──────────────────┐   │     │     │
│  │  │  │Storage│ │  VM   │ │  Content Library  │   │     │     │
│  │  │  │Policy │ │ Class │ │  (K8s 이미지)      │   │     │     │
│  │  │  └───────┘ └───────┘ └──────────────────┘   │     │     │
│  │  └──────────────────────────────────────────────┘     │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │ 프로비저닝                           │
│              ┌────────────┼────────────┐                        │
│              ▼            ▼            ▼                        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │ VKS Cluster 1│ │ VKS Cluster 2│ │ VKS Cluster 3│            │
│  │              │ │              │ │              │            │
│  │ CP: 3 nodes  │ │ CP: 1 node   │ │ CP: 3 nodes  │            │
│  │ Worker: 5    │ │ Worker: 3    │ │ Worker: 10   │            │
│  │              │ │              │ │              │            │
│  │ [Workloads]  │ │ [Workloads]  │ │ [Workloads]  │            │
│  └──────────────┘ └──────────────┘ └──────────────┘            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### VKS 생명주기 관리 도구

| 도구 | 설명 | 사용 방식 |
|------|------|----------|
| **kubectl** | 선언적 클러스터 관리 | YAML 매니페스트 기반 |
| **VCF CLI (vcf)** | 대화형 클러스터 관리 | 명령어 기반 |
| **VCF Automation** | GUI 기반 관리 | IaaS Services Console |
| **vSphere Client** | 모니터링/관리 | 웹 UI |

---

## 2. 인증 및 접근 관리

### 인증 방식

```
┌─────────────────────────────────────────────────────────────────┐
│                     인증 체계 구조                                 │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  방식 1: vCenter SSO (기본)                           │       │
│  │                                                      │       │
│  │  사용자 → VCF CLI 로그인 → JWT 토큰 발급              │       │
│  │    → Supervisor 접근 → VKS 클러스터 접근               │       │
│  │                                                      │       │
│  │  • AD/LDAP 통합 가능                                  │       │
│  │  • vSphere 인프라 인증과 통합                          │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  방식 2: 외부 Identity Provider (OIDC)                │       │
│  │                                                      │       │
│  │  사용자 → 외부 IdP (예: Okta) → OIDC 토큰             │       │
│  │    → Pinniped 서비스 → VKS 클러스터 접근               │       │
│  │                                                      │       │
│  │  • OpenID Connect 프로토콜 지원                        │       │
│  │  • Pinniped가 K8s 통합 처리                           │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### vSphere Namespace 역할과 권한

| 역할 | Namespace 내 권한 | 클러스터 내 권한 | 비고 |
|------|------------------|----------------|------|
| **Owner** | 클러스터 관리 + Namespace 생성/삭제 | cluster-admin | SSO 사용자만 지원 |
| **Can edit** | 클러스터 CRUD | cluster-admin ClusterRoleBinding 자동 생성 | 가장 일반적 |
| **Can view** | 읽기 전용 | 없음 (별도 RBAC 필요) | 조회 목적 |

### Persona별 vSphere 역할 매핑

| Persona | vSphere Role | SSO Group | 주요 업무 |
|---------|-------------|-----------|----------|
| **VI/Cloud Admin** | Administrator | Administrators | 인프라 관리, Supervisor 구성 |
| **DevOps/Platform Op** | Non-admin/Custom | ServiceProviderUsers | 클러스터 프로비저닝/운영 |
| **Developer** | Read Only/None | None | 워크로드 배포 |

### 접속 절차

```
┌─────────────────────────────────────────────────────────────────┐
│                 VKS 클러스터 접속 흐름                             │
│                                                                 │
│  Step 1: VCF CLI 설치                                           │
│  ──────────────────────                                         │
│  vSphere Client → Supervisor Management → Namespaces           │
│    → "Link to CLI Tools" → vcf-cli 다운로드/설치                 │
│  $ mv vcf-cli-linux_amd64 vcf && chmod +x vcf                  │
│                                                                 │
│  Step 2: Supervisor에 로그인                                     │
│  ──────────────────────                                         │
│  $ vcf context create \                                        │
│      --endpoint 10.92.42.13 \                                  │
│      --username user@domain \                                  │
│      --ca-certificate ~/ca_root.cert                           │
│  → JWT 토큰 생성, .kube/config에 컨텍스트 저장                   │
│                                                                 │
│  Step 3: VKS 클러스터 접근                                       │
│  ──────────────────────                                         │
│  $ vcf context use cluster-1                                   │
│  $ kubectl get nodes                                           │
│  $ kubectl cluster-info                                        │
│                                                                 │
│  [관리자 직접 접근 — kubeconfig Secret 사용]                      │
│  $ kubectl get secret CLUSTER-NAME-kubeconfig -n NAMESPACE     │
│  $ kubectl get secret CLUSTER-NAME-kubeconfig \                │
│      -o jsonpath='{.data.value}' | base64 -d \                 │
│      > CLUSTER-NAME-kubeconfig-admin                           │
│  $ kubectl --kubeconfig=CLUSTER-NAME-kubeconfig-admin get nodes│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 개발자 접근 권한 부여

```yaml
# 개발자 RoleBinding 예시
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: rolebinding-cluster-user-joe
  namespace: default
roleRef:
  kind: ClusterRole
  name: edit                    # 기본 제공 ClusterRole
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: User
  name: sso:joe@example.com    # sso: 접두사 + 사용자명@도메인
  apiGroup: rbac.authorization.k8s.io
```

> 지원 형식: `sso:USER@DOMAIN` (개인), `sso:GROUP@DOMAIN` (그룹)

---

## 3. 클러스터 프로비저닝

### 프로비저닝 전체 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│               VKS 클러스터 프로비저닝 워크플로우                    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ 사전 준비 (VI Admin)                                  │       │
│  │  ✅ Content Library에 K8s 릴리스 이미지 등록            │       │
│  │  ✅ vSphere Namespace 구성                             │       │
│  │  ✅ VM Class, Storage Policy 할당                      │       │
│  └────────────────────────┬─────────────────────────────┘       │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ 리소스 확인 (DevOps)                                   │       │
│  │  $ kubectl get virtualmachineclass                    │       │
│  │  $ kubectl describe namespace NAMESPACE               │       │
│  │  $ kubectl get kubernetesreleases  (또는 kr)          │       │
│  └────────────────────────┬─────────────────────────────┘       │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ 클러스터 생성                                          │       │
│  │                                                      │       │
│  │  [kubectl 방식]                                       │       │
│  │  $ kubectl apply -f cluster-1.yaml                   │       │
│  │                                                      │       │
│  │  [VCF CLI 방식]                                       │       │
│  │  $ vcf cluster create -f cluster-1.yaml              │       │
│  └────────────────────────┬─────────────────────────────┘       │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ 상태 모니터링                                          │       │
│  │  $ kubectl get cluster                               │       │
│  │  $ kubectl describe cluster cluster-1                │       │
│  │  $ vcf cluster get cluster-1                         │       │
│  │  $ vcf cluster list -A                               │       │
│  └────────────────────────┬─────────────────────────────┘       │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────┐       │
│  │ 클러스터 접근 및 검증                                   │       │
│  │  $ vcf context use cluster-1                         │       │
│  │  $ kubectl get nodes                                 │       │
│  │  $ kubectl cluster-info                              │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 클러스터 YAML 예시 (v1beta1 API)

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: cluster-1
  namespace: my-namespace
spec:
  clusterNetwork:
    services:
      cidrBlocks: ["198.51.100.0/12"]
    pods:
      cidrBlocks: ["192.0.2.0/16"]
  topology:
    class: builtin-generic-v3.5.0    # ClusterClass 지정
    version: v1.32.0+vmware.1        # VKr 버전
    controlPlane:
      replicas: 3                     # CP 노드 수 (1 또는 3)
      metadata: {}
    workers:
      machineDeployments:
      - class: node-pool
        name: worker-pool-1
        replicas: 3
        metadata: {}
```

### 클러스터 프로비저닝 테스트

```yaml
# 간단한 테스트 Pod 배포
apiVersion: v1
kind: Pod
metadata:
  name: ping-pod
  namespace: default
spec:
  containers:
  - image: busybox:1.34
    name: busybox
    command: ["ping", "-c"]
    args: ["1", "8.8.8.8"]
  imagePullSecrets:
  - name: regcred
  restartPolicy: Never
```

> VKr v1.26+ 환경에서는 Pod Security Admission(PSA)이 적용됩니다.
> 테스트 시 `kubectl label --overwrite ns default pod-security.kubernetes.io/enforce=privileged` 필요할 수 있습니다.

### 클러스터 삭제

```bash
# kubectl 방식
kubectl delete cluster --namespace NAMESPACE CLUSTER-NAME

# VCF CLI 방식
vcf cluster delete --namespace NAMESPACE CLUSTER-NAME
```

> **주의:** vSphere Client나 vCenter CLI로 삭제하지 마세요! K8s garbage collection이 종속 리소스를 자동 정리합니다.

---

## 4. ClusterClass와 API 버전

### API 버전 변천사

```
┌─────────────────────────────────────────────────────────────────┐
│                   VKS API 버전 변천사                              │
│                                                                 │
│  v1alpha1, v1alpha2 (vCenter 7)                                │
│      │    Deprecated                                           │
│      ▼                                                         │
│  v1alpha3 — TanzuKubernetesCluster (vCenter 8)                 │
│      │    VKS 3.2부터 Deprecated                                │
│      ▼                                                         │
│  v1beta1 — Cluster API (vCenter 8+)                            │
│      │    권장 API                                              │
│      ▼                                                         │
│  v1beta2 — Cluster API (vCenter 8 U3+ / vCenter 9+)           │
│           최신 API                                              │
│                                                                 │
│  ※ VKS 3.4부터 TanzuKubernetesCluster 프로비저닝 불가            │
│  ※ 신규 클러스터는 v1beta1 또는 v1beta2 사용 권장                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Versioned ClusterClass 매트릭스

VKS 3.2.0부터 **Versioned ClusterClass**가 도입되어, VKS 업그레이드 후에도 클러스터가 자동으로 롤링 업데이트되지 않습니다.

| ClusterClass | VKS 3.2 | VKS 3.3 | VKS 3.4 | VKS 3.5 | VKS 3.6 |
|---|:---:|:---:|:---:|:---:|:---:|
| tanzukubernetescluster | O | O | Deprecated | Removed | Removed |
| builtin-generic-v3.1.0 | O | O | O | O | Deprecated |
| builtin-generic-v3.2.0 | O | O | O | O | Deprecated |
| builtin-generic-v3.3.0 | - | O | O | O | Deprecated |
| builtin-generic-v3.4.0 | - | - | O | O | O |
| builtin-generic-v3.5.0 | - | - | - | O | O |
| builtin-generic-v3.6.0 | - | - | - | - | O |

### ClusterClass 위치

```
┌─────────────────────────────────────────────────────────────────┐
│              ClusterClass 네임스페이스 변경                        │
│                                                                 │
│  VKS 3.3 이하:                                                  │
│  ┌──────────────────────────────────────────────┐               │
│  │  각 vSphere Namespace에 ClusterClass 존재     │               │
│  │  (Namespace-scoped)                          │               │
│  └──────────────────────────────────────────────┘               │
│                                                                 │
│  VKS 3.4 이상:                                                  │
│  ┌──────────────────────────────────────────────┐               │
│  │  중앙 네임스페이스에 ClusterClass 존재          │               │
│  │  vmware-system-vks-public                    │               │
│  │  (모든 Namespace에서 참조 가능)                │               │
│  └──────────────────────────────────────────────┘               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### VKr(Kubernetes Release)과 ClusterClass 호환성

| K8s 버전 (VKr) | builtin-generic-v3.5.0 | builtin-generic-v3.6.0 |
|---|:---:|:---:|
| 1.30 | O | - |
| 1.31 | O | O |
| 1.32 | O | O |
| 1.33 | O | O |
| 1.34 | - | O |
| 1.35 | - | - |

---

## 5. 멀티 OS 노드 풀

### 지원 OS별 비교

```
┌─────────────────────────────────────────────────────────────────┐
│                     멀티 OS 노드 풀 지원                          │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Photon OS (기본)                                     │       │
│  │  • VKS 기본 OS                                        │       │
│  │  • Control Plane + Worker 모두 지원                    │       │
│  │  • Antrea, Calico CNI 지원                            │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Ubuntu                                               │       │
│  │  • Worker 노드 지원                                    │       │
│  │  • Antrea, Calico CNI 지원                            │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Windows Server 2022 (VKr 1.31+)                      │       │
│  │  • Worker 노드만 지원                                  │       │
│  │  • Antrea CNI만 지원 (Calico 불가!)                    │       │
│  │  • Cluster API 필수 (v1beta1/v1beta2)                 │       │
│  │  • builtin-generic-v3.2.0+ ClusterClass 필요          │       │
│  │  • gMSA(Group Managed Service Account) 지원           │       │
│  │  • Content Library에 Windows 라이선스 이미지 필요       │       │
│  │  • 볼륨 경로: c:\var\lib\kubelet, c:\programdata\...  │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  RHEL (VKr 1.35+ / VKS 3.6+)                         │       │
│  │  • Control Plane + Worker 모두 지원                    │       │
│  │  • builtin-generic-v3.6.0+ ClusterClass 필요          │       │
│  │  • Content Library에 커스텀 RHEL VKr 이미지 필요       │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### vSphere Zone 기반 워크로드 격리

```
┌─────────────────────────────────────────────────────────────────┐
│            vSphere Zone 기반 노드 분산                            │
│                                                                 │
│  VCF 9 / VKS 3.3+:                                             │
│  • Worker 노드를 vSphere Zone에 분산 배치 가능                    │
│  • Control Plane 노드는 자동으로 Zone에 분산                      │
│                                                                 │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │
│  │   Zone 1    │ │   Zone 2    │ │   Zone 3    │               │
│  │             │ │             │ │             │               │
│  │  [CP #1]    │ │  [CP #2]    │ │  [CP #3]    │  ← 자동 분산  │
│  │  [Worker]   │ │  [Worker]   │ │  [Worker]   │               │
│  │  [Worker]   │ │  [Worker]   │ │             │  ← 명시/자동  │
│  └─────────────┘ └─────────────┘ └─────────────┘               │
│                                                                 │
│  Worker 배치 옵션:                                               │
│  • Explicit: MachineDeployment에 failureDomain 지정             │
│  • Automatic: failureDomain 생략 (VCF 9.1 / VKS 3.6+)          │
│  ⚠️ Explicit + Automatic 혼합 사용 불가!                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. 클러스터 운영 및 모니터링

### 클러스터 생명주기 단계

```
┌─────────────────────────────────────────────────────────────────┐
│                  VKS 클러스터 Lifecycle Phase                     │
│                                                                 │
│  Creating ──▶ Running ──▶ Updating ──▶ Running                 │
│     │            │                        │                     │
│     ▼            ▼                        ▼                     │
│   Failed      Deleting                 Failed                  │
│                                                                 │
│  5가지 상태: Creating, Running, Updating, Deleting, Failed      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 스케일링

```
┌─────────────────────────────────────────────────────────────────┐
│                      수동 스케일링                                │
│                                                                 │
│  수평 스케일링 (Horizontal):                                     │
│  • Worker 노드 추가/제거                                         │
│  • Control Plane: 1 또는 3만 가능 (스케일링 미지원)               │
│                                                                 │
│  수직 스케일링 (Vertical):                                       │
│  • VM Class 변경 → 롤링 업데이트 발생                             │
│  • Worker 노드 볼륨 크기 변경 가능                                │
│                                                                 │
│  $ kubectl edit cluster CLUSTER-NAME                            │
│  # spec.topology.workers.machineDeployments[0].replicas 수정    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 클러스터 상태 확인 (v1beta1/v1beta2)

| Condition | 설명 |
|-----------|------|
| **Ready** | 클러스터 전체 준비 상태 |
| **ControlPlaneReady** | Control Plane 노드 준비 |
| **InfrastructureReady** | vSphere 인프라 준비 |
| **TopologyReconciled** | 토폴로지 적용 완료 |
| **NetworkProviderReconciled** | 네트워크 프로바이더 구성 완료 |
| **CloudProviderReconciled** | 클라우드 프로바이더 구성 완료 |
| **DNSReconciled** | DNS 구성 완료 |
| **Available** (v1beta2) | 워크로드 수용 가능 상태 |

### Machine 상태 확인

```bash
# 머신 상태 확인
kubectl describe machine MACHINE-NAME

# 주요 Condition:
# - ResourcePolicyReady     : 리소스 정책 준비
# - ClusterNetworkReady     : 클러스터 네트워크 준비
# - LoadBalancerReady       : 로드 밸런서 준비
# - VMProvisioned           : VM 프로비저닝 완료
# - WaitingForBootstrapData : 부트스트랩 데이터 대기
# - PoweringOn              : 전원 켜는 중
# - WaitingForNetworkAddress: 네트워크 주소 대기
```

### MachineHealthCheck 구성

```
┌─────────────────────────────────────────────────────────────────┐
│              MachineHealthCheck 동작 방식                         │
│                                                                 │
│  MachineHealthCheck가 노드 상태를 주기적으로 확인:                  │
│                                                                 │
│  v1beta1:                                                      │
│  • maxUnhealthy: 최대 비정상 노드 수                              │
│  • nodeStartupTimeout: 노드 시작 제한 시간                       │
│  • unhealthyConditions:                                        │
│    - Ready (False/Unknown)                                     │
│    - MemoryPressure (True)                                     │
│    - DiskPressure (True)                                       │
│    - PIDPressure (True)                                        │
│    - NetworkUnavailable (True)                                 │
│                                                                 │
│  v1beta2 (v3.5.0+):                                            │
│  • remediation.triggerIf: 복구 트리거 조건                       │
│  • nodeStartupTimeoutSeconds: 초 단위 타임아웃                   │
│  • unhealthyNodeConditions: 비정상 조건 목록                     │
│                                                                 │
│  비정상 감지 → 자동 복구 (노드 교체)                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### VKS 클러스터 핵심 Secret

| Secret | 용도 |
|--------|------|
| **CCM Token** | Cloud Controller Manager 인증 토큰 |
| **PVCSI Token** | Paravirtual CSI 드라이버 인증 토큰 |
| **Kubeconfig** | 클러스터 관리자 접근용 kubeconfig |
| **SSH Private Key** | 노드 SSH 접근용 개인키 |
| **SSH Password** | 노드 SSH 비밀번호 |
| **CA Certificate** | 클러스터 CA 인증서 |

```bash
# Secret 조회
kubectl get secrets -n NAMESPACE | grep CLUSTER-NAME
```

---

## 7. 클러스터 업데이트

### 롤링 업데이트 모델

```
┌─────────────────────────────────────────────────────────────────┐
│               VKS 롤링 업데이트 순서                               │
│                                                                 │
│  업데이트 트리거:                                                 │
│  • VKr 버전 변경                                                 │
│  • VM Class 변경                                                │
│  • Storage Class 변경                                           │
│  • ClusterClass 변경                                            │
│                                                                 │
│  실행 순서:                                                      │
│  ┌──────────┐     ┌───────────────┐     ┌──────────────┐       │
│  │ Add-ons  │────▶│ Control Plane │────▶│ Worker Nodes │       │
│  │ 업데이트  │     │ 업데이트       │     │ 업데이트      │       │
│  └──────────┘     └───────────────┘     └──────────────┘       │
│                                                                 │
│  노드 교체 방식:                                                  │
│  ① 새 노드 VM 생성                                              │
│  ② 새 노드 온라인 대기                                           │
│  ③ 기존 노드 drain                                              │
│  ④ 기존 노드 삭제                                                │
│  → 서비스 중단 최소화!                                            │
│                                                                 │
│  ※ VKS 3.0부터 VKS Controller는                                 │
│    vCenter/Supervisor와 독립적으로 동작                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 업데이트 방법별 비교

| 방법 | 명령어 | 비고 |
|------|--------|------|
| **VKr 버전 변경** | `kubectl edit cluster CLUSTER-NAME` | version 필드 수정 |
| **VM Class 변경** | `kubectl edit cluster CLUSTER-NAME` | 대상 VM Class가 Namespace에 할당되어 있어야 함 |
| **Storage Class 변경** | `kubectl edit cluster CLUSTER-NAME` | storageClass 파라미터 수정 |
| **ClusterClass 변경** | `kubectl edit cluster CLUSTER-NAME` | class/classRef.name 수정 → 노드 롤아웃 트리거 |
| **VCF CLI** | `vcf cluster upgrade CLUSTER --kr VKR` | 대화형 업그레이드 |

```bash
# VCF CLI로 업그레이드 가능 버전 확인 및 실행
vcf context use sv-context
vcf cluster available-upgrades get cluster-1 -n my-ns
vcf cluster upgrade cluster-1 -n my-ns --kr v1.33.0+vmware.1
```

> **주의:** 이미 배포된 클러스터에는 `kubectl apply`를 사용할 수 없습니다. `kubectl edit`을 사용하세요!

### TanzuKubernetesCluster → Cluster API 마이그레이션

```
┌─────────────────────────────────────────────────────────────────┐
│        TKC → Cluster API 마이그레이션 (Retire)                   │
│                                                                 │
│  VKS 3.3+에서 사용 가능                                          │
│                                                                 │
│  $ kubectl label tkc CLUSTER-NAME \                            │
│      kubernetes.vmware.com/retire-tkc=""                       │
│                                                                 │
│  사전 검증:                                                      │
│  ✅ Cluster 리소스 존재 및 Ready 상태                             │
│  ✅ Non-legacy VKr 사용 중                                       │
│  ✅ 진행 중인 업그레이드 없음                                     │
│  ✅ TMC 관리 대상이 아님                                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. 오토스케일링

### 오토스케일링 개요

```
┌─────────────────────────────────────────────────────────────────┐
│                  Cluster Autoscaler 동작 원리                    │
│                                                                 │
│                    [Pending Pod 감지]                            │
│                          │                                      │
│                          ▼                                      │
│                  리소스 부족 판단?                                 │
│                   Yes ↙      ↘ No                               │
│                      ▼         (대기)                            │
│              ┌───────────────┐                                  │
│              │  Scale Out    │                                  │
│              │ Worker 노드   │                                  │
│              │ 자동 추가      │                                  │
│              └───────┬───────┘                                  │
│                      │                                          │
│                      ▼                                          │
│              [노드 활용률 모니터링]                                │
│                      │                                          │
│              활용률 낮음 감지?                                    │
│               Yes ↙      ↘ No                                   │
│                  ▼         (대기)                                │
│          ┌───────────────┐                                      │
│          │  Scale In     │                                      │
│          │ Worker 노드   │                                      │
│          │ 자동 제거      │                                      │
│          └───────────────┘                                      │
│                                                                 │
│  요구사항:                                                       │
│  • vSphere 8 U3+                                               │
│  • VKr 1.27.x+                                                 │
│  • VKr 버전과 1:1 매핑되는 Autoscaler 패키지                     │
│                                                                 │
│  Scale to/from Zero:                                           │
│  • VKS 3.2 이하: 불가                                           │
│  • VKS 3.3+ (VKr 1.31.4+): 가능                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 오토스케일러 설치 방법

| 방법 | VKS 버전 | 설명 |
|------|---------|------|
| **Add-on Management** | VKS 3.5+ | 자동 레이블 → 자동 설치. MachineDeployment 어노테이션으로 min/max 설정 |
| **kubectl** | 모든 버전 | 패키지 매니저 설치 → 패키지 리포지토리 → 오토스케일러 배포 |
| **VCF CLI** | 모든 버전 | 클러스터 생성 → 리포지토리 설정 → 패키지 설치 → 검증 |

### 오토스케일된 클러스터 업그레이드 절차

```
┌─────────────────────────────────────────────────────────────────┐
│          오토스케일 클러스터 업그레이드 절차                        │
│                                                                 │
│  ① Autoscaler 일시 중지 (paused: true)                         │
│       ▼                                                         │
│  ② 클러스터 업그레이드 (VKr 버전 변경)                            │
│       ▼                                                         │
│  ③ Autoscaler 패키지 버전 업데이트                               │
│       ▼                                                         │
│  ④ Autoscaler 재개 (paused: false)                             │
│                                                                 │
│  ※ Add-on Management (VKS 3.5+):                               │
│    VKS가 자동으로 autoscaler 버전을 VKr에 맞춰 업데이트            │
│    호환 버전 없으면 업그레이드 사전 검증에서 차단됨                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 오토스케일러 삭제

```bash
# Add-on Management 방식 (레이블로 비관리 전환)
kubectl label cluster CLUSTER-NAME \
    addon.addons.kubernetes.vmware.com/cluster-autoscaler=unmanaged

# kubectl 방식
kubectl delete -f autoscaler.yaml

# VCF CLI 방식
vcf package installed delete -n tkg-system cluster-autoscaler-pkgi
```

---

## 9. 애드온 및 표준 패키지

### 애드온 관리 프레임워크 (VKS 3.5+)

```
┌─────────────────────────────────────────────────────────────────┐
│               VKS 애드온 관리 아키텍처                             │
│                                                                 │
│  vmware-system-vks-public 네임스페이스                            │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Addon                  : 사용 가능한 애드온 목록      │       │
│  │  AddonRepository        : 패키지 리포지토리 정의       │       │
│  │  AddonRepositoryInstall : 리포지토리 → 클러스터 바인딩 │       │
│  │  AddonRelease           : 버전별 메타데이터 (불변)     │       │
│  │  AddonConfigDefinition  : 구성 템플릿/스키마           │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  클러스터 네임스페이스                                            │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  AddonInstall    : 원하는 애드온 상태 (설치 요청)      │       │
│  │  ClusterAddon    : 설치 상태 (실제 상태)              │       │
│  │  AddonConfig     : 검증된 구성 값                     │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  장점:                                                          │
│  ✅ 패키지 리포지토리 자동 설치/업그레이드                         │
│  ✅ 모든 표준 패키지를 단일 방법으로 관리                           │
│  ✅ 선언적 API로 Fleet 전체 애드온 관리                            │
│  ✅ 업그레이드 전 호환성 사전 검증                                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 사용 가능한 애드온 목록

```bash
$ kubectl get addons -n vmware-system-vks-public
```

| 애드온 | 용도 |
|--------|------|
| **cert-manager** | TLS 인증서 자동 발급/갱신 |
| **cluster-autoscaler** | 워커 노드 자동 스케일링 |
| **contour** | Ingress Controller |
| **external-dns** | 외부 DNS 자동 관리 |
| **fluent-bit** | 로그 수집/전달 |
| **harbor** | 컨테이너 이미지 레지스트리 |
| **istio** | 서비스 메시 |
| **prometheus** | 모니터링/메트릭 수집 |
| **telegraf** | 메트릭 수집 에이전트 |
| **velero** | 백업/복구 |
| **ako** | Avi Kubernetes Operator |
| **sriov-network-device-plugin** | SR-IOV 네트워크 디바이스 |
| **windows-gmsa-webhook** | Windows gMSA 지원 |
| **helm-controller** | Helm 차트 관리 |
| **vsphere-pv-csi-webhook** | PV CSI 검증 웹훅 |

### 14개 표준 패키지 (Carvel 포맷)

> VMware by Broadcom이 제공하는 오픈 소스 애플리케이션 번들입니다. VKS 3.5+에서는 애드온 관리 프레임워크를 통해 설치/관리합니다.

---

## 10. 워크로드 배포

### 기본 워크로드 배포 패턴

```
┌─────────────────────────────────────────────────────────────────┐
│                   워크로드 배포 패턴                               │
│                                                                 │
│  1. Pod + LoadBalancer Service                                 │
│  ┌───────────────────────────────────────────┐                  │
│  │  [Pod: nginx]                             │                  │
│  │       ↑                                   │                  │
│  │  [Service: LoadBalancer] ← External IP    │                  │
│  └───────────────────────────────────────────┘                  │
│                                                                 │
│  2. Ingress (Contour)                                          │
│  ┌───────────────────────────────────────────┐                  │
│  │  [Contour Ingress Controller]             │                  │
│  │       ↓                                   │                  │
│  │  [Ingress Rule]                           │                  │
│  │    /api → [Service A]                     │                  │
│  │    /web → [Service B]                     │                  │
│  └───────────────────────────────────────────┘                  │
│                                                                 │
│  3. StatefulSet + PVC (Persistent Storage)                     │
│  ┌───────────────────────────────────────────┐                  │
│  │  [StatefulSet: redis]                     │                  │
│  │       ↑                                   │                  │
│  │  [PVC] → [PV] → [vSphere Datastore]       │                  │
│  └───────────────────────────────────────────┘                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### LoadBalancer 서비스 예시

```yaml
# Static IP LoadBalancer
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: LoadBalancer
  loadBalancerIP: 10.0.0.100    # 고정 IP 지정 (선택)
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

> **보안 경고:** `services/status`에 대한 patch 권한을 제한하여 무단 IP 변경을 방지하세요.

### VKS 정의 Priority Class

| PriorityClass | 값 | Preemption | 용도 |
|---|---|---|---|
| **vmware-system-important** | 1,000,000,000 | 기본 | VKS 시스템 핵심 워크로드 |
| **vmware-system-observability** | 1,000,000 | Never | 모니터링 등 관찰 가능성 워크로드 |

> VKS 3.5+ / builtin-generic-v3.5.0에서 도입. **VKS 시스템 Pod 전용**입니다.

### 스토리지 클래스와 Persistent Volume

```
┌─────────────────────────────────────────────────────────────────┐
│           Storage Class 바인딩 모드                               │
│                                                                 │
│  vSphere 스토리지 정책 1개 → StorageClass 2개 자동 생성           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  goldsp (Immediate Binding Mode)                     │       │
│  │  • PVC 생성 즉시 PV 프로비저닝                         │       │
│  │  • 일반적인 사용 방식                                  │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  goldsp-latebinding (WaitForFirstConsumer)           │       │
│  │  • Pod가 스케줄링될 때 PV 프로비저닝                    │       │
│  │  • Multi-Zone 환경에서 권장                            │       │
│  │  • StatefulSet across Zones에 필수                    │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  VCF 9.0+: 4Kn 스토리지 포맷 지원 (Pod 볼륨 전용)               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. 스토리지 관리

### 스토리지 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│               VKS 스토리지 아키텍처                                │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  VKS Cluster                                          │     │
│  │                                                        │     │
│  │  ┌──────────────────┐                                  │     │
│  │  │  pvCSI Driver    │ ← Paravirtual CSI               │     │
│  │  │                  │   (수정된 vSphere CNS-CSI)        │     │
│  │  │  • 서비스 계정    │   서비스 계정 자격증명으로 동작     │     │
│  │  │    자격증명 사용  │   (인프라 자격증명 불필요!)        │     │
│  │  └────────┬─────────┘                                  │     │
│  │           │                                            │     │
│  │           ▼                                            │     │
│  │  ┌──────────────────┐                                  │     │
│  │  │  StorageClass    │ ← vSphere 스토리지 정책에서       │     │
│  │  │  (자동 생성)      │   자동 매핑                      │     │
│  │  └────────┬─────────┘                                  │     │
│  │           │                                            │     │
│  │           ▼                                            │     │
│  │  ┌──────────────────┐     ┌────────────────────┐      │     │
│  │  │  PVC             │────▶│  PV                 │      │     │
│  │  │  (Persistent     │     │  (Persistent Volume)│      │     │
│  │  │   Volume Claim)  │     │                     │      │     │
│  │  └──────────────────┘     └────────┬───────────┘      │     │
│  └────────────────────────────────────│────────────────────┘     │
│                                       │                         │
│                                       ▼                         │
│                            ┌────────────────────┐               │
│                            │  vSphere Datastore  │               │
│                            │  (VMFS/NFS/vSAN)    │               │
│                            └────────────────────┘               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 노드 볼륨 마운트 지원

| 볼륨 마운트 | 노드 유형 | 지원 여부 |
|------------|----------|----------|
| `/var/lib/containerd` | Worker | **지원** |
| `/var/lib/kubelet` | Worker | **지원** |
| `/var/lib/etcd` | Control Plane | ClusterClass v3.5+ 에서만 |
| `/` (root), `/var`, `/var/lib`, `/etc` | 모든 노드 | **미지원** |

### Dynamic vs Static PV 비교

```
┌─────────────────────────────────────────────────────────────────┐
│          Dynamic PV vs Static PV                                │
│                                                                 │
│  Dynamic PV (동적 프로비저닝):                                    │
│  ┌──────────────────────────────────────────────┐               │
│  │  1. PVC 생성 (StorageClass 참조)               │               │
│  │  2. pvCSI가 자동으로 PV + 가상 디스크 생성       │               │
│  │  3. PVC 상태: Bound                            │               │
│  │  → 가장 일반적인 방식                            │               │
│  └──────────────────────────────────────────────┘               │
│                                                                 │
│  Static PV (정적 프로비저닝):                                     │
│  ┌──────────────────────────────────────────────┐               │
│  │  1. Supervisor에 기존 PVC가 존재해야 함          │               │
│  │  2. PV 정의에 StorageClass + volumeHandle 지정  │               │
│  │  3. volumeHandle = Supervisor PVC 참조         │               │
│  │  ⚠️ 참조 PVC가 Pod에 연결되어 있으면 안 됨!      │               │
│  │  ⚠️ 다른 클러스터에서 재사용 시 기존 PVC/PV 삭제  │               │
│  └──────────────────────────────────────────────┘               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 볼륨 확장

- `allowVolumeExpansion`: 기본값 `true` (자동 활성화)
- 온라인/오프라인 확장 모두 지원
- **블록 볼륨만** 확장 가능
- StatefulSet 볼륨, 스냅샷이 있는 볼륨은 확장 불가

### 스냅샷

```
┌─────────────────────────────────────────────────────────────────┐
│                    CSI 스냅샷                                    │
│                                                                 │
│  요구사항:                                                       │
│  • vSphere 8.0 U2+, VKr v1.26.5+                              │
│  • cert-manager, vsphere-pv-csi-webhook,                       │
│    external-csi-snapshot-webhook 설치 필요                       │
│                                                                 │
│  제약사항:                                                       │
│  • 블록 볼륨만 지원 (파일 볼륨 불가)                               │
│  • 스냅샷에서 생성한 PVC는 같은 데이터스토어에 위치해야 함           │
│  • 스냅샷이 있는 볼륨은 삭제/확장 불가                             │
│  • 권장: 디스크당 2-3개 스냅샷                                    │
│  • vSAN ESA 최대: 볼륨당 32개                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 12. 네트워킹 관리

### CNI 옵션

```
┌─────────────────────────────────────────────────────────────────┐
│                     CNI 선택지                                   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Antrea (기본 CNI)                                    │       │
│  │  • VKS 기본값                                         │       │
│  │  • NSX Antrea Adapter 통합 가능                       │       │
│  │  • Windows 노드 풀 지원                               │       │
│  │  • EgressSeparateSubnet 지원 (VPC 환경)               │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Calico                                               │       │
│  │  • 대체 CNI 옵션                                      │       │
│  │  • Windows 노드 미지원!                                │       │
│  │  • VKr 1.35+: AddonConfig로 구성                      │       │
│  │  • VKr 1.34-: CalicoConfig/ClusterBootstrap 사용      │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  VKS Networking Addon (VKS 3.6+ / VKr 1.35+)         │       │
│  │  • Supervisor Service 기반 CNI                        │       │
│  │  • AddonConfig + bootstrapAddons 클러스터 변수로 구성   │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  기본 CNI 변경:                                                  │
│  Supervisor Management → Configure → Default CNI               │
│  ⚠️ 전역 설정 → 모든 새 클러스터에 적용 (기존 클러스터 변경 없음)   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Antrea-NSX Adapter

```
┌─────────────────────────────────────────────────────────────────┐
│               Antrea-NSX Adapter 구성                            │
│                                                                 │
│  요구사항:                                                       │
│  • vSphere 8 U3+, NSX 4.1+, VKS 3.0+, VKr v1.28.x+           │
│  • 클러스터당 1:1 관계                                           │
│                                                                 │
│  활성화:                                                         │
│  AntreaConfig 리소스 생성 → antreaNSX.enable: true              │
│                                                                 │
│  효과:                                                           │
│  • NSX에서 VKS 클러스터 네트워크 정책 통합 관리                    │
│  • NSX UI에서 K8s NetworkPolicy 시각화                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### NSX 네트워킹 오브젝트 (클러스터당)

| 오브젝트 | 용도 |
|---------|------|
| **Tier-1 Router** | 클러스터 전용 라우터 (Segment 포함) |
| **Load Balancer** | CP 포트 8443, 3개 CP 노드 서버 풀 |
| **Virtual Servers** | HTTP/HTTPS Ingress용 |
| **SNAT Rules** | 외부 통신용 NAT |
| **DFW Rules** | kube-dns 관련 분산 방화벽 규칙 |

---

## 13. 보안 관리

### VKS 기본 보안 특성

```
┌─────────────────────────────────────────────────────────────────┐
│                VKS 기본 보안 (Secure by Default)                 │
│                                                                 │
│  ✅ etcd 암호화: 클러스터별 고유 키로 모든 Secret 암호화           │
│  ✅ 자격증명 격리: VKS 클러스터에 인프라 자격증명 없음             │
│  ✅ 토큰 범위 제한: 크로스 클러스터 접근 차단                      │
│  ✅ PSA 기본 활성화: VKr v1.25+                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Pod Security Admission (PSA)

```
┌─────────────────────────────────────────────────────────────────┐
│                Pod Security Admission 구성                      │
│                                                                 │
│  3가지 모드:                                                     │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Enforce : 정책 위반 Pod 차단                         │       │
│  │  Audit   : 정책 위반 기록 (허용은 함)                  │       │
│  │  Warn    : 정책 위반 경고 메시지 표시                  │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  3가지 레벨:                                                     │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  Privileged  : 제한 없음 (위험)                       │       │
│  │  Baseline    : 기본 보안 정책                         │       │
│  │  Restricted  : 최대 보안 정책 (가장 엄격)              │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  VKr별 기본값:                                                   │
│  • VKr v1.25: warn + audit → restricted                       │
│  • VKr v1.26+: enforce → restricted (기본으로 차단!)            │
│                                                                 │
│  Namespace별 PSA 조정:                                          │
│  $ kubectl label ns NAMESPACE \                                │
│      pod-security.kubernetes.io/enforce=baseline               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### PSP (VKr 1.24 이하)

| PSP | 특성 |
|-----|------|
| **vmware-system-privileged** | 허용적 — 모든 Pod 허용 |
| **vmware-system-restricted** | 제한적 — 보안 강화 |

> 기본 RoleBinding/ClusterRoleBinding이 없으므로 관리자가 직접 생성해야 합니다.

### TLS 인증서 관리

```
┌─────────────────────────────────────────────────────────────────┐
│              TLS 인증서 관리 체계                                  │
│                                                                 │
│  두 가지 Trust Domain:                                          │
│                                                                 │
│  ┌──────────────────────┐    ┌──────────────────────┐           │
│  │  vCenter (VMCA)      │    │  Kubernetes CA       │           │
│  │  • Supervisor 인증서  │    │  • 클러스터 내부 인증서│           │
│  │  • vSphere 8 U3+     │    │  • 롤링 업데이트 시   │           │
│  │    자동 로테이션      │    │    자동 로테이션      │           │
│  └──────────────────────┘    └──────────────────────┘           │
│                                                                 │
│  수동 인증서 로테이션:                                            │
│  KubeadmControlPlane에 rolloutAfter 타임스탬프 패치              │
│                                                                 │
│  NSX 인증서 로테이션:                                             │
│  • NSX LB 인증서: vSphere Client 또는 NSX API                   │
│  • NSX Manager 인증서: OpenSSL + NSX API                        │
│  • 멀티 노드 NSX: 각 노드 개별 로테이션 필요                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 14. 프라이빗 레지스트리

### 프라이빗 레지스트리 통합

```
┌─────────────────────────────────────────────────────────────────┐
│            프라이빗 레지스트리 구성 흐름                            │
│                                                                 │
│  Step 1: Self-signed CA 인증서 구성                              │
│  ───────────────────────────                                    │
│  클러스터 spec → trust.additionalTrustedCAs에 인증서 추가         │
│  ⚠️ v1beta1 API: 이중 Base64 인코딩 필요!                       │
│  ⚠️ v1alpha3 API: 단일 Base64 인코딩                             │
│                                                                 │
│  Step 2: 레지스트리 인증 Secret 생성                              │
│  ───────────────────────────                                    │
│  $ kubectl create secret generic regcred \                     │
│      --from-file=.dockerconfigjson=~/.docker/config.json \     │
│      --type=kubernetes.io/dockerconfigjson                     │
│                                                                 │
│  Step 3: Pod에서 레지스트리 사용                                  │
│  ───────────────────────────                                    │
│  spec:                                                         │
│    containers:                                                 │
│    - image: harbor.example.com/myproject/myapp:v1              │
│    imagePullSecrets:                                           │
│    - name: regcred                                             │
│                                                                 │
│  ※ 인증서 로테이션 시 새 Secret을 생성해야 함                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 15. 백업 및 복구 (Velero)

### 백업 방법 비교

```
┌─────────────────────────────────────────────────────────────────┐
│                  Velero 백업 방법 3가지                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  1. CSI Snapshot (권장)                                │       │
│  │     • CNS 블록 볼륨 대상                               │       │
│  │     • Crash-consistent                                │       │
│  │     • 증분 백업 지원                                    │       │
│  │     • 가장 빠르고 효율적                                │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  2. File System Backup                                │       │
│  │     • Non-CNS 볼륨 대상                                │       │
│  │     • 라이브 파일시스템 읽기                             │       │
│  │     • Kopia 사용 (Velero 1.12+)                       │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  3. vSphere Plugin Snapshot                           │       │
│  │     • 네이티브 vSphere 스냅샷 활용                     │       │
│  │     • 전체 백업만 지원 (증분 불가)                       │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
│  ⚠️ CSI와 vSphere Plugin Snapshot 동시 활성화 불가!             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Velero 버전 호환성

| Velero 버전 | 지원 K8s 버전 |
|---|---|
| v1.17.2 | 1.31 ~ 1.34 |
| v1.16.2 | 1.31 ~ 1.33 |
| v1.15.2 | 1.28 ~ 1.32 |

### Velero 설치 방법

| 방법 | 권장 대상 | 비고 |
|------|---------|------|
| **Standard Package** | Velero 1.16+ | 권장 방식 |
| **Velero CLI** | Velero 1.15 이하 | 기존 방식 |
| **vSphere Operator** | - | Deprecated |

---

## 16. 트러블슈팅

### 로그 수집

```
┌─────────────────────────────────────────────────────────────────┐
│                    로그 수집 방법                                  │
│                                                                 │
│  1. Supervisor Support Bundle                                  │
│     vSphere Client에서 내보내기                                  │
│                                                                 │
│  2. VKS Cluster Support Bundle (VKS 3.5+)                      │
│     $ vcf cluster support-bundler create CLUSTER-NAME          │
│     수집 내용: Linux/Windows 노드 데이터,                         │
│     클러스터 덤프, PVC, Endpoints, ConfigMaps, CronJobs          │
│                                                                 │
│  3. WCP 로그 파일                                                │
│     $ tail -f /var/log/vmware/wcp/wcpsvc.log                   │
│                                                                 │
│  4. 컴포넌트별 로그                                               │
│     • CAPI Controller                                          │
│     • CAPV (vSphere Provider)                                  │
│     • VM Operator                                              │
│     • VKS Controller Manager                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 주요 트러블슈팅 시나리오

| 증상 | 원인 | 해결 |
|------|------|------|
| **접속 불가 / 권한 에러** | vSphere Namespace 권한 부족 | Edit 권한 요청 |
| **VKr 리소스 없음** | Content Library 동기화 실패 | Content Library Service 재시작 |
| **VM Class 바인딩 에러** | Namespace에 VM Class 미할당 | vSphere Namespace에 VM Class 추가 |
| **프로비저닝 실패** | CP 수 오류 (1 또는 3만 가능) | replicas를 1 또는 3으로 수정 |
| **노드 에러 (CPU 부족)** | VM Class 크기 부족 | extra-small/small 대신 더 큰 VM Class 사용 |
| **네트워크 에러** | TEP 인터페이스/MTU 문제 | Tier-1 Router, SNAT IP, LB, MTU 확인 |
| **컨테이너 배포 에러** | PSA/PSP 제한 | PSA 레이블 조정 또는 securityContext 설정 |
| **레지스트리 인증서 에러** | Base64 인코딩 오류 | v1beta1: 이중 Base64, v1alpha3: 단일 Base64 |
| **업그레이드 실패** | 소프트웨어 구성 오류 | 어노테이션으로 검사 오버라이드 (위험!) |

### Supervisor SSH 접근 (긴급 트러블슈팅)

```bash
# dcli를 통한 Supervisor SSH 접근
# 1. vCenter SSH 접속
# 2. decryptK8Pwd.py 실행하여 비밀번호 획득
# ⚠️ 경고: Supervisor에 대한 변경은 클러스터를
#    지원 불가 상태로 만들 수 있습니다!
```

### 실패한 업그레이드 재시작

```bash
# kubectl proxy로 API 접근
kubectl proxy &

# 실패한 Job의 backoffLimit 증가 및 status 초기화
curl -X PATCH http://localhost:8001/... \
    -H "Content-Type: application/merge-patch+json" \
    -d '{"spec":{"backoffLimit":6}}'
```

---

## 17. 정리 및 요약

### 핵심 포인트

```
┌─────────────────────────────────────────────────────────────────┐
│                       핵심 요약                                   │
│                                                                 │
│  1. VKS = Supervisor + CAPI + CAPV 기반 K8s 클러스터 서비스       │
│     → kubectl, VCF CLI, VCF Automation으로 관리                  │
│                                                                 │
│  2. API 버전: v1beta1/v1beta2 사용 (v1alpha3 Deprecated)         │
│     → Versioned ClusterClass로 안전한 업그레이드                  │
│                                                                 │
│  3. 멀티 OS 지원: Photon, Ubuntu, Windows, RHEL                 │
│     → Windows는 Antrea CNI만, RHEL은 VKS 3.6+                  │
│                                                                 │
│  4. 인증: vCenter SSO (기본) + 외부 OIDC (Pinniped)              │
│     → 3가지 역할: Owner, Can edit, Can view                     │
│                                                                 │
│  5. 롤링 업데이트: Add-ons → CP → Workers 순서                   │
│     → 이미 배포된 클러스터는 kubectl edit 사용                    │
│                                                                 │
│  6. 오토스케일링: Worker 노드 자동 Scale Out/In                   │
│     → VKS 3.5+는 Add-on Management로 자동 관리                  │
│                                                                 │
│  7. 스토리지: pvCSI 드라이버, 동적/정적 PV, 볼륨 확장             │
│     → StorageClass 2개 자동 생성 (Immediate + LateBind)          │
│                                                                 │
│  8. 보안: Secure by Default                                     │
│     → etcd 암호화, PSA (v1.26+ enforce restricted)              │
│                                                                 │
│  9. 백업: Velero — CSI Snapshot 권장                             │
│     → CSI + vSphere Plugin 동시 사용 불가                        │
│                                                                 │
│  10. 애드온: VKS 3.5+ Add-on Management Framework               │
│      → 14개 표준 패키지, 선언적 Fleet 관리                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 주요 명령어 치트시트

```
┌─────────────────────────────────────────────────────────────────┐
│                    VKS 필수 명령어                                │
│                                                                 │
│  [인증/접속]                                                     │
│  vcf context create --endpoint IP --username USER              │
│  vcf context use CLUSTER-NAME                                  │
│                                                                 │
│  [클러스터 관리]                                                  │
│  kubectl apply -f cluster.yaml          # 클러스터 생성          │
│  kubectl get cluster                    # 클러스터 목록          │
│  kubectl describe cluster NAME          # 상세 상태             │
│  kubectl edit cluster NAME              # 클러스터 수정          │
│  kubectl delete cluster -n NS NAME      # 클러스터 삭제          │
│                                                                 │
│  [리소스 확인]                                                    │
│  kubectl get virtualmachineclass        # VM Class 목록         │
│  kubectl get kubernetesreleases         # VKr 목록              │
│  kubectl get clusterclass -n vmware-system-vks-public          │
│                                                                 │
│  [모니터링]                                                      │
│  kubectl describe machine NAME          # 머신 상태             │
│  kubectl describe pvc NAME              # 볼륨 상태             │
│  kubectl get secrets | grep CLUSTER     # Secret 목록           │
│                                                                 │
│  [VCF CLI]                                                      │
│  vcf cluster create -f cluster.yaml     # 클러스터 생성          │
│  vcf cluster list -A                    # 전체 클러스터 목록      │
│  vcf cluster get NAME                   # 클러스터 상태          │
│  vcf cluster upgrade NAME --kr VKR      # 업그레이드             │
│  vcf cluster delete -n NS NAME          # 클러스터 삭제          │
│  vcf kubernetes-release get             # VKr 목록              │
│                                                                 │
│  [애드온]                                                        │
│  kubectl get addons -n vmware-system-vks-public                │
│  kubectl get clusteraddon -n NAMESPACE  # 설치된 애드온 확인     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 학습 경로 가이드

```
┌─────────────────────────────────────────────────────────────────┐
│                    관련 교육 자료                                  │
│                                                                 │
│  ✅ 완료: VKS 클러스터 관리 전체 생명주기                          │
│                                                                 │
│  관련 자료:                                                      │
│  • k8s-crd-clusterapi.md  → CRD, Cluster API, VKS 기본 개념    │
│  • vcf-supervisor-vpc.md  → Supervisor VPC 네트워킹              │
│  • k8s-storage.md         → K8s 스토리지 기본 개념               │
│  • k8s-networking.md      → K8s 네트워킹 기본 개념               │
│  • k8s-rbac.md            → K8s RBAC 기본 개념                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

> **참고 문서:** [Broadcom TechDocs — Managing vSphere Kubernetes Service Clusters and Workloads](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vsphere-supervisor-services-and-standalone-components/latest/managing-vsphere-kuberenetes-service-clusters-and-workloads.html)
