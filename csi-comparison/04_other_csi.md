# 04. 기타 대표 CSI 드라이버

## 1. AWS EBS CSI Driver

### 1.1 개요

Amazon Elastic Block Store(EBS)를 Kubernetes PV로 사용하는 공식 AWS CSI 드라이버입니다.
2022년부터 EKS에서 in-tree `kubernetes.io/aws-ebs` 프로비저너를 대체하는 표준 방식입니다.

- **GitHub**: https://github.com/kubernetes-sigs/aws-ebs-csi-driver
- **드라이버 이름**: `ebs.csi.aws.com`
- **지원 프로토콜**: EBS (블록 스토리지, NVMe/SCSI)
- **지원 볼륨 타입**: gp2, gp3, io1, io2, sc1, st1

### 1.2 주요 특징

| 기능 | 지원 |
|------|------|
| 동적 프로비저닝 | ✅ |
| ReadWriteOnce | ✅ |
| ReadWriteMany | ❌ (EBS 특성상 단일 노드만) |
| VolumeSnapshot | ✅ |
| 볼륨 확장 | ✅ |
| 볼륨 암호화 (KMS) | ✅ |
| Topology (AZ 인식) | ✅ |
| io2 Block Express | ✅ |

### 1.3 설치

```bash
# EKS Add-on으로 설치 (권장)
aws eks create-addon \
  --cluster-name my-cluster \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn arn:aws:iam::123456789012:role/AmazonEKS_EBS_CSI_DriverRole

# 또는 Helm으로 설치
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm upgrade --install aws-ebs-csi-driver \
  aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::123456789012:role/AmazonEKS_EBS_CSI_DriverRole"
```

### 1.4 StorageClass 예제

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc-gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3                  # gp3 볼륨 타입
  iops: "3000"              # IOPS (gp3: 3000-16000)
  throughput: "125"         # MiB/s (gp3: 125-1000)
  encrypted: "true"         # EBS 암호화
  kmsKeyId: "arn:aws:kms:ap-northeast-2:123456789012:key/xxxx"
volumeBindingMode: WaitForFirstConsumer  # AZ 인식을 위해 필수
reclaimPolicy: Delete
allowVolumeExpansion: true
```

### 1.5 PVC 예제

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-pvc-demo
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: ebs-sc-gp3
```

---

## 2. GCE PD CSI Driver (Google Persistent Disk)

### 2.1 개요

Google Cloud의 Persistent Disk를 Kubernetes PV로 사용하는 공식 CSI 드라이버입니다.
GKE 1.18+에서 기본 활성화됩니다.

- **GitHub**: https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver
- **드라이버 이름**: `pd.csi.storage.gke.io`
- **지원 디스크 타입**: pd-standard, pd-ssd, pd-balanced, pd-extreme, hyperdisk-extreme

### 2.2 주요 특징

| 기능 | 지원 |
|------|------|
| 동적 프로비저닝 | ✅ |
| ReadWriteOnce | ✅ |
| ReadOnlyMany | ✅ (pd-standard/pd-ssd를 여러 Pod에 ReadOnly 마운트) |
| ReadWriteMany | ❌ (Filestore CSI 사용 필요) |
| VolumeSnapshot | ✅ |
| 볼륨 확장 | ✅ |
| 리전 PD (Zonal 장애 복구) | ✅ |
| Customer-Managed Encryption | ✅ |

### 2.3 설치

```bash
# GKE에서는 기본 활성화 (수동 설치 불필요)
# 자체 설치 시
kubectl apply -k "github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver/deploy/kubernetes/overlays/stable"
```

### 2.4 StorageClass 예제

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gce-pd-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
  replication-type: none       # 또는 regional-pd (리전 복제)
  disk-encryption-kms-key: "projects/my-project/locations/global/keyRings/my-ring/cryptoKeys/my-key"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
---
# 리전 PD (Zone 장애 시 자동 복구)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gce-pd-regional
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-balanced
  replication-type: regional-pd
  zones: us-central1-a,us-central1-b
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
```

---

## 3. Azure Disk CSI Driver

### 3.1 개요

Azure Managed Disk를 Kubernetes PV로 사용하는 공식 Microsoft CSI 드라이버입니다.
AKS 1.21+에서 기본 활성화됩니다.

- **GitHub**: https://github.com/kubernetes-sigs/azuredisk-csi-driver
- **드라이버 이름**: `disk.csi.azure.com`
- **지원 디스크 타입**: Standard_LRS, Premium_LRS, UltraSSD_LRS, PremiumV2_LRS

### 3.2 주요 특징

| 기능 | 지원 |
|------|------|
| 동적 프로비저닝 | ✅ |
| ReadWriteOnce | ✅ |
| ReadWriteMany | ❌ (Azure Files CSI 사용 필요) |
| VolumeSnapshot | ✅ |
| 볼륨 확장 | ✅ |
| Ultra Disk (초저지연) | ✅ |
| Shared Disk (공유 디스크) | ✅ (SCSI PR 기반) |
| Zone 인식 | ✅ |

### 3.3 설치

```bash
# AKS에서는 기본 활성화
# 자체 설치 시 (Helm)
helm repo add azuredisk-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/master/charts
helm repo update

