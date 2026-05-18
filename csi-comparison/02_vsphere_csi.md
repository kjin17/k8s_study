# 02. vSphere CSI Driver 상세

## 1. 개요

vSphere CSI Driver(공식명: VMware vSphere Container Storage Plug-in)는 VMware vSphere 환경에서
Kubernetes 워크로드에 영구 스토리지를 제공하는 공식 CSI 드라이버입니다.

- **공식 GitHub**: https://github.com/kubernetes-sigs/vsphere-csi-driver
- **드라이버 이름**: `csi.vsphere.vmware.com`
- **지원 프로토콜**: VMDK (블록), vSAN File Service (NFS/RWX)
- **최소 요구사항**: vSphere 6.7 U3+, vCenter 6.7 U3+

### 주요 기능

| 기능 | 지원 여부 |
|------|-----------|
| 동적 프로비저닝 | ✅ |
| 볼륨 스냅샷 | ✅ (vSphere 7.0+) |
| 볼륨 클론 | ✅ |
| 볼륨 리사이즈 (확장) | ✅ |
| Raw Block Volume | ✅ |
| Topology (존/랙 인식) | ✅ |
| ReadWriteMany (RWX) | ✅ (vSAN File Service 필요) |
| 멀티 vCenter 지원 | ✅ (v3.0+) |

---

## 2. 아키텍처

```
┌──────────────────────────────────────────────────────┐
│                 Kubernetes Cluster                    │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │     vsphere-csi-controller (Deployment)        │  │
│  │                                                │  │
│  │  ┌──────────────┐  ┌──────────────────────┐   │  │
│  │  │ csi-driver   │  │ external-provisioner │   │  │
│  │  │ (controller) │  │ external-attacher    │   │  │
│  │  │              │  │ external-snapshotter │   │  │
│  │  │              │  │ external-resizer     │   │  │
│  │  │              │  │ livenessprobe        │   │  │
│  │  └──────┬───────┘  └──────────────────────┘   │  │
│  └─────────┼──────────────────────────────────────┘  │
│            │ gRPC (UNIX socket)                       │
│  ┌─────────▼──────────────────────────────────────┐  │
│  │     vsphere-csi-node (DaemonSet)               │  │
│  │                                                │  │
│  │  ┌──────────────┐  ┌──────────────────────┐   │  │
│  │  │ csi-driver   │  │ node-driver-registrar│   │  │
│  │  │ (node)       │  │ livenessprobe        │   │  │
│  │  └──────────────┘  └──────────────────────┘   │  │
│  └────────────────────────────────────────────────┘  │
└─────────────────────────┬────────────────────────────┘
                          │ vSphere API (SOAP/REST)
┌─────────────────────────▼────────────────────────────┐
│              vCenter Server                          │
│  - VMDK 생성/삭제/attach/detach                      │
│  - vSAN Datastore 관리                               │
│  - Storage Policy 적용                               │
└──────────────────────────────────────────────────────┘
```

---

## 3. 설치

### 3.1 사전 요구사항

```bash
# vSphere Cloud Provider Interface(CPI) 설치 확인
kubectl get nodes -o jsonpath='{.items[*].spec.providerID}'
# 출력 예시: vsphere://42306e9c-7bfa-7042-4e71-exxxxxxx

# CSI 드라이버 설치 전 CPI가 반드시 먼저 구성되어야 함
```

### 3.2 Secret 생성 (vCenter 인증 정보)

```yaml
# vsphere-config-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: vsphere-config-secret
  namespace: vmware-system-csi
stringData:
  csi-vsphere.conf: |
    [Global]
    cluster-id = "my-k8s-cluster"
    cluster-distribution = "OpenShift"  # 또는 "Vanilla"

    [VirtualCenter "vcenter.example.com"]
    insecure-flag = "false"
    user = "administrator@vsphere.local"
    password = "VMware1!"
    port = "443"
    datacenters = "Datacenter"
```

```bash
kubectl apply -f vsphere-config-secret.yaml
```

### 3.3 드라이버 설치 (Helm)

```bash
# Helm 레포지토리 추가
helm repo add vsphere-csi https://kubernetes-sigs.github.io/vsphere-csi-driver/charts
helm repo update

# 네임스페이스 생성
kubectl create namespace vmware-system-csi

# Helm으로 설치
helm install vsphere-csi vsphere-csi/vsphere-csi \
  --namespace vmware-system-csi \
  --set config.vcenter="vcenter.example.com" \
  --set config.username="administrator@vsphere.local" \
  --set config.password="VMware1!" \
  --set config.datacenter="Datacenter"
```

### 3.4 드라이버 설치 확인

```bash
# CSI 드라이버 Pod 상태 확인
kubectl get pods -n vmware-system-csi

# 출력 예시:
# NAME                                     READY   STATUS    RESTARTS
# vsphere-csi-controller-7d9fcb5b8-xk2p9  7/7     Running   0
# vsphere-csi-node-4xbpq                  3/3     Running   0  (각 노드에 하나)

# CSIDriver 오브젝트 확인
kubectl get csidriver csi.vsphere.vmware.com

# CSINode 확인
kubectl get csinode
```

