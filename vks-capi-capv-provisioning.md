# VKS 클러스터 프로비저닝 심화 — CAPI/CAPV 컨트롤러 동작 과정

> VKS(vSphere Kubernetes Service) 워크로드 클러스터를 생성할 때 **Supervisor 내부에서 CAPI/CAPV 컨트롤러들이 어떤 순서로 동작하여 VM이 만들어지고 노드가 조인되는지**를 단계별로 추적합니다.
> CRD/Cluster API/CAPV 기초 개념은 [`k8s-crd-clusterapi.md`](k8s-crd-clusterapi.md), 클러스터 운영 전반은 [`vks-cluster-management.md`](vks-cluster-management.md)를 먼저 참고하세요.

---

## 목차

1. [개념 요약 — CAPI 리소스와 CAPV 매핑](#1-개념-요약--capi-리소스와-capv-매핑)
2. [Supervisor 내 컨트롤러 구성](#2-supervisor-내-컨트롤러-구성)
3. [클러스터 생성 End-to-End 흐름](#3-클러스터-생성-end-to-end-흐름)
4. [단계별 상세 동작](#4-단계별-상세-동작)
5. [실습: 생성 과정 관찰](#5-실습-생성-과정-관찰)
6. [Scale & Upgrade 시 동작](#6-scale--upgrade-시-동작)
7. [트러블슈팅](#7-트러블슈팅)
8. [정리 및 핵심 요약](#8-정리-및-핵심-요약)

---

## 1. 개념 요약 — CAPI 리소스와 CAPV 매핑

### CAPI 리소스 계층

| CAPI 리소스 | 역할 | 대응 비유 |
|---|---|---|
| Cluster | 클러스터 전체의 논리적 표현 (네트워크 CIDR, 토폴로지) | — |
| KubeadmControlPlane (KCP) | Control Plane 노드 수/버전 관리, kubeadm 오케스트레이션 | — |
| MachineDeployment | Worker 노드 그룹 (롤링 업데이트 지원) | Deployment |
| MachineSet | MachineDeployment의 특정 버전 스냅샷 | ReplicaSet |
| Machine | 노드 1대의 논리적 표현 | Pod |
| KubeadmConfig | 노드 부트스트랩용 cloud-init 데이터 생성 | — |

### CAPV(Infrastructure Provider) 매핑

| CAPI 리소스 | CAPV 리소스 | 실제 vSphere 객체 |
|---|---|---|
| Cluster | VSphereCluster | Control Plane Endpoint (VIP/LB) |
| Machine | VSphereMachine | 가상머신 (VM) |
| (템플릿) | VSphereMachineTemplate | VM 스펙 (VM Class, Storage Class, VKr 이미지) |

> 💡 **Supervisor 모드 vs govmomi 모드**
> Supervisor 환경의 CAPV(`vmware.infrastructure.cluster.x-k8s.io` API 그룹)는 VM을 vCenter API로 직접 만들지 않고
> **VM Operator**(`vmoperator.vmware.com`의 VirtualMachine CR)에게 위임합니다.
> 독립형(OSS/TKGm) CAPV는 govmomi로 vCenter에 직접 VM Clone을 요청합니다.

---

## 2. Supervisor 내 컨트롤러 구성

```bash
# CAPI/CAPV 컨트롤러
kubectl get pods -n vmware-system-capw
# NAME                                        READY   STATUS
# capi-controller-manager-xxx                 2/2     Running   # CAPI Core
# capi-kubeadm-bootstrap-controller-xxx       2/2     Running   # Bootstrap Provider
# capi-kubeadm-control-plane-controller-xxx   2/2     Running   # Control Plane Provider
# capw-controller-manager-xxx                 2/2     Running   # Infra Provider (CAPV Supervisor 모드)

kubectl get pods -n vmware-system-vmop    # VM Operator (VM 생성 담당)
kubectl get pods -n vmware-system-tkg     # VKS/TKG 컨트롤러 (VKr, 애드온)
```

```
┌────────────────────────────────────────────────────────────────┐
│                 Supervisor 컨트롤러 협업 구조                     │
│                                                                │
│  Cluster CR ──▶ VKS/TKG Controller (토폴로지/애드온)             │
│                     │                                          │
│                     ▼                                          │
│               CAPI Controller ◀──▶ KCP / Bootstrap Controller  │
│                     │                    (cloud-init 생성)      │
│                     ▼                                          │
│               CAPV Controller (VSphereCluster/VSphereMachine)  │
│                     │                                          │
│                     ▼                                          │
│               VM Operator ──▶ vCenter (VM Clone / 전원 관리)    │
└────────────────────────────────────────────────────────────────┘
```

---

## 3. 클러스터 생성 End-to-End 흐름

```
 사용자          VKS/TKG        CAPI          KCP/Bootstrap      CAPV           VM Operator      vCenter
(kubectl)      Controller    Controller      Controller       Controller       (vmop)
    |               |             |               |               |               |               |
[1] |-- Cluster --->|             |               |               |               |               |
    |  (apply)      |             |               |               |               |               |
    |               |             |               |               |               |               |
[2] |               |-- Topology 렌더링 --------->|               |               |               |
    |               |   Cluster / KCP / MachineDeployment /      |               |               |
    |               |   VSphereMachineTemplate 생성              |               |               |
    |               |             |               |               |               |               |
[3] |               |             |-- VSphereCluster Reconcile ->|               |               |
    |               |             |               |               |-- Control Plane VIP 확보     |
    |               |             |               |               |   (NSX LB / NSX ALB)         |
    |               |             |               |               |               |               |
[4] |               |             |<-- 첫 번째 CP Machine 생성    |               |               |
    |               |             |               |-- KubeadmConfig 렌더링       |               |
    |               |             |               |   cloud-init Secret 생성     |               |
    |               |             |               |   (kubeadm init)             |               |
    |               |             |               |               |               |               |
[5] |               |             |-- Machine → VSphereMachine ->|               |               |
    |               |             |               |               |-- VirtualMachine CR 생성 --->|
    |               |             |               |               |   (bootstrap data 전달)      |
    |               |             |               |               |               |-- VM Clone ->|
    |               |             |               |               |               |   (Content Library
    |               |             |               |               |               |    VKr 이미지, 전원 On)
    |               |             |               |               |               |<-- VM IP ----|
    |               |             |               |               |               |   (DHCP/NSX) |
    |               |             |               |               |               |               |
[6] |               |             |               |          [VM 내부] 부팅 → cloud-init 실행 →  |
    |               |             |               |          kubeadm init → API Server 기동      |
    |               |             |               |               |               |               |
    |               |             |-- Node 등록 확인 → Machine: Running          |               |
    |               |             |<-- 나머지 CP Machine 순차 join (KCP)         |               |
    |               |             |-- Worker Machine 병렬 생성 (kubeadm join) → [5]~[6] 반복     |
    |               |             |               |               |               |               |
[7] |               |-- 애드온 배포 (CNI/CSI/CPI, kapp-controller) → 워크로드 클러스터           |
    |               |             |               |               |               |               |
[8] |<- Cluster Ready (Phase: Provisioned) -------|               |               |               |
    |               |             |               |               |               |               |
```

---

## 4. 단계별 상세 동작

### [1] 사용자 요청

vSphere Namespace에 `Cluster`(v1beta1) CR을 apply 합니다.
(레거시 `TanzuKubernetesCluster` API는 VKS 3.7에서 완전 제거 — [`vks-cluster-management.md`](vks-cluster-management.md) 4장 참조)

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: cluster-01
  namespace: ns01                        # 자신의 vSphere Namespace
spec:
  clusterNetwork:
    services:
      cidrBlocks: ["10.96.0.0/12"]
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    serviceDomain: cluster.local
  topology:
    class: builtin-generic-v3.7.0        # VKS 3.x ClusterClass (vSphere 7/8: tanzukubernetescluster)
    version: v1.36.0---vmware.1-vkr.1
    controlPlane:
      replicas: 3                        # 운영: 3 (etcd 정족수), VKS 3.7+: 최대 5
    workers:
      machineDeployments:
      - class: node-pool
        name: node-pool-1
        replicas: 2
    variables:
    - name: vmClass
      value: best-effort-small           # kubectl get vmclass
    - name: storageClass
      value: k8s-storage-policy          # 네임스페이스에 할당된 Storage Class
```

### [2] Topology 렌더링 (CAPI Topology Controller)

`spec.topology`(버전, 노드 수, VM Class, VKr)를 ClusterClass 템플릿과 결합하여 하위 리소스 트리를 생성합니다.

```
Cluster
 ├── VSphereCluster                      # Infra: Control Plane Endpoint
 ├── KubeadmControlPlane
 │    └── Machine (x N)
 │         ├── KubeadmConfig            # cloud-init (kubeadm init/join)
 │         └── VSphereMachine
 │              └── VirtualMachine      # VM Operator CR → 실제 VM
 └── MachineDeployment (node pool 별)
      └── MachineSet
           └── Machine (x N)  →  KubeadmConfig / VSphereMachine / VirtualMachine
```

### [3] 인프라 준비 (CAPV)

CAPV가 `VSphereCluster`를 Reconcile 하여 **Control Plane Endpoint(VIP)** 를 확보합니다.
NSX-T 환경은 NSX Load Balancer, VDS 환경은 NSX ALB(Avi)가 VIP를 제공하며,
완료 시 `VSphereCluster`의 `status.ready=true`가 됩니다.

### [4] Control Plane 부트스트랩 (KCP + Bootstrap Controller)

- KCP는 첫 Machine **1대를 먼저** 생성 (etcd 초기화를 위해 순차 진행)
- Kubeadm Bootstrap Controller(CABPK)가 `KubeadmConfig`를 렌더링하여 **cloud-init 데이터를 Secret으로 생성**
- Secret 참조가 Machine의 `spec.bootstrap.dataSecretName`에 연결됨
- 첫 노드는 `kubeadm init`, 이후 노드는 `kubeadm join` 스크립트를 받음

### [5] VM 생성 (CAPV → VM Operator → vCenter)

- CAPV가 Machine에 대응하는 `VSphereMachine` 생성 → VM Operator의 `VirtualMachine` CR로 변환
- VM Operator는 vSphere Namespace에 연결된 **Content Library의 VKr 이미지**로 VM을 Clone
- **VM Class**(CPU/메모리), **Storage Class**(스토리지 정책) 적용 후 전원 On
- bootstrap Secret은 VM metadata(cloud-init userdata)로 주입

### [6] 노드 기동 & 등록

- VM 부팅 → cloud-init이 kubeadm 실행 → Control Plane 구성 또는 join
- CAPI Machine Controller가 워크로드 클러스터의 Node 객체와 Machine의 `providerID`를 매칭 → `Running` 전환
- Control Plane 정족수 충족 후 MachineDeployment의 Worker들이 **병렬** 생성

### [7] 애드온 배포 (VKS Controller)

API Server 기동 후 애드온 컨트롤러가 `ClusterBootstrap`/AddonConfig에 정의된 패키지
(CNI: Antrea/Calico/Cilium, vSphere CSI, Cloud Provider(CPI), kapp-controller, metrics-server 등)를 설치합니다.
**CNI가 배포되어야 Node가 `Ready`로 전환**됩니다. (CNI 비교: [`cni-comparison/`](cni-comparison/))

### [8] 완료

모든 Machine이 Running, 애드온 Ready → Cluster `phase: Provisioned`, `ControlPlaneReady/InfrastructureReady=True`

---

## 5. 실습: 생성 과정 관찰

```bash
# Supervisor Context로 전환 후 자신의 vSphere Namespace에서 확인

# 실습 1: CAPI 리소스 트리 확인
kubectl get cluster,kubeadmcontrolplane,machinedeployment,machine -n ns01
# NAME                                  PHASE         AGE
# cluster.cluster.x-k8s.io/cluster-01   Provisioned   10m
# NAME                                  INITIALIZED   REPLICAS   READY
# kubeadmcontrolplane.../cluster-01-xxx true          3          3
# NAME                                  PHASE     NODENAME
# machine.../cluster-01-xxx-abcde       Running   cluster-01-xxx-abcde

# 실습 2: CAPV / VM Operator 리소스 확인
kubectl get vspherecluster,vspheremachine -n ns01
kubectl get virtualmachine -n ns01
# NAME                    POWER-STATE   CLASS               IMAGE                    IP
# cluster-01-xxx-abcde    PoweredOn     best-effort-small   ...photon-...-v1.36...   10.244.0.34

# 실습 3: 부트스트랩 cloud-init Secret 확인 ([4]단계 산출물)
kubectl get secret -n ns01 | grep bootstrap

# 실습 4: 진행 상황/실패 원인 추적 — Cluster → Machine → VirtualMachine 순으로 conditions 확인
kubectl describe cluster cluster-01 -n ns01
kubectl describe machine <machine-name> -n ns01
```

---

## 6. Scale & Upgrade 시 동작

### Worker Scale-out / Scale-in

- `spec.topology.workers.machineDeployments[].replicas` 수정
- Scale-out: MachineSet이 새 Machine 추가 → [5]~[6] 과정 반복
- Scale-in: Machine 삭제 → 노드 drain → VM 삭제 순으로 진행

### Kubernetes 버전 업그레이드 (Rolling Replace)

```
spec.topology.version 변경
  → 새 VKr 이미지 기반 VSphereMachineTemplate로 교체
  → KCP: Control Plane 1대씩 교체 (새 VM 생성 → join → 구 VM drain/삭제)
  → MachineDeployment: Worker 롤링 교체
```

> 💡 노드는 **In-place 업그레이드가 아닌 VM 재생성(Immutable Infrastructure)** 방식입니다.
> (단, VKS 3.7부터 일부 노드 *구성 변경*은 인플레이스 업데이트를 지원 — K8s 버전/VM Class 변경은 여전히 롤링 교체)

---

## 7. 트러블슈팅

| 증상 | 확인 포인트 |
|---|---|
| Cluster가 Provisioning에서 멈춤 | `VSphereCluster` conditions — VIP(LB) 확보 실패 여부 (NSX/ALB 상태) |
| Machine이 Provisioning에서 멈춤 | `VirtualMachine` 상태 — VM Class 리소스 부족, Storage Policy 미할당, Content Library에 해당 VKr 이미지 없음 |
| VM은 켜졌는데 Machine이 Running이 안 됨 | VM 콘솔에서 cloud-init 로그 확인, Control Plane Endpoint 통신 여부 |
| Node가 NotReady | CNI 애드온 배포 여부 — 워크로드 클러스터에서 `kubectl get pods -n kube-system` |
| 업그레이드 중단 | KCP conditions, 신규 VKr 호환성 및 ClusterClass 리베이스 필요 여부 |

```bash
# 컨트롤러 로그 직접 확인 (Supervisor 접근 가능 시)
kubectl logs -n vmware-system-capw deploy/capi-controller-manager
kubectl logs -n vmware-system-capw deploy/capw-controller-manager
kubectl logs -n vmware-system-vmop deploy/vmware-system-vmop-controller-manager
```

---

## 8. 정리 및 핵심 요약

```
┌──────────────────────────────────────────────────────────────────┐
│                  한눈에 보는 프로비저닝 파이프라인                    │
│                                                                  │
│  Cluster apply → Topology 렌더링(ClusterClass) → VIP 확보(CAPV)   │
│   → cloud-init Secret(Bootstrap) → VirtualMachine(VM Operator)   │
│   → VM Clone(vCenter, VKr 이미지) → kubeadm init/join             │
│   → 애드온(CNI/CSI/CPI) → Provisioned                            │
└──────────────────────────────────────────────────────────────────┘
```

### 핵심 포인트 7가지

1. VKS 클러스터 생성은 **VKS/TKG → CAPI → KCP/Bootstrap → CAPV → VM Operator → vCenter**의 컨트롤러 체인으로 진행된다
2. Supervisor 모드 CAPV는 vCenter를 직접 호출하지 않고 **VM Operator의 VirtualMachine CR**에 위임한다
3. 노드 부트스트랩의 실체는 Bootstrap Controller가 만든 **cloud-init Secret**이다 (`spec.bootstrap.dataSecretName`)
4. Control Plane은 etcd 정족수 때문에 **순차 생성**, Worker는 **병렬 생성**된다
5. **CNI가 배포되기 전까지 Node는 NotReady**가 정상이다 — 애드온 단계까지가 프로비저닝이다
6. 업그레이드는 In-place가 아니라 **VM 재생성 롤링 교체**(Immutable Infrastructure) 방식이다
7. 트러블슈팅은 **Cluster → Machine → VirtualMachine 순서로 conditions를 추적**하는 것이 기본이다
