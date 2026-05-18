# 01. CSI (Container Storage Interface) 개요

## 1. CSI란?

CSI(Container Storage Interface)는 컨테이너 오케스트레이터(Kubernetes 등)와 스토리지 플러그인 간의 **표준 인터페이스**입니다.
2017년에 제안되어 Kubernetes 1.9에서 Alpha, 1.13에서 GA(Generally Available)로 안정화되었습니다.

### CSI 도입 전 문제점

- **In-tree 플러그인**: 스토리지 드라이버 코드가 Kubernetes 코어에 직접 포함
- Kubernetes 릴리즈 주기에 종속되어 스토리지 벤더가 빠르게 기능 추가 불가
- 버그 수정도 Kubernetes 전체 릴리즈를 기다려야 함
- 코드 품질 및 보안 문제 발생 시 Kubernetes 전체에 영향

### CSI 도입 후 이점

- 스토리지 드라이버를 **Kubernetes 외부(Out-of-tree)**에서 독립적으로 개발/배포
- 벤더가 자체 릴리즈 주기로 드라이버 업데이트 가능
- 표준 인터페이스로 인해 다양한 오케스트레이터에서 동일 드라이버 재사용 가능

---

## 2. CSI 아키텍처

```
┌─────────────────────────────────────────────┐
│              Kubernetes Cluster              │
│                                             │
│  ┌──────────────────────────────────────┐   │
│  │         CO (Container Orchestrator)  │   │
│  │  - kube-controller-manager           │   │
│  │  - kubelet                           │   │
│  └───────────────┬──────────────────────┘   │
│                  │ gRPC                      │
│  ┌───────────────▼──────────────────────┐   │
│  │         CSI Driver (Plugin)          │   │
│  │                                      │   │
│  │  ┌─────────────────────────────────┐ │   │
│  │  │   Controller Plugin (Deployment)│ │   │
│  │  │   - CreateVolume                │ │   │
│  │  │   - DeleteVolume                │ │   │
│  │  │   - ControllerPublishVolume     │ │   │
│  │  └─────────────────────────────────┘ │   │
│  │                                      │   │
│  │  ┌─────────────────────────────────┐ │   │
│  │  │   Node Plugin (DaemonSet)       │ │   │
│  │  │   - NodeStageVolume             │ │   │
│  │  │   - NodePublishVolume           │ │   │
│  │  │   - NodeGetCapabilities         │ │   │
│  │  └─────────────────────────────────┘ │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

---

## 3. CSI 주요 컴포넌트

### 3.1 Controller Plugin (컨트롤러 플러그인)

**역할**: 스토리지 리소스의 생명주기(생성/삭제/스냅샷) 관리

- 주로 `Deployment` 또는 `StatefulSet`으로 배포
- 클러스터 내 하나(또는 몇 개)의 인스턴스만 실행
- 스토리지 백엔드(예: vSphere, NetApp)와 직접 통신

**주요 gRPC 메서드:**

| 메서드 | 설명 |
|--------|------|
| `CreateVolume` | 새 볼륨 생성 |
| `DeleteVolume` | 볼륨 삭제 |
| `ControllerPublishVolume` | 볼륨을 특정 노드에 연결(attach) |
| `ControllerUnpublishVolume` | 볼륨 연결 해제(detach) |
| `CreateSnapshot` | 볼륨 스냅샷 생성 |
| `DeleteSnapshot` | 스냅샷 삭제 |
| `ListSnapshots` | 스냅샷 목록 조회 |
| `ControllerExpandVolume` | 볼륨 크기 확장 |

### 3.2 Node Plugin (노드 플러그인)

**역할**: 각 워커 노드에서 볼륨 마운트/언마운트 처리

- `DaemonSet`으로 배포 (모든 노드에서 실행)
- kubelet과 통신하여 볼륨을 Pod에 마운트
- 노드 로컬 파일시스템 조작 담당

**주요 gRPC 메서드:**

| 메서드 | 설명 |
|--------|------|
| `NodeStageVolume` | 볼륨을 노드의 스테이징 경로에 마운트 |
| `NodeUnstageVolume` | 스테이징 경로 언마운트 |
| `NodePublishVolume` | Pod의 볼륨 경로에 바인드 마운트 |
| `NodeUnpublishVolume` | Pod 볼륨 경로 언마운트 |
| `NodeGetCapabilities` | 노드 플러그인 기능 목록 반환 |
| `NodeGetInfo` | 노드 토폴로지 정보 반환 |
| `NodeExpandVolume` | 노드에서 파일시스템 확장 |

### 3.3 Sidecar Containers (사이드카 컨테이너)

CSI 드라이버는 Kubernetes API와의 통신을 위해 **공식 사이드카 컨테이너**를 함께 사용합니다.
이 컨테이너들은 `k8s.gcr.io/sig-storage/` 또는 `registry.k8s.io/sig-storage/` 이미지로 제공됩니다.

| 사이드카 | 역할 | 배포 위치 |
|----------|------|-----------|
| `external-provisioner` | PVC 생성 감지 → `CreateVolume` 호출 | Controller |
| `external-attacher` | VolumeAttachment 감지 → `ControllerPublishVolume` 호출 | Controller |
| `external-snapshotter` | VolumeSnapshot 감지 → `CreateSnapshot` 호출 | Controller |
| `external-resizer` | PVC 크기 변경 감지 → `ControllerExpandVolume` 호출 | Controller |
| `node-driver-registrar` | kubelet에 CSI 드라이버 소켓 등록 | Node (DaemonSet) |
| `livenessprobe` | CSI 드라이버 헬스체크 | Controller + Node |
| `cluster-driver-registrar` | CSIDriver 오브젝트 자동 생성 (deprecated) | Controller |

---

## 4. Kubernetes CSI 관련 오브젝트

### 4.1 CSIDriver

드라이버의 기능/특성을 클러스터에 등록하는 클러스터 레벨 오브젝트

```yaml
apiVersion: storage.k8s.io/v1
kind: CSIDriver
metadata:
  name: csi.vsphere.vmware.com
