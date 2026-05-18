# 03. NetApp Trident CSI 상세

## 1. 개요

NetApp Trident는 NetApp 스토리지 솔루션(ONTAP, Element, SolidFire, Cloud Volumes 등)을 위한
오픈소스 동적 스토리지 오케스트레이터이자 CSI 드라이버입니다.

- **공식 GitHub**: https://github.com/NetApp/trident
- **드라이버 이름**: `csi.trident.netapp.io`
- **지원 프로토콜**: NFS (v3/v4.1), iSCSI, NVMe/TCP, FC, SMB
- **지원 백엔드**: ONTAP NAS, ONTAP SAN, Element, Azure NetApp Files, Google Cloud NetApp Volumes, Amazon FSx for ONTAP

### 주요 기능

| 기능 | 지원 여부 |
|------|-----------|
| 동적 프로비저닝 | ✅ |
| ReadWriteMany (RWX) | ✅ (NFS) |
| Raw Block Volume | ✅ (iSCSI/NVMe) |
| 볼륨 스냅샷 | ✅ |
| 볼륨 클론 | ✅ |
| 볼륨 리사이즈 | ✅ |
| 볼륨 Import | ✅ (기존 볼륨 가져오기) |
| 멀티 백엔드 지원 | ✅ |
| QoS 정책 | ✅ |
| 데이터 암호화 | ✅ (NetApp Volume Encryption) |

---

## 2. 아키텍처

```
┌──────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                     │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │         Trident Controller (Deployment)          │    │
│  │                                                  │    │
│  │  ┌─────────────┐  ┌────────────────────────────┐ │    │
│  │  │  trident-   │  │  external-provisioner      │ │    │
│  │  │  main       │  │  external-attacher         │ │    │
│  │  │  container  │  │  external-snapshotter      │ │    │
│  │  │             │  │  external-resizer          │ │    │
│  │  └──────┬──────┘  └────────────────────────────┘ │    │
│  └─────────┼────────────────────────────────────────┘    │
│            │                                             │
│  ┌─────────▼────────────────────────────────────────┐    │
│  │         Trident Node (DaemonSet)                 │    │
│  │  ┌─────────────┐  ┌────────────────────────────┐ │    │
│  │  │  trident-   │  │  node-driver-registrar     │ │    │
│  │  │  main       │  │  livenessprobe             │ │    │
│  │  │  container  │  │                            │ │    │
│  │  └─────────────┘  └────────────────────────────┘ │    │
│  └──────────────────────────────────────────────────┘    │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │   Trident CRDs                                   │    │
│  │   - TridentOrchestrator                          │    │
│  │   - TridentBackendConfig (TBC)                   │    │
│  │   - TridentBackend                               │    │
│  │   - TridentStorageClass                          │    │
│  │   - TridentVolume                                │    │
│  └──────────────────────────────────────────────────┘    │
└─────────────────────────┬────────────────────────────────┘
                          │ ONTAP API (ZAPI/REST)
┌─────────────────────────▼────────────────────────────────┐
│            NetApp ONTAP / SAN Storage                    │
│  - NFS Export 생성/관리                                   │
│  - iSCSI LUN 생성/관리                                    │
│  - Snapshot 관리 (ONTAP 네이티브)                         │
└──────────────────────────────────────────────────────────┘
```

---

## 3. 설치

### 3.1 Trident Operator를 이용한 설치 (권장)

```bash
# Trident Operator 설치 (Helm)
helm repo add netapp-trident https://netapp.github.io/trident-helm-chart
helm repo update

# Trident 네임스페이스 생성
kubectl create namespace trident

# Helm으로 Trident 설치
helm install trident netapp-trident/trident-operator \
  --namespace trident \
  --set tridentAutosupportImage=docker.io/netapp/trident-autosupport:24.02 \
  --create-namespace

# 설치 확인
kubectl get pods -n trident
```

### 3.2 설치 상태 확인

```bash
# Trident 버전 확인
kubectl exec -n trident deployment/trident-controller -- tridentctl version

# Backend 목록 (아직 없을 것)
kubectl get tridentbackendconfigs -n trident

# CSI Driver 등록 확인
kubectl get csidriver csi.trident.netapp.io
```

---

## 4. Backend 구성

Backend는 Trident가 실제 스토리지 시스템에 접근하기 위한 구성 정보입니다.
`TridentBackendConfig` (TBC) CRD로 관리합니다.

### 4.1 ONTAP NAS (NFS) Backend

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ontap-nas-secret
  namespace: trident
stringData:
  username: vsadmin
  password: Netapp1!
---
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-ontap-nas
  namespace: trident
spec:
  version: 1
  storageDriverName: ontap-nas    # NFS 프로토콜
  managementLIF: 192.168.10.10   # ONTAP 관리 IP
  dataLIF: 192.168.20.10         # NFS 데이터 LIF IP
  svm: svm_nfs                   # SVM 이름
  credentials:
    name: ontap-nas-secret       # 위에서 생성한 Secret
  defaults:
    spaceReserve: "none"
    snapshotPolicy: "default"
    exportPolicy: "default"
    snapshotDir: "false"
  storage:
    - labels:
        performance: gold
      defaults:
        spaceReserve: "volume"
        snapshotPolicy: "default-1weekly"
    - labels:
        performance: silver
      defaults:
        spaceReserve: "none"