helm install azuredisk-csi-driver azuredisk-csi-driver/azuredisk-csi-driver \
  --namespace kube-system \
  --set cloud=AzurePublicCloud
```

### 3.4 StorageClass 예제

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-disk-premium
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS       # Standard_LRS, Premium_LRS, UltraSSD_LRS
  kind: Managed              # Managed 디스크 사용
  cachingmode: ReadOnly      # None, ReadOnly, ReadWrite
  # diskEncryptionSetID: "/subscriptions/.../diskEncryptionSets/myDES"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
---
# Ultra Disk StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-disk-ultra
provisioner: disk.csi.azure.com
parameters:
  skuName: UltraSSD_LRS
  diskIopsReadWrite: "4000"
  diskMBpsReadWrite: "300"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
```

---

## 4. Rook-Ceph CSI

### 4.1 개요

Rook은 Ceph를 Kubernetes에서 운영하기 위한 클라우드 네이티브 스토리지 오케스트레이터입니다.
Ceph CSI 드라이버와 통합하여 블록(RBD), 파일(CephFS), 오브젝트(RGW) 스토리지를 제공합니다.

- **GitHub**: https://github.com/rook/rook
- **드라이버 이름**: `rook-ceph.rbd.csi.ceph.com` (블록), `rook-ceph.cephfs.csi.ceph.com` (파일)
- **지원 프로토콜**: Ceph RBD (블록), CephFS (파일), S3 (오브젝트)

### 4.2 주요 특징

| 기능 | RBD | CephFS |
|------|-----|--------|
| 동적 프로비저닝 | ✅ | ✅ |
| ReadWriteOnce | ✅ | ✅ |
| ReadWriteMany | ❌ | ✅ |
| VolumeSnapshot | ✅ | ✅ |
| 볼륨 확장 | ✅ | ✅ |
| 오프사이트 복제 | ✅ (mirroring) | ✅ |
| 자가 치유 | ✅ | ✅ |

### 4.3 설치

```bash
# Rook-Ceph Operator 설치 (Helm)
helm repo add rook-release https://charts.rook.io/release
helm repo update

# Operator 설치
helm install rook-ceph rook-release/rook-ceph \
  --namespace rook-ceph \
  --create-namespace

# Ceph 클러스터 생성 (CephCluster CRD)
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/cluster.yaml

# 상태 확인 (모든 OSD가 Running이어야 함)
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph
```

### 4.4 StorageClass 예제

```yaml
# Ceph RBD (블록 스토리지)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph          # Rook 네임스페이스
  pool: replicapool             # Ceph 풀 이름
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
mountOptions:
  - discard
---
# CephFS (파일 스토리지, RWX 지원)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: myfs
  pool: myfs-replicated
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
reclaimPolicy: Delete
allowVolumeExpansion: true
```

---

## 5. NFS Subdir External Provisioner

### 5.1 개요

기존 NFS 서버를 Kubernetes 동적 프로비저닝에 활용하는 간단한 프로비저너입니다.
엄밀히는 CSI 드라이버가 아닌 External Provisioner이지만 실무에서 많이 사용됩니다.

- **GitHub**: https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
- **드라이버 이름**: `cluster.local/nfs-subdir-external-provisioner`
- **특징**: 기존 NFS 서버의 서브디렉토리를 PV로 사용 (별도 NFS 서버 필요)

### 5.2 설치

```bash
# Helm으로 설치
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
helm repo update

helm install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=192.168.1.100 \
  --set nfs.path=/exports/k8s \
  --set storageClass.defaultClass=true \
  --namespace nfs-provisioner \
  --create-namespace
```

### 5.3 StorageClass 예제

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: cluster.local/nfs-subdir-external-provisioner
parameters:
  pathPattern: "${.PVC.namespace}/${.PVC.name}"  # 서브디렉토리 패턴
  onDelete: retain       # PVC 삭제 시 디렉토리 보존 (또는 delete)
reclaimPolicy: Retain
allowVolumeExpansion: false  # 서브디렉토리 방식은 확장 미지원
volumeBindingMode: Immediate
```

### 5.4 사용 예제

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc-demo
  namespace: default
spec:
  accessModes:
    - ReadWriteMany          # NFS는 RWX 지원
  resources:
    requests:
      storage: 5Gi           # NFS는 실제 용량 제한 없음 (논리적 크기만 기록)
  storageClassName: nfs-sc
```

---

## 6. 기타 주목할 CSI 드라이버

| 드라이버 | 사용 환경 | 특징 |
|----------|-----------|------|
| **Longhorn** (Rancher) | 온프레미스 | K8s 네이티브 분산 블록 스토리지, 자동 복제 |
| **OpenEBS** | 온프레미스 | 마이크로서비스 스토리지, Mayastor(NVMe) 지원 |
| **Portworx** (Pure Storage) | 엔터프라이즈 | 멀티클라우드 스토리지, 데이터 마이그레이션 |
| **HPE CSI Driver** | 엔터프라이즈 | Nimble/Alletra/Primera 지원 |
| **Pure Service Orchestrator** | 엔터프라이즈 | FlashBlade/FlashArray 지원 |
| **Dell CSI Drivers** | 엔터프라이즈 | PowerStore/PowerMax/Unity XT 지원 |
| **Hitachi CSI Driver** | 엔터프라이즈 | VSP 시리즈 지원 |