spec:
  attachRequired: true        # ControllerPublishVolume 필요 여부
  podInfoOnMount: false       # 마운트 시 Pod 정보 전달 여부
  volumeLifecycleModes:
    - Persistent              # 일반 PVC 사용
    - Ephemeral               # Inline ephemeral 볼륨 사용
```

### 4.2 CSINode

각 노드의 CSI 드라이버 등록 정보 (자동 생성)

```yaml
apiVersion: storage.k8s.io/v1
kind: CSINode
metadata:
  name: worker-node-01
spec:
  drivers:
    - name: csi.vsphere.vmware.com
      nodeID: worker-node-01
      topologyKeys:
        - topology.csi.vsphere.volume/zone
```

### 4.3 StorageClass

동적 프로비저닝 시 볼륨 생성 파라미터 정의

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsphere-sc
provisioner: csi.vsphere.vmware.com
parameters:
  storagePolicyName: "vSAN Default Storage Policy"
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

### 4.4 VolumeSnapshotClass

스냅샷 생성 시 사용할 드라이버 및 파라미터 정의

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: vsphere-snapclass
driver: csi.vsphere.vmware.com
deletionPolicy: Delete
```

---

## 5. CSI 볼륨 프로비저닝 흐름

### 5.1 동적 프로비저닝 (Dynamic Provisioning)

```
사용자: PVC 생성
    ↓
external-provisioner: PVC 감지 → CreateVolume RPC 호출
    ↓
CSI Controller Plugin: 스토리지 백엔드에 볼륨 생성
    ↓
external-provisioner: PV 오브젝트 생성, PVC와 바인드
    ↓
Scheduler: Pod를 적절한 노드에 스케줄
    ↓
external-attacher: VolumeAttachment 생성 → ControllerPublishVolume RPC 호출
    ↓
CSI Controller Plugin: 볼륨을 해당 노드에 attach
    ↓
kubelet: NodeStageVolume → NodePublishVolume RPC 호출
    ↓
CSI Node Plugin: 볼륨을 Pod 경로에 마운트
    ↓
Pod: 볼륨 사용 가능
```

### 5.2 정적 프로비저닝 (Static Provisioning)

```
관리자: 기존 스토리지 볼륨으로 PV 수동 생성
    ↓
사용자: PVC 생성
    ↓
Kubernetes: PVC와 PV 매칭 (바인드)
    ↓
이하 동일 (attach → mount 과정)
```

---

## 6. AccessMode (접근 모드)

| AccessMode | 약자 | 설명 |
|------------|------|------|
| `ReadWriteOnce` | RWO | 단일 노드에서 읽기/쓰기 |
| `ReadOnlyMany` | ROX | 여러 노드에서 읽기만 |
| `ReadWriteMany` | RWX | 여러 노드에서 읽기/쓰기 |
| `ReadWriteOncePod` | RWOP | 단일 Pod에서만 읽기/쓰기 (K8s 1.22+) |

> 지원하는 AccessMode는 드라이버와 스토리지 프로토콜에 따라 다름 (블록: RWO/RWOP, NFS: RWX 가능)

---

## 7. Volume Mode

| VolumeMode | 설명 |
|------------|------|
| `Filesystem` | 파일시스템으로 포맷하여 마운트 (기본값) |
| `Block` | Raw 블록 디바이스로 노출 (포맷 없음) |
