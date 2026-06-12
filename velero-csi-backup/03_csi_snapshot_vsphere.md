# 03. vSphere CSI 스냅샷

## CSI Snapshot이란?

CSI Snapshot은 CSI 드라이버가 지원하는 스토리지 볼륨의 **시점 복사(point-in-time copy)** 기능입니다.

Kubernetes에서는 다음 리소스로 다룹니다.

- `VolumeSnapshot`
- `VolumeSnapshotContent`
- `VolumeSnapshotClass`

---

## vSphere CSI 중심으로 보는 이유

vSphere 환경에서는 vSphere CSI Driver가 공식적으로 CSI 기반 영구 스토리지를 제공하므로,
백업과 복구를 설계할 때 가장 자연스럽게 스냅샷 기능을 붙일 수 있습니다.

주요 장점:
- vSphere 관리 체계와 연동이 쉽다
- 블록 볼륨(VMDK) 기반 스냅샷 운영이 가능하다
- Stateful workload 복구에 잘 맞는다

---

## vSphere CSI에서 스냅샷이 동작하는 흐름

```text
PVC
  ↓
VolumeSnapshot 생성
  ↓
VolumeSnapshotClass가 vSphere CSI 드라이버 사용
  ↓
vCenter / datastore 레벨에서 스냅샷 생성
  ↓
필요 시 새 PVC로 복원 또는 데이터 복사
```

---

## 필수 구성 요소

- vSphere CSI Driver
- snapshot-controller
- VolumeSnapshot CRD
- VolumeSnapshotClass

---

## VolumeSnapshotClass 예시

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: vsphere-snapshot-class
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: csi.vsphere.vmware.com
deletionPolicy: Delete
```

---

## VolumeSnapshot 예시

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mysql-snap-20260613
  namespace: prod
spec:
  volumeSnapshotClassName: vsphere-snapshot-class
  source:
    persistentVolumeClaimName: mysql-pvc
```

---

## 스냅샷에서 PVC 복원

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc-restore
  namespace: prod
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: vsphere-sc-standard
  dataSource:
    name: mysql-snap-20260613
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

---

## 스냅샷의 특징

### 장점
- 빠르다
- 복구가 간단하다
- PV 전체 복사보다 효율적일 수 있다
- 장애 직전 시점으로 되돌리기 좋다

### 한계
- 애플리케이션 일관성은 자동 보장되지 않을 수 있다
- 스냅샷 보존 정책이 없으면 스토리지 사용량이 늘어난다
- 스냅샷 기능은 CSI 드라이버 지원 여부에 의존한다

---

## vSphere CSI에서 특히 중요한 점

- 스냅샷은 보통 **crash-consistent** 수준으로 이해하는 것이 안전하다
- DB 같은 서비스는 필요하면 pre/post hook 또는 flush/quiesce 전략을 추가한다
- vSphere 정책/데이터스토어 여유 공간도 같이 관리해야 한다

---

## 스냅샷이 잘 맞는 경우

- StatefulSet 데이터
- 짧은 주기의 롤백 지점 확보
- 장애 발생 전 빠른 복구
- 테스트 환경 복제

---

## 스냅샷이 부족한 경우

- 클러스터 외부로 장기 백업을 남겨야 하는 경우
- 매우 긴 보관 주기가 필요한 경우
- 스토리지 자체 장애 대비가 필요한 경우

이럴 때는 Velero 오브젝트 백업과 함께 써야 합니다.