---

## 4. StorageClass 구성

### 4.1 기본 StorageClass (VMDK 블록)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsphere-sc-standard
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.vmware.com
parameters:
  # vSphere Storage Policy 이름 (vCenter에서 미리 정의)
  storagePolicyName: "vSAN Default Storage Policy"
  # 데이터스토어 URL (선택사항, 없으면 정책에 맞는 데이터스토어 자동 선택)
  # datastoreurl: "ds:///vmfs/volumes/vsan:xxxx/"
reclaimPolicy: Delete        # PVC 삭제 시 볼륨도 삭제
allowVolumeExpansion: true   # 볼륨 확장 허용
volumeBindingMode: WaitForFirstConsumer  # Pod 스케줄링 이후 볼륨 생성
```

### 4.2 Topology 인식 StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsphere-sc-topology
provisioner: csi.vsphere.vmware.com
parameters:
  storagePolicyName: "Zone-A Storage Policy"
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.csi.vsphere.volume/zone
        values:
          - zone-a
          - zone-b
```

### 4.3 vSAN File Service (RWX) StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsphere-sc-rwx
provisioner: csi.vsphere.vmware.com
parameters:
  storagePolicyName: "vSAN Default Storage Policy"
  csi.storage.k8s.io/fstype: "nfs4"  # vSAN File Service 사용 시
accessModes:
  - ReadWriteMany
reclaimPolicy: Delete
```

---

## 5. VolumeSnapshotClass 구성

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: vsphere-snapclass
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: csi.vsphere.vmware.com
deletionPolicy: Delete  # 스냅샷 오브젝트 삭제 시 실제 스냅샷도 삭제
parameters:
  # vSphere 스냅샷 관련 파라미터 (선택)
  # description: "Created by Kubernetes"
```

> **사전 조건**: VolumeSnapshot CRD와 snapshot-controller가 클러스터에 설치되어 있어야 함

```bash
# snapshot CRD 설치
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# snapshot-controller 설치
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml
```

---

## 6. 사용 예제

### 6.1 PVC 생성

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vsphere-pvc-demo
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: vsphere-sc-standard
```

### 6.2 Pod에서 PVC 사용

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vsphere-pod-demo
  namespace: default
spec:
  containers:
    - name: app
      image: nginx:latest
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: vsphere-pvc-demo
```

### 6.3 VolumeSnapshot 생성 및 복원

```yaml
# 스냅샷 생성
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: vsphere-snapshot-demo
  namespace: default
spec:
  volumeSnapshotClassName: vsphere-snapclass
  source:
    persistentVolumeClaimName: vsphere-pvc-demo
---
# 스냅샷에서 PVC 복원
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vsphere-pvc-restored
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: vsphere-sc-standard
  dataSource:
    name: vsphere-snapshot-demo
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

### 6.4 볼륨 확장 (Resize)

```bash
# PVC의 storage 요청 크기를 늘림
kubectl patch pvc vsphere-pvc-demo -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 확인
kubectl get pvc vsphere-pvc-demo
```

---

## 7. Tanzu (TKG) 연동

VMware Tanzu Kubernetes Grid(TKG) 또는 TKGm 환경에서는 vSphere CSI가 기본 내장됩니다.

```bash
# TKG 클러스터에서 기본 StorageClass 확인
kubectl get storageclass

# 출력 예시:
# NAME                          PROVISIONER                    ...
# default (default)             csi.vsphere.vmware.com         ...
# tanzu-storage-policy          csi.vsphere.vmware.com         ...
```

### TKG StorageClass 예제

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: tanzu-sc-vsan
provisioner: csi.vsphere.vmware.com
parameters:
  storagePolicyName: "tanzu-storage-policy"
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

---

## 8. 트러블슈팅

```bash
# CSI 드라이버 로그 확인
kubectl logs -n vmware-system-csi deployment/vsphere-csi-controller -c vsphere-csi-controller

# Node 드라이버 로그
kubectl logs -n vmware-system-csi daemonset/vsphere-csi-node -c vsphere-csi-node

# PVC가 Pending 상태일 때 이벤트 확인
kubectl describe pvc vsphere-pvc-demo

# VolumeAttachment 확인
kubectl get volumeattachment
```

### 자주 발생하는 문제

| 문제 | 원인 | 해결 |
|------|------|------|
| PVC Pending | StorageClass가 없거나 Storage Policy 불일치 | vCenter에서 Policy 확인 |
| Mount 실패 | VMware Tools 미설치 | 게스트 OS에 open-vm-tools 설치 |
| Snapshot 실패 | snapshot-controller 미설치 | external-snapshotter 배포 확인 |
| RWX 미지원 | vSAN File Service 비활성화 | vSAN 7.0+ 및 File Service 활성화 필요 |