```

### 4.2 ONTAP SAN (iSCSI) Backend

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ontap-san-secret
  namespace: trident
stringData:
  username: vsadmin
  password: Netapp1!
---
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-ontap-san
  namespace: trident
spec:
  version: 1
  storageDriverName: ontap-san   # iSCSI 프로토콜
  managementLIF: 192.168.10.10
  dataLIF: 192.168.30.10         # iSCSI 데이터 LIF
  svm: svm_iscsi
  credentials:
    name: ontap-san-secret
  defaults:
    spaceReserve: "volume"
    spaceAllocation: "true"
    snapshotPolicy: "default"
    fsType: ext4
```

### 4.3 Azure NetApp Files Backend

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: anf-secret
  namespace: trident
stringData:
  clientID: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  clientSecret: "your-client-secret"
---
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-anf
  namespace: trident
spec:
  version: 1
  storageDriverName: azure-netapp-files
  subscriptionID: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  tenantID: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  location: koreacentral
  credentials:
    name: anf-secret
  virtualNetwork: my-vnet
  subnet: my-subnet
  serviceLevel: Premium
```

### 4.4 Backend 확인

```bash
# Backend 목록 확인
kubectl get tridentbackendconfigs -n trident

# Backend 상세 확인
kubectl describe tridentbackendconfigs backend-ontap-nas -n trident

# Backend 상태 (Running이면 정상)
kubectl get tridentbackends -n trident
```

---

## 5. StorageClass 구성

### 5.1 NFS StorageClass (ONTAP NAS)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: trident-sc-nas
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.trident.netapp.io
parameters:
  backendType: "ontap-nas"
  # 라벨로 특정 Backend 선택
  selector: "performance=gold"
  # NFS 내보내기 정책
  exportPolicy: "k8s_export"
  # 스냅샷 디렉토리 노출
  snapshotDir: "true"
mountOptions:
  - nfsvers=4.1
  - hard
  - timeo=600
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
```

### 5.2 iSCSI StorageClass (ONTAP SAN)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: trident-sc-san
provisioner: csi.trident.netapp.io
parameters:
  backendType: "ontap-san"
  selector: "performance=gold"
  fsType: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

### 5.3 Virtual Storage Pool 사용

```yaml
# 하나의 StorageClass에서 여러 성능 등급 선택
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: trident-sc-gold
provisioner: csi.trident.netapp.io
parameters:
  backendType: "ontap-nas"
  selector: "performance=gold"
  mediaType: "ssd"
reclaimPolicy: Retain
allowVolumeExpansion: true
```

---

## 6. PVC 사용 예제

### 6.1 NFS PVC (ReadWriteMany)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: trident-pvc-nfs
  namespace: default
spec:
  accessModes:
    - ReadWriteMany          # NFS는 RWX 지원
  resources:
    requests:
      storage: 50Gi
  storageClassName: trident-sc-nas
```

### 6.2 iSCSI PVC (ReadWriteOnce)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: trident-pvc-iscsi
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: trident-sc-san
  volumeMode: Filesystem    # 또는 Block (Raw 블록 디바이스)
```

### 6.3 볼륨 Import (기존 ONTAP 볼륨 가져오기)

```bash
# tridentctl로 기존 볼륨 import
tridentctl import volume backend-ontap-nas existing_volume_name \
  --pvc import-pvc.yaml \
  -n trident
```

```yaml
# import-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: imported-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
  storageClassName: trident-sc-nas
```

---

## 7. VolumeSnapshot

```yaml
# VolumeSnapshotClass 생성
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: trident-snapclass
driver: csi.trident.netapp.io
deletionPolicy: Delete
parameters:
  # ONTAP 스냅샷 정책 연동 (선택)
  # snapshotPolicy: "hourly"
---
# 스냅샷 생성
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: trident-snapshot-demo
  namespace: default
spec:
  volumeSnapshotClassName: trident-snapclass
  source:
    persistentVolumeClaimName: trident-pvc-nfs
```

---

## 8. 트러블슈팅

```bash
# Trident Controller 로그
kubectl logs -n trident deployment/trident-controller -c trident-main

# Node 로그
kubectl logs -n trident daemonset/trident-node -c trident-main

# Backend 상태 확인
kubectl get tridentbackends -n trident -o wide

# Volume 목록
kubectl get tridentvolumes -n trident

# tridentctl 사용 (Trident 전용 CLI)
kubectl exec -n trident deployment/trident-controller -- tridentctl get backend
kubectl exec -n trident deployment/trident-controller -- tridentctl get volume
```

### 자주 발생하는 문제

| 문제 | 원인 | 해결 |
|------|------|------|
| Backend Offline | ONTAP 연결 실패 | managementLIF/dataLIF IP 확인 |
| iSCSI Mount 실패 | initiator 미등록 | `iscsiadm -m discovery` 실행 |
| NFS Permission Denied | 내보내기 정책 불일치 | ONTAP export-policy 확인 |
| 볼륨 생성 느림 | Thick 프로비저닝 | `spaceReserve: none`으로 변경 |
| RWX Mount 실패 | NFS v4.1 비활성화 | ONTAP NFS v4.1 활성화 확인 |
