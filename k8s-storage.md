# Kubernetes 스토리지 심화 교육

> Kubernetes에서 **데이터를 영구적으로 저장하고 관리하는 방법**을 깊이 있게 다룹니다.
> PV, PVC, StorageClass, StatefulSet, CSI, vSphere CSI까지 스토리지의 전체 그림을 이해하는 것을 목표로 합니다.

---

## 목차

1. [왜 영구 스토리지가 필요한가?](#1-왜-영구-스토리지가-필요한가)
2. [Volume 기초](#2-volume-기초)
3. [PersistentVolume (PV)](#3-persistentvolume-pv)
4. [PersistentVolumeClaim (PVC)](#4-persistentvolumeclaim-pvc)
5. [PV와 PVC의 라이프사이클](#5-pv와-pvc의-라이프사이클)
6. [StorageClass와 동적 프로비저닝](#6-storageclass와-동적-프로비저닝)
7. [CSI (Container Storage Interface)](#7-csi-container-storage-interface)
8. [vSphere CSI Driver](#8-vsphere-csi-driver)
9. [StatefulSet과 스토리지](#9-statefulset과-스토리지)
10. [스토리지 트러블슈팅](#10-스토리지-트러블슈팅)
11. [실습: 스토리지 동작 확인](#11-실습-스토리지-동작-확인)
12. [정리 및 핵심 요약](#12-정리-및-핵심-요약)

---

## 1. 왜 영구 스토리지가 필요한가?

### 한 문장 정의

> Kubernetes의 Pod는 본질적으로 **일시적(Ephemeral)**이기 때문에, Pod가 삭제되거나 재시작되면 내부 데이터가 모두 사라집니다. **영구 스토리지**는 Pod의 생명주기와 무관하게 데이터를 보존합니다.

### 비유로 이해하기

```
┌─────────────────────────────────────────────────────────────┐
│                  호텔 vs 자기 집 비유                           │
│                                                             │
│   Pod의 기본 스토리지 = 호텔 방                                │
│   ┌────────────────┐                                        │
│   │   호텔 방       │  체크아웃하면 방의 모든 짐이 사라짐!       │
│   │  (Container    │  다시 체크인하면 빈 방을 받음              │
│   │   Filesystem)  │                                        │
│   └────────────────┘                                        │
│                                                             │
│   PersistentVolume = 자기 집 창고                             │
│   ┌────────────────┐                                        │
│   │   창고          │  호텔을 옮겨도 창고의 짐은 그대로!        │
│   │  (Persistent   │  언제든 다시 꺼내 쓸 수 있음              │
│   │   Volume)      │                                        │
│   └────────────────┘                                        │
│                                                             │
│   Pod가 죽어도 → PV의 데이터는 살아있음!                       │
└─────────────────────────────────────────────────────────────┘
```

### 스토리지 없이 생기는 문제

```
┌─────────────────────────────────────────────────────────────┐
│          영구 스토리지가 없을 때 발생하는 재앙                    │
│                                                             │
│  시나리오: MySQL Pod에 중요 데이터 저장 중                      │
│                                                             │
│  ┌──────────────┐                                           │
│  │  MySQL Pod   │  데이터: 주문 10,000건                     │
│  │  (Running)   │  (/var/lib/mysql에 저장)                   │
│  └──────┬───────┘                                           │
│         │                                                   │
│         │  💥 Pod 크래시 또는 노드 장애 발생!                   │
│         ▼                                                   │
│  ┌──────────────┐                                           │
│  │  MySQL Pod   │  데이터: 0건  ← 😱 전부 사라짐!            │
│  │  (새로 생성)  │  빈 데이터베이스로 시작                      │
│  └──────────────┘                                           │
│                                                             │
│  PV 사용 시:                                                  │
│  ┌──────────────┐     ┌──────────────┐                       │
│  │  MySQL Pod   │ ──▶ │     PV       │  데이터: 주문 10,000건 │
│  │  (Running)   │     │  (외부 디스크) │                       │
│  └──────┬───────┘     └──────┬───────┘                       │
│         │ 💥 크래시!          │ 데이터 유지!                    │
│         ▼                    │                               │
│  ┌──────────────┐            │                               │
│  │  MySQL Pod   │ ──────────▶│  데이터: 주문 10,000건 ✅       │
│  │  (새로 생성)  │            │  아무것도 안 잃음!               │
│  └──────────────┘            └──────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Volume 기초

### Volume 유형 분류

```
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes Volume 유형 분류                       │
│                                                             │
│  ┌─── 임시(Ephemeral) Volume ───────────────────────────┐   │
│  │                                                       │   │
│  │  emptyDir     : Pod 수명과 함께, Pod 삭제 시 소멸       │   │
│  │  configMap    : ConfigMap 데이터를 파일로 마운트          │   │
│  │  secret       : Secret 데이터를 파일로 마운트             │   │
│  │  downwardAPI  : Pod/Container 메타데이터를 파일로 노출    │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── 영구(Persistent) Volume ──────────────────────────┐   │
│  │                                                       │   │
│  │  hostPath     : 노드의 로컬 디스크 (단일 노드만)         │   │
│  │  nfs          : NFS 공유 스토리지                       │   │
│  │  iscsi        : iSCSI 블록 스토리지                     │   │
│  │  cephfs       : Ceph 파일시스템                         │   │
│  │  vsphereVolume: vSphere VMDK (deprecated → CSI 사용)  │   │
│  │  awsEBS       : AWS EBS (deprecated → CSI 사용)       │   │
│  │  gcePD        : GCP Persistent Disk (deprecated)      │   │
│  │  csi          : CSI 드라이버 (권장, 표준 방식)           │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  트렌드: 인트리(in-tree) 플러그인 → CSI(out-of-tree)로 전환   │
└─────────────────────────────────────────────────────────────┘
```

### emptyDir — 가장 기본적인 Volume

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-demo
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo 'Hello' > /data/message.txt && sleep 3600"]
    volumeMounts:
    - name: shared-data
      mountPath: /data
  - name: reader
    image: busybox
    command: ["sh", "-c", "cat /data/message.txt && sleep 3600"]
    volumeMounts:
    - name: shared-data
      mountPath: /data
  volumes:
  - name: shared-data
    emptyDir: {}             # Pod 시작 시 빈 디렉터리 생성
```

```
┌─── emptyDir 동작 ────────────────────────────────────────┐
│                                                          │
│  ┌──────────── Pod ────────────────┐                     │
│  │                                 │                     │
│  │  ┌─────────┐   ┌─────────┐     │                     │
│  │  │ writer  │   │ reader  │     │                     │
│  │  │ /data ──┼───┼── /data │     │  같은 볼륨 공유      │
│  │  └─────────┘   └─────────┘     │                     │
│  │        └──── emptyDir ────┘     │                     │
│  └─────────────────────────────────┘                     │
│                                                          │
│  ✅ 같은 Pod 내 컨테이너 간 파일 공유                       │
│  ✅ 임시 캐시, 중간 처리 결과 저장에 적합                    │
│  ❌ Pod 삭제 시 데이터 소멸                                 │
│  ❌ 다른 Pod와 공유 불가                                    │
└──────────────────────────────────────────────────────────┘
```

### hostPath — 노드 로컬 디스크

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-demo
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: host-logs
      mountPath: /var/log/nginx
  volumes:
  - name: host-logs
    hostPath:
      path: /var/log/app-logs    # 노드의 실제 경로
      type: DirectoryOrCreate    # 없으면 자동 생성
```

```
┌─── hostPath 주의사항 ────────────────────────────────────┐
│                                                          │
│  ⚠️ hostPath는 대부분의 경우 사용하지 말아야 합니다!         │
│                                                          │
│  문제 1: 노드 종속                                        │
│  Pod가 다른 노드로 이동하면 데이터에 접근 불가               │
│                                                          │
│  문제 2: 보안 위험                                        │
│  노드 파일시스템에 직접 접근 → 잘못하면 시스템 파일 손상     │
│                                                          │
│  사용해도 되는 경우:                                       │
│  ├── DaemonSet의 로그 수집 에이전트 (Fluent Bit 등)        │
│  ├── 노드 모니터링 에이전트                                │
│  └── 단일 노드 테스트/개발 환경                             │
└──────────────────────────────────────────────────────────┘
```

---

## 3. PersistentVolume (PV)

### PV란?

> **PersistentVolume(PV)**은 클러스터 관리자가 프로비저닝한 **스토리지 자원**입니다. 노드가 클러스터의 컴퓨팅 자원이듯, PV는 클러스터의 스토리지 자원입니다.

```
┌─────────────────────────────────────────────────────────────┐
│           PV = 클러스터 수준의 스토리지 자원                    │
│                                                             │
│   Node = 컴퓨팅 자원          PV = 스토리지 자원              │
│   ┌────────────┐             ┌────────────┐                  │
│   │ CPU: 4코어  │             │ 용량: 10Gi  │                  │
│   │ RAM: 16GB  │             │ 타입: SSD   │                  │
│   │            │             │ 모드: RWO   │                  │
│   └────────────┘             └────────────┘                  │
│                                                             │
│   Pod가 Node를 사용          Pod가 PV를 사용                   │
│   (Scheduler가 배치)         (PVC를 통해 요청)                 │
│                                                             │
│   핵심: PV는 Pod와 독립적인 생명주기를 가짐!                    │
│         Pod가 삭제되어도 PV와 데이터는 유지됨                    │
└─────────────────────────────────────────────────────────────┘
```

### PV YAML 예시

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv-10gi
spec:
  capacity:
    storage: 10Gi                    # 스토리지 용량
  accessModes:
  - ReadWriteOnce                    # 접근 모드
  persistentVolumeReclaimPolicy: Retain   # 반환 정책
  storageClassName: manual           # StorageClass 이름
  hostPath:                          # 스토리지 백엔드 (예시)
    path: /mnt/data
```

### Access Modes (접근 모드)

```
┌─────────────────────────────────────────────────────────────┐
│                  PV Access Modes                             │
│                                                             │
│  ┌─── ReadWriteOnce (RWO) ──────────────────────────────┐   │
│  │                                                       │   │
│  │  하나의 노드에서만 읽기/쓰기 가능                        │   │
│  │                                                       │   │
│  │  Node 1: ✅ 읽기/쓰기                                  │   │
│  │  Node 2: ❌ 접근 불가                                   │   │
│  │                                                       │   │
│  │  사용 사례: 단일 Pod DB (MySQL, PostgreSQL)             │   │
│  │  지원: 대부분의 블록 스토리지 (EBS, vSphere VMDK 등)     │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── ReadOnlyMany (ROX) ───────────────────────────────┐   │
│  │                                                       │   │
│  │  여러 노드에서 읽기 전용으로 접근 가능                    │   │
│  │                                                       │   │
│  │  Node 1: ✅ 읽기 전용                                   │   │
│  │  Node 2: ✅ 읽기 전용                                   │   │
│  │  Node 3: ✅ 읽기 전용                                   │   │
│  │                                                       │   │
│  │  사용 사례: 정적 콘텐츠 배포, ML 모델 파일 공유           │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── ReadWriteMany (RWX) ──────────────────────────────┐   │
│  │                                                       │   │
│  │  여러 노드에서 읽기/쓰기 가능                            │   │
│  │                                                       │   │
│  │  Node 1: ✅ 읽기/쓰기                                   │   │
│  │  Node 2: ✅ 읽기/쓰기                                   │   │
│  │  Node 3: ✅ 읽기/쓰기                                   │   │
│  │                                                       │   │
│  │  사용 사례: 공유 파일 스토리지, CMS 업로드 디렉터리        │   │
│  │  지원: NFS, CephFS, Azure Files 등 (파일 스토리지)      │   │
│  │  ⚠️ 블록 스토리지(EBS, vSphere)는 RWX 미지원!           │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── ReadWriteOncePod (RWOP) ──────────────────────────┐   │
│  │                                                       │   │
│  │  K8s 1.27+: 단 하나의 Pod에서만 읽기/쓰기 가능           │   │
│  │  (RWO보다 더 엄격 — RWO는 같은 노드의 다른 Pod도 가능)    │   │
│  │                                                       │   │
│  │  사용 사례: 데이터 무결성이 극도로 중요한 경우             │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Reclaim Policy (반환 정책)

```
┌─────────────────────────────────────────────────────────────┐
│            PVC 삭제 후 PV 데이터 처리 방식                     │
│                                                             │
│  ┌─── Retain (보존) ────────────────────────────────────┐   │
│  │                                                       │   │
│  │  PVC 삭제 → PV는 Released 상태                         │   │
│  │  데이터 유지, 관리자가 수동으로 정리                      │   │
│  │                                                       │   │
│  │  ✅ 가장 안전 (데이터 유실 없음)                         │   │
│  │  ❌ 관리자가 직접 PV 재사용 또는 삭제해야 함              │   │
│  │                                                       │   │
│  │  적합: 프로덕션 DB, 중요 데이터                          │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── Delete (삭제) ────────────────────────────────────┐   │
│  │                                                       │   │
│  │  PVC 삭제 → PV + 실제 스토리지 볼륨 모두 삭제            │   │
│  │                                                       │   │
│  │  ✅ 자동 정리, 관리 편리                                 │   │
│  │  ❌ 데이터 영구 삭제! 복구 불가!                          │   │
│  │                                                       │   │
│  │  적합: 임시 테스트, 동적 프로비저닝 기본값                 │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── Recycle (재활용) ─ DEPRECATED ────────────────────┐   │
│  │                                                       │   │
│  │  PVC 삭제 → 데이터만 삭제(rm -rf) → PV 재사용 가능       │   │
│  │  ⚠️ 더 이상 사용하지 않음! 동적 프로비저닝 사용 권장       │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. PersistentVolumeClaim (PVC)

### PVC란?

> **PersistentVolumeClaim(PVC)**은 사용자(개발자)가 스토리지를 **요청하는 오브젝트**입니다. PV가 "스토리지 자원"이라면, PVC는 "스토리지 주문서"입니다.

```
┌─────────────────────────────────────────────────────────────┐
│            PV/PVC 관계 = 공급/수요 모델                       │
│                                                             │
│   관리자(Admin)                     개발자(Developer)         │
│                                                             │
│   "스토리지를 준비해놓겠다"          "스토리지를 10Gi 주세요"    │
│                                                             │
│   ┌──────────────┐                ┌──────────────┐          │
│   │     PV       │ ◀── Binding ──▶│    PVC       │          │
│   │              │                │              │          │
│   │ capacity:    │                │ request:     │          │
│   │   20Gi       │                │   10Gi       │          │
│   │ accessMode:  │                │ accessMode:  │          │
│   │   RWO        │                │   RWO        │          │
│   │ storageClass:│                │ storageClass:│          │
│   │   fast-ssd   │                │   fast-ssd   │          │
│   └──────────────┘                └──────┬───────┘          │
│                                          │                  │
│                                    ┌─────┴─────┐            │
│                                    │    Pod    │            │
│                                    │ volume:  │            │
│                                    │  pvc:    │            │
│                                    │  my-pvc  │            │
│                                    └──────────┘            │
│                                                             │
│   역할 분리:                                                 │
│   관리자 = 스토리지 인프라 관리 (PV, StorageClass)             │
│   개발자 = 필요한 스토리지 요청 (PVC) → Pod에 마운트           │
└─────────────────────────────────────────────────────────────┘
```

### PVC YAML 예시

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
  - ReadWriteOnce               # 접근 모드
  resources:
    requests:
      storage: 10Gi             # 요청 용량
  storageClassName: fast-ssd    # StorageClass 지정 (동적 프로비저닝)
```

### Pod에서 PVC 사용

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: mysql
spec:
  containers:
  - name: mysql
    image: mysql:8.0
    env:
    - name: MYSQL_ROOT_PASSWORD
      value: "password123"
    volumeMounts:
    - name: mysql-storage
      mountPath: /var/lib/mysql       # MySQL 데이터 디렉터리
  volumes:
  - name: mysql-storage
    persistentVolumeClaim:
      claimName: my-pvc              # PVC 이름 참조
```

---

## 5. PV와 PVC의 라이프사이클

### 전체 흐름

```
┌─────────────────────────────────────────────────────────────┐
│               PV/PVC 라이프사이클                              │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  1단계: 프로비저닝 (Provisioning)                      │    │
│  │                                                      │    │
│  │  정적(Static):   관리자가 PV를 미리 생성                │    │
│  │  동적(Dynamic):  PVC 생성 시 StorageClass가 자동 생성   │    │
│  └──────────────────────────┬───────────────────────────┘    │
│                             │                               │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  2단계: 바인딩 (Binding)                               │    │
│  │                                                      │    │
│  │  PVC ─── 조건 매칭 ──▶ PV                              │    │
│  │  (용량, AccessMode, StorageClass가 맞는 PV를 찾아 연결) │    │
│  │                                                      │    │
│  │  PV: Available → Bound                                │    │
│  │  PVC: Pending → Bound                                 │    │
│  └──────────────────────────┬───────────────────────────┘    │
│                             │                               │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  3단계: 사용 (Using)                                   │    │
│  │                                                      │    │
│  │  Pod가 PVC를 Volume으로 마운트하여 데이터 읽기/쓰기      │    │
│  │  PV 상태: Bound (Pod에서 사용 중)                       │    │
│  └──────────────────────────┬───────────────────────────┘    │
│                             │                               │
│                             ▼                               │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  4단계: 반환 (Reclaiming)                              │    │
│  │                                                      │    │
│  │  PVC 삭제 → Reclaim Policy에 따라 처리                  │    │
│  │                                                      │    │
│  │  Retain → PV: Released (데이터 유지, 수동 정리)         │    │
│  │  Delete → PV + 백엔드 볼륨 자동 삭제                    │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### PV/PVC 상태 전이

```
┌─── PV 상태 ──────────────────────────────────────────────┐
│                                                          │
│  Available ──▶ Bound ──▶ Released ──▶ (재사용 또는 삭제)  │
│  (사용 가능)   (PVC에   (PVC 삭제됨,                      │
│               바인딩됨)  데이터 남아있음)                   │
│                                                          │
│  Available ──▶ Bound ──▶ (PV 자동 삭제)                   │
│               (Delete 정책일 때)                          │
│                                                          │
├─── PVC 상태 ─────────────────────────────────────────────┤
│                                                          │
│  Pending ──▶ Bound ──▶ (삭제)                             │
│  (매칭 PV   (PV에                                        │
│   탐색 중)   바인딩됨)                                     │
│                                                          │
│  Pending이 지속되는 경우:                                  │
│  ├── 조건에 맞는 PV가 없음                                │
│  ├── StorageClass가 잘못됨                                │
│  └── 동적 프로비저닝 실패 (CSI 드라이버 문제)               │
└──────────────────────────────────────────────────────────┘
```

### 정적 vs 동적 프로비저닝

```
┌─── 정적 프로비저닝 (Static) ─────────────────────────────┐
│                                                          │
│  관리자                    개발자                         │
│                                                          │
│  1. PV 미리 생성           2. PVC 생성                    │
│  ┌──────────┐             ┌──────────┐                   │
│  │ PV-10Gi  │ ◀─ Binding ─│ PVC-10Gi │                   │
│  │ PV-20Gi  │             └──────────┘                   │
│  │ PV-50Gi  │                                            │
│  └──────────┘                                            │
│                                                          │
│  장점: 스토리지를 미리 검수하고 준비                        │
│  단점: 관리자가 매번 PV를 수동 생성해야 함 → 비효율적       │
│                                                          │
├─── 동적 프로비저닝 (Dynamic) ────────────────────────────┤
│                                                          │
│  관리자                    개발자                         │
│                                                          │
│  1. StorageClass 생성       2. PVC 생성 (StorageClass 지정)│
│  ┌──────────────┐          ┌──────────┐                   │
│  │ StorageClass │          │ PVC-10Gi │                   │
│  │ "fast-ssd"   │ ──자동──▶│          │                   │
│  │ provisioner: │  PV 생성  └──────────┘                   │
│  │ csi.vsphere  │                                        │
│  └──────────────┘                                        │
│                                                          │
│  장점: PV 자동 생성, 관리자 개입 최소화                     │
│  단점: StorageClass 설정이 올바른지 확인 필요               │
│                                                          │
│  → 운영 환경에서는 동적 프로비저닝이 표준!                   │
└──────────────────────────────────────────────────────────┘
```

---

## 6. StorageClass와 동적 프로비저닝

### StorageClass란?

> **StorageClass**는 스토리지의 "등급(Class)"을 정의하는 오브젝트입니다. 어떤 프로비저너를 사용하고, 어떤 파라미터로 볼륨을 생성할지 정의합니다.

```
┌─────────────────────────────────────────────────────────────┐
│           StorageClass = 스토리지 메뉴판                      │
│                                                             │
│   ┌─────────────────────────────────────────────────┐       │
│   │             스토리지 메뉴판                        │       │
│   │                                                 │       │
│   │  ┌─── fast-ssd ──────────────────────────┐      │       │
│   │  │ SSD, 고성능, IOPS 3000                 │      │       │
│   │  │ 프로비저너: csi.vsphere.vmware.com     │      │       │
│   │  │ 용도: 데이터베이스                      │      │       │
│   │  └────────────────────────────────────────┘      │       │
│   │                                                 │       │
│   │  ┌─── standard ──────────────────────────┐      │       │
│   │  │ HDD, 범용, 비용 효율적                  │      │       │
│   │  │ 프로비저너: csi.vsphere.vmware.com     │      │       │
│   │  │ 용도: 일반 애플리케이션                  │      │       │
│   │  └────────────────────────────────────────┘      │       │
│   │                                                 │       │
│   │  ┌─── nfs-shared ────────────────────────┐      │       │
│   │  │ NFS, RWX 지원, 공유 파일 스토리지       │      │       │
│   │  │ 프로비저너: nfs.csi.k8s.io            │      │       │
│   │  │ 용도: 여러 Pod가 공유하는 파일           │      │       │
│   │  └────────────────────────────────────────┘      │       │
│   └─────────────────────────────────────────────────┘       │
│                                                             │
│   개발자: "fast-ssd로 10Gi 주세요" (PVC 생성)                │
│   → StorageClass가 자동으로 SSD PV 생성!                      │
└─────────────────────────────────────────────────────────────┘
```

### StorageClass YAML 예시

```yaml
# 예시 1: vSphere CSI StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"  # 기본 StorageClass
provisioner: csi.vsphere.vmware.com      # CSI 드라이버 이름
parameters:
  storagepolicyname: "SSD-Policy"        # vSphere 스토리지 정책
  datastoreurl: "ds:///vmfs/volumes/xxx" # 데이터스토어 URL (선택)
reclaimPolicy: Delete                    # PVC 삭제 시 PV도 삭제
allowVolumeExpansion: true               # 볼륨 확장 허용
volumeBindingMode: Immediate             # PVC 생성 즉시 바인딩
---
# 예시 2: AWS EBS CSI StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3                              # EBS 볼륨 타입
  iops: "3000"
  throughput: "125"
  encrypted: "true"
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer  # Pod가 스케줄될 때 바인딩
---
# 예시 3: NFS CSI StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-shared
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.1.100
  share: /exported/path
reclaimPolicy: Delete
mountOptions:
- hard
- nfsvers=4.1
```

### volumeBindingMode

```
┌─────────────────────────────────────────────────────────────┐
│           volumeBindingMode 비교                              │
│                                                             │
│  ┌─── Immediate (즉시) ────────────────────────────────┐    │
│  │                                                      │    │
│  │  PVC 생성 → 즉시 PV 프로비저닝 → 바인딩               │    │
│  │                                                      │    │
│  │  문제: Pod가 아직 스케줄되지 않았으므로                  │    │
│  │  PV가 Pod와 다른 AZ/노드에 생성될 수 있음!              │    │
│  │                                                      │    │
│  │  PV: Zone-A에 생성됨                                   │    │
│  │  Pod: Zone-B에 스케줄됨  → ❌ 마운트 실패!              │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── WaitForFirstConsumer (대기) ─────────────────────┐    │
│  │                                                      │    │
│  │  PVC 생성 → 대기 → Pod 스케줄 시점에 PV 프로비저닝      │    │
│  │                                                      │    │
│  │  Pod: Zone-B에 스케줄 → PV도 Zone-B에 생성             │    │
│  │  → ✅ 항상 같은 위치에 PV 생성!                         │    │
│  │                                                      │    │
│  │  권장: 토폴로지가 중요한 환경 (멀티 AZ, 멀티 노드)      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 볼륨 확장 (Volume Expansion)

```bash
# StorageClass에서 allowVolumeExpansion: true 필수

# PVC 용량 확장 (10Gi → 20Gi)
kubectl patch pvc my-pvc -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 또는 kubectl edit
kubectl edit pvc my-pvc
# spec.resources.requests.storage 값을 수정

# 확장 상태 확인
kubectl get pvc my-pvc
kubectl describe pvc my-pvc | grep -A 5 Conditions

# ⚠️ 주의사항:
# - 축소(Shrink)는 불가능! 확장만 가능
# - 일부 CSI 드라이버는 온라인 확장 지원 (Pod 재시작 불필요)
# - 일부는 오프라인 확장만 지원 (Pod 삭제 후 재생성 필요)
```

---

## 7. CSI (Container Storage Interface)

### CSI가 왜 필요한가?

```
┌─────────────────────────────────────────────────────────────┐
│              CSI 이전의 문제점 (In-Tree 방식)                  │
│                                                             │
│  Kubernetes 코어                                              │
│  ┌────────────────────────────────────────────┐              │
│  │                                            │              │
│  │  K8s 코어 코드 안에 스토리지 드라이버 내장      │              │
│  │                                            │              │
│  │  ├── AWS EBS 드라이버                       │              │
│  │  ├── GCE PD 드라이버                        │              │
│  │  ├── Azure Disk 드라이버                    │              │
│  │  ├── vSphere 드라이버                       │              │
│  │  ├── Ceph 드라이버                          │              │
│  │  └── ... 수십 개의 드라이버                   │              │
│  │                                            │              │
│  └────────────────────────────────────────────┘              │
│                                                             │
│  문제점:                                                      │
│  ❌ 새 스토리지 추가 → K8s 코어 코드 수정 필요                  │
│  ❌ 드라이버 버그 → K8s 전체 릴리스 기다려야 수정               │
│  ❌ K8s 바이너리가 점점 비대해짐                                │
│  ❌ 스토리지 벤더가 K8s 릴리스 주기에 종속                      │
│                                                             │
│  ─────────────────────────────────────────────               │
│                                                             │
│  CSI 이후 (Out-of-Tree 방식):                                 │
│                                                             │
│  Kubernetes 코어                  CSI 드라이버 (별도 배포)      │
│  ┌───────────────┐              ┌──────────────────┐         │
│  │               │   CSI 표준   │  AWS EBS CSI     │         │
│  │  K8s 코어     │ ◀═ 인터페 ═▶ │  vSphere CSI     │         │
│  │  (가벼움!)    │   이스       │  Ceph CSI        │         │
│  │               │              │  NetApp CSI      │         │
│  └───────────────┘              └──────────────────┘         │
│                                                             │
│  ✅ K8s와 독립적으로 개발/배포/업데이트                         │
│  ✅ 어떤 스토리지든 CSI 표준만 따르면 연동 가능                  │
│  ✅ K8s 코어는 가볍게 유지                                     │
└─────────────────────────────────────────────────────────────┘
```

### CSI 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                  CSI 드라이버 구성요소                          │
│                                                             │
│  ┌─── Controller Plugin (Deployment) ──────────────────┐    │
│  │                                                      │    │
│  │  ┌────────────────────┐  ┌────────────────────┐      │    │
│  │  │ CSI Controller     │  │ External            │      │    │
│  │  │ (벤더 제공)         │  │ Provisioner         │      │    │
│  │  │                    │  │ (sidecar)           │      │    │
│  │  │ 볼륨 생성/삭제      │  │                    │      │    │
│  │  │ 스냅샷 생성        │  │ PVC 감시 → 볼륨     │      │    │
│  │  │ 볼륨 확장          │  │ 생성 요청           │      │    │
│  │  └────────────────────┘  └────────────────────┘      │    │
│  │                                                      │    │
│  │  ┌────────────────────┐  ┌────────────────────┐      │    │
│  │  │ External           │  │ External            │      │    │
│  │  │ Attacher           │  │ Snapshotter         │      │    │
│  │  │ (sidecar)          │  │ (sidecar)           │      │    │
│  │  │                    │  │                    │      │    │
│  │  │ 볼륨을 노드에      │  │ VolumeSnapshot      │      │    │
│  │  │ 연결(Attach)       │  │ 관리                │      │    │
│  │  └────────────────────┘  └────────────────────┘      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── Node Plugin (DaemonSet, 모든 노드에 배포) ──────┐     │
│  │                                                      │    │
│  │  ┌────────────────────┐  ┌────────────────────┐      │    │
│  │  │ CSI Node           │  │ Node Driver         │      │    │
│  │  │ (벤더 제공)         │  │ Registrar           │      │    │
│  │  │                    │  │ (sidecar)           │      │    │
│  │  │ 볼륨을 Pod에       │  │                    │      │    │
│  │  │ 마운트/언마운트     │  │ kubelet에 CSI       │      │    │
│  │  │                    │  │ 드라이버 등록        │      │    │
│  │  └────────────────────┘  └────────────────────┘      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### CSI 볼륨 생성 흐름

```
PVC 생성
   │
   ▼
┌─── External Provisioner (sidecar) ───────────────────────┐
│  PVC Watch → CSI Controller에 CreateVolume 요청           │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌─── CSI Controller Plugin ────────────────────────────────┐
│  스토리지 백엔드에 실제 볼륨 생성                            │
│  (예: vSphere에 VMDK 생성, AWS에 EBS 생성)                  │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌─── PV 자동 생성, PVC에 바인딩 ───────────────────────────┐
└──────────────────────────┬───────────────────────────────┘
                           │
Pod 스케줄링 → 노드에 배치   │
                           ▼
┌─── External Attacher (sidecar) ──────────────────────────┐
│  CSI Controller에 ControllerPublishVolume 요청             │
│  → 볼륨을 특정 노드에 연결 (Attach)                         │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
┌─── CSI Node Plugin (해당 노드) ──────────────────────────┐
│  NodeStageVolume: 볼륨을 노드에 스테이징 (포맷, 임시 마운트) │
│  NodePublishVolume: Pod 경로에 최종 마운트                   │
└──────────────────────────┬───────────────────────────────┘
                           │
                           ▼
                    Pod에서 볼륨 사용 가능!
```

### 주요 CSI 드라이버 목록

| CSI 드라이버 | 프로비저너 이름 | 스토리지 백엔드 |
|-------------|---------------|---------------|
| **vSphere CSI** | `csi.vsphere.vmware.com` | VMware vSphere VMDK |
| **AWS EBS CSI** | `ebs.csi.aws.com` | Amazon EBS |
| **GCE PD CSI** | `pd.csi.storage.gke.io` | Google Persistent Disk |
| **Azure Disk CSI** | `disk.csi.azure.com` | Azure Managed Disk |
| **NFS CSI** | `nfs.csi.k8s.io` | NFS 서버 |
| **Ceph RBD CSI** | `rbd.csi.ceph.com` | Ceph RBD |
| **NetApp Trident** | `csi.trident.netapp.io` | NetApp ONTAP/SolidFire |
| **Longhorn** | `driver.longhorn.io` | Longhorn 분산 스토리지 |
| **OpenEBS** | `cstor.csi.openebs.io` | OpenEBS |

---

## 8. vSphere CSI Driver

### vSphere CSI란?

> **vSphere CSI Driver**는 VMware vSphere 환경에서 Kubernetes Pod에 **VMDK(Virtual Machine Disk)를 동적으로 프로비저닝**하는 CSI 드라이버입니다. vSphere의 스토리지 정책(SPBM)과 통합됩니다.

```
┌─────────────────────────────────────────────────────────────┐
│              vSphere CSI 전체 구조                             │
│                                                             │
│  ┌─── Kubernetes Cluster ────────────────────────────┐      │
│  │                                                    │      │
│  │  PVC 생성 → StorageClass (csi.vsphere.vmware.com)  │      │
│  │                    │                                │      │
│  │                    ▼                                │      │
│  │  ┌─── vSphere CSI Controller ──────────────┐       │      │
│  │  │  (Deployment, Master 노드에서 실행)        │       │      │
│  │  │                                          │       │      │
│  │  │  vCenter API 호출 → VMDK 생성             │       │      │
│  │  └──────────────────┬───────────────────────┘       │      │
│  │                     │                               │      │
│  │                     ▼                               │      │
│  │  ┌─── vSphere CSI Node ────────────────────┐       │      │
│  │  │  (DaemonSet, 모든 노드에서 실행)           │       │      │
│  │  │                                          │       │      │
│  │  │  VMDK를 노드에 Attach → Pod에 Mount       │       │      │
│  │  └──────────────────────────────────────────┘       │      │
│  │                                                    │      │
│  └────────────────────────┬───────────────────────────┘      │
│                           │                                  │
│                           │ vCenter API                       │
│                           ▼                                  │
│  ┌─── vSphere 인프라 ─────────────────────────────────┐      │
│  │                                                    │      │
│  │  ┌──────────┐    ┌──────────┐    ┌──────────┐      │      │
│  │  │ vCenter  │    │Datastore │    │  SPBM    │      │      │
│  │  │          │    │(VMFS/    │    │ 정책     │      │      │
│  │  │ VMDK 관리│    │ vSAN/NFS)│    │          │      │      │
│  │  └──────────┘    └──────────┘    └──────────┘      │      │
│  │                                                    │      │
│  └────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### vSphere CSI 전제 조건

| 항목 | 요구사항 |
|------|---------|
| **vSphere 버전** | 6.7U3 이상 (7.0 이상 권장) |
| **ESXi 버전** | 6.7U3 이상 |
| **VM Hardware** | 버전 15 이상 |
| **disk.EnableUUID** | 모든 K8s 노드 VM에서 `TRUE` 설정 필수 |
| **VM 이름** | K8s 노드 이름과 vSphere VM 이름이 일치해야 함 |
| **vCenter 계정** | 데이터스토어 및 VM 관리 권한 필요 |

### disk.EnableUUID 설정

```
┌─────────────────────────────────────────────────────────────┐
│       disk.EnableUUID가 필요한 이유                            │
│                                                             │
│  CSI Node Plugin은 VMDK를 올바른 VM에 Attach하기 위해          │
│  각 VM의 디스크를 UUID로 식별합니다.                            │
│                                                             │
│  disk.EnableUUID = FALSE (기본값):                             │
│  → VM 내부에서 디스크 UUID를 볼 수 없음                        │
│  → CSI가 어떤 VMDK가 어떤 디바이스인지 식별 불가!               │
│                                                             │
│  disk.EnableUUID = TRUE:                                     │
│  → VM 내부에서 디스크 UUID 확인 가능                           │
│  → CSI가 정확한 VMDK 매핑 가능                                │
│                                                             │
│  설정 방법:                                                   │
│  vSphere Client → VM 설정 → VM Options                       │
│  → Advanced → Configuration Parameters                      │
│  → disk.EnableUUID = TRUE                                    │
│                                                             │
│  또는 govc CLI:                                               │
│  govc vm.change -vm '/DC/vm/k8s-node-1' \                   │
│    -e disk.enableUUID=TRUE                                  │
└─────────────────────────────────────────────────────────────┘
```

### vSphere CSI 설치 구성요소

```bash
# vSphere CSI 설치 후 확인
kubectl get pods -n vmware-system-csi

# 출력 예시:
# NAME                                     READY   STATUS    RESTARTS
# vsphere-csi-controller-xxx-yyy           7/7     Running   0
# vsphere-csi-node-aaaaa                   3/3     Running   0    (각 노드)
# vsphere-csi-node-bbbbb                   3/3     Running   0
# vsphere-csi-node-ccccc                   3/3     Running   0
```

| Pod | 역할 | 배포 방식 |
|-----|------|----------|
| **vsphere-csi-controller** | vCenter API로 VMDK 생성/삭제/확장, 볼륨 Attach/Detach | Deployment (1~3개) |
| **vsphere-csi-node** | 노드에서 VMDK Mount/Unmount, kubelet에 CSI 등록 | DaemonSet (모든 노드) |

### vSphere CSI StorageClass 예시

```yaml
# 기본 StorageClass (vSphere 스토리지 정책 기반)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsphere-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.vsphere.vmware.com
parameters:
  # 방법 1: 스토리지 정책(SPBM) 지정
  storagepolicyname: "kubernetes-storage-policy"

  # 방법 2: 데이터스토어 직접 지정
  # datastoreurl: "ds:///vmfs/volumes/vsan:xxxx/"
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
---
# vSAN용 고성능 StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: vsan-high-perf
provisioner: csi.vsphere.vmware.com
parameters:
  storagepolicyname: "vSAN-High-Performance"
  # vSAN 정책에서 스트라이프 수, FTT 등을 설정
reclaimPolicy: Retain              # 프로덕션에서는 Retain 권장
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

### vSphere CSI 스토리지 정책 (SPBM)

```
┌─────────────────────────────────────────────────────────────┐
│         vSphere SPBM (Storage Policy Based Management)      │
│                                                             │
│  vCenter에서 스토리지 정책을 정의하면                           │
│  K8s StorageClass의 parameters.storagepolicyname으로 참조      │
│                                                             │
│  ┌─── 정책 예시 ────────────────────────────────────────┐    │
│  │                                                      │    │
│  │  정책 이름: "kubernetes-storage-policy"                │    │
│  │                                                      │    │
│  │  규칙:                                                │    │
│  │  ├── 데이터스토어 호환성: vSAN / VMFS 선택             │    │
│  │  ├── 장애 허용(FTT): 1 (RAID-1 미러링)               │    │
│  │  ├── 스트라이프 수: 1                                  │    │
│  │  ├── 오브젝트 공간 예약: Thin Provisioning             │    │
│  │  └── 암호화: 사용                                     │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  PVC 생성 시:                                                 │
│  PVC(storageClassName: vsphere-sc)                           │
│  → StorageClass(storagepolicyname: kubernetes-storage-policy)│
│  → vCenter가 해당 정책에 맞는 데이터스토어에 VMDK 생성         │
└─────────────────────────────────────────────────────────────┘
```

### vSphere CSI 볼륨 생성 상세 흐름

```
개발자: PVC 생성 (storageClassName: vsphere-sc, 10Gi)
        │
        ▼
┌─── CSI Controller (vsphere-csi-controller) ──────────────┐
│                                                           │
│  1. External Provisioner가 PVC Watch로 감지                │
│  2. CSI Controller에 CreateVolume 호출                     │
│  3. CSI Controller → vCenter API 호출:                     │
│     └── SPBM 정책에 맞는 데이터스토어 선택                   │
│     └── VMDK 파일 생성 (10Gi, Thin Provisioning)            │
│     └── FCD (First Class Disk) ID 발급                      │
│  4. PV 자동 생성 → PVC에 바인딩                              │
│                                                           │
└──────────────────────────┬────────────────────────────────┘
                           │
Pod 스케줄링 → Worker-1 배치│
                           ▼
┌─── CSI Controller (Attach) ──────────────────────────────┐
│                                                           │
│  5. External Attacher가 VolumeAttachment Watch로 감지      │
│  6. CSI Controller → vCenter API:                          │
│     └── VMDK를 Worker-1 VM에 SCSI 디스크로 연결             │
│                                                           │
└──────────────────────────┬────────────────────────────────┘
                           │
                           ▼
┌─── CSI Node (Worker-1의 vsphere-csi-node) ───────────────┐
│                                                           │
│  7. NodeStageVolume: SCSI 디스크 포맷 (ext4/xfs)           │
│  8. NodePublishVolume: Pod의 컨테이너 경로에 bind mount     │
│     /var/lib/kubelet/pods/<pod-uid>/volumes/...             │
│                                                           │
└───────────────────────────────────────────────────────────┘
                           │
                           ▼
                    Pod에서 /var/lib/mysql 사용 가능!
```

---

## 9. StatefulSet과 스토리지

### StatefulSet이 필요한 이유

```
┌─────────────────────────────────────────────────────────────┐
│        Deployment vs StatefulSet 스토리지 차이                 │
│                                                             │
│  ┌─── Deployment ────────────────────────────────────┐      │
│  │                                                    │      │
│  │  모든 Pod가 같은 PVC를 공유 (또는 PV 없이 동작)       │      │
│  │                                                    │      │
│  │  Pod-1 ─┐                                          │      │
│  │  Pod-2 ─┼──▶ 하나의 PVC (공유)                     │      │
│  │  Pod-3 ─┘                                          │      │
│  │                                                    │      │
│  │  ❌ 각 Pod가 독립적인 데이터를 가질 수 없음             │      │
│  │  ❌ DB 같은 상태 저장 앱에는 부적합                     │      │
│  └────────────────────────────────────────────────────┘      │
│                                                             │
│  ┌─── StatefulSet ───────────────────────────────────┐      │
│  │                                                    │      │
│  │  각 Pod가 고유한 PVC를 가짐                          │      │
│  │                                                    │      │
│  │  mysql-0 ──▶ PVC: data-mysql-0 ──▶ PV-0 (10Gi)    │      │
│  │  mysql-1 ──▶ PVC: data-mysql-1 ──▶ PV-1 (10Gi)    │      │
│  │  mysql-2 ──▶ PVC: data-mysql-2 ──▶ PV-2 (10Gi)    │      │
│  │                                                    │      │
│  │  ✅ 각 Pod가 독립적인 데이터 보유                      │      │
│  │  ✅ Pod 재생성 시 같은 PVC에 다시 연결                  │      │
│  │  ✅ DB 클러스터 (MySQL, PostgreSQL, MongoDB 등)에 적합 │      │
│  └────────────────────────────────────────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### StatefulSet의 스토리지 특성

```
┌─────────────────────────────────────────────────────────────┐
│          StatefulSet 고유 특성                                 │
│                                                             │
│  1. 순서 보장 (Ordered)                                       │
│     mysql-0 생성 완료 → mysql-1 생성 → mysql-2 생성           │
│     삭제는 역순: mysql-2 → mysql-1 → mysql-0                 │
│                                                             │
│  2. 안정적인 네트워크 ID                                       │
│     Pod 이름이 항상 동일: mysql-0, mysql-1, mysql-2           │
│     Headless Service로 개별 Pod에 DNS 접근 가능:              │
│     mysql-0.mysql-headless.default.svc.cluster.local         │
│                                                             │
│  3. 고유 PVC (volumeClaimTemplates)                           │
│     각 Pod마다 독립적인 PVC 자동 생성                          │
│     Pod 삭제 후 재생성 시 같은 PVC에 재연결                    │
│                                                             │
│  4. PVC 보존                                                  │
│     StatefulSet 삭제 시 PVC는 자동 삭제되지 않음!              │
│     데이터 보호를 위해 수동 삭제 필요                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### StatefulSet + volumeClaimTemplates YAML

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
spec:
  clusterIP: None              # Headless Service (ClusterIP 없음)
  selector:
    app: mysql
  ports:
  - port: 3306
    name: mysql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless   # Headless Service 이름
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "password123"
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql     # MySQL 데이터 디렉터리

  # ★ 핵심: volumeClaimTemplates
  # 각 Pod마다 독립적인 PVC가 자동 생성됨
  volumeClaimTemplates:
  - metadata:
      name: data                        # PVC 이름 접두사
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd        # StorageClass 지정
      resources:
        requests:
          storage: 10Gi
```

```
위 YAML 적용 시 자동 생성되는 리소스:

Pod:  mysql-0, mysql-1, mysql-2
PVC:  data-mysql-0, data-mysql-1, data-mysql-2
PV:   pvc-xxxx-0, pvc-xxxx-1, pvc-xxxx-2  (동적 프로비저닝)

┌─── StatefulSet 시각화 ───────────────────────────────────┐
│                                                          │
│  mysql-headless (Headless Service)                        │
│     │                                                    │
│     ├── mysql-0.mysql-headless                           │
│     │      └── PVC: data-mysql-0 → PV (VMDK-0, 10Gi)    │
│     │                                                    │
│     ├── mysql-1.mysql-headless                           │
│     │      └── PVC: data-mysql-1 → PV (VMDK-1, 10Gi)    │
│     │                                                    │
│     └── mysql-2.mysql-headless                           │
│            └── PVC: data-mysql-2 → PV (VMDK-2, 10Gi)    │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

### StatefulSet Pod 재생성 시 동작

```
┌─────────────────────────────────────────────────────────────┐
│          mysql-1 Pod가 삭제/장애 발생 시                       │
│                                                             │
│  상태 1 (정상):                                               │
│  mysql-0 ──▶ PVC: data-mysql-0 ──▶ PV-0                    │
│  mysql-1 ──▶ PVC: data-mysql-1 ──▶ PV-1  ← 이 Pod 장애     │
│  mysql-2 ──▶ PVC: data-mysql-2 ──▶ PV-2                    │
│                                                             │
│  상태 2 (장애 후 자동 복구):                                   │
│  mysql-0 ──▶ PVC: data-mysql-0 ──▶ PV-0                    │
│  mysql-1 ──▶ PVC: data-mysql-1 ──▶ PV-1  ← 새 Pod, 같은 PVC│
│  mysql-2 ──▶ PVC: data-mysql-2 ──▶ PV-2                    │
│                                                             │
│  ✅ 새 mysql-1 Pod는 같은 PVC(data-mysql-1)에 재연결          │
│  ✅ 이전 데이터가 그대로 유지됨!                                │
│  ✅ Pod 이름도 동일 (mysql-1)                                  │
│  ✅ DNS도 동일 (mysql-1.mysql-headless....)                    │
└─────────────────────────────────────────────────────────────┘
```

### persistentVolumeClaimRetentionPolicy (K8s 1.27+)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain    # StatefulSet 삭제 시 PVC 유지 (기본값)
    whenScaled: Delete     # 스케일 다운 시 불필요한 PVC 삭제

  # whenDeleted 옵션:
  #   Retain: StatefulSet 삭제해도 PVC 유지 (안전, 기본값)
  #   Delete: StatefulSet 삭제 시 PVC도 함께 삭제

  # whenScaled 옵션:
  #   Retain: replicas 줄여도 PVC 유지 (기본값)
  #   Delete: replicas 줄이면 해당 PVC 삭제
```

---

## 10. 스토리지 트러블슈팅

### PVC가 Pending 상태일 때

```
PVC Pending 원인 진단 흐름:

kubectl describe pvc <pvc-name>  → Events 섹션 확인
        │
        ├── "no persistent volumes available"
        │   → 정적 프로비저닝: 조건에 맞는 PV가 없음
        │   → 해결: PV 생성 또는 조건 확인 (용량, accessMode, storageClass)
        │
        ├── "waiting for first consumer"
        │   → volumeBindingMode: WaitForFirstConsumer
        │   → 정상! Pod가 생성되면 바인딩됨
        │
        ├── "storageclass.storage.k8s.io \"xxx\" not found"
        │   → StorageClass 이름 오타 또는 미생성
        │   → 해결: kubectl get sc 로 확인
        │
        ├── "failed to provision volume"
        │   → CSI 드라이버 오류 (백엔드 스토리지 문제)
        │   → 해결: CSI Controller 로그 확인
        │
        └── "exceeded quota"
            → ResourceQuota 초과
            → 해결: 쿼터 확인 및 조정
```

### 자주 발생하는 문제와 해결

| 증상 | 원인 | 확인 명령 | 해결 |
|------|------|----------|------|
| PVC `Pending` | StorageClass 없음 | `kubectl get sc` | StorageClass 생성, 이름 확인 |
| PVC `Pending` | CSI 드라이버 미설치 | `kubectl get csidrivers` | CSI 드라이버 설치 |
| Pod `ContainerCreating` 지속 | 볼륨 Attach 실패 | `kubectl describe pod` | CSI Controller 로그 확인 |
| Pod에서 쓰기 실패 | ReadOnly 마운트 | `kubectl exec -- mount` | accessMode 및 PV 상태 확인 |
| 볼륨 확장 안 됨 | allowVolumeExpansion 미설정 | `kubectl get sc -o yaml` | StorageClass 수정 |
| PV `Released` 재사용 불가 | Retain 정책으로 Released 상태 | `kubectl get pv` | PV의 claimRef 삭제 또는 PV 재생성 |
| 다른 노드에서 마운트 실패 | RWO 볼륨을 다른 노드에서 사용 시도 | `kubectl describe pod` | Pod를 같은 노드에 스케줄 또는 RWX 사용 |

### 유용한 디버깅 명령어

```bash
# ─── PV/PVC 상태 확인 ───
kubectl get pv
kubectl get pvc
kubectl get pvc -o wide                    # StorageClass, Volume 이름 포함

# PVC 상세 정보 (이벤트 포함)
kubectl describe pvc <pvc-name>

# PV 상세 정보
kubectl describe pv <pv-name>

# ─── StorageClass 확인 ───
kubectl get storageclass                   # 또는 kubectl get sc
kubectl describe sc <sc-name>
kubectl get sc -o yaml                     # 상세 파라미터 확인

# ─── CSI 드라이버 확인 ───
kubectl get csidrivers                     # 설치된 CSI 드라이버 목록
kubectl get csinodes                       # 노드별 CSI 등록 상태
kubectl get volumeattachments              # 볼륨 Attach 상태

# ─── CSI 로그 확인 ───
# vSphere CSI Controller 로그
kubectl logs -n vmware-system-csi deployment/vsphere-csi-controller \
  -c vsphere-csi-controller --tail=50

# vSphere CSI Node 로그 (특정 노드)
kubectl logs -n vmware-system-csi <vsphere-csi-node-pod> \
  -c vsphere-csi-node --tail=50

# ─── Pod 마운트 상태 확인 ───
kubectl exec <pod> -- df -h               # 마운트된 볼륨 용량 확인
kubectl exec <pod> -- mount | grep <path>  # 마운트 상세 정보

# ─── Released PV 재사용 (claimRef 제거) ───
kubectl patch pv <pv-name> -p '{"spec":{"claimRef": null}}'
```

---

## 11. 실습: 스토리지 동작 확인

### 실습 1: emptyDir — 컨테이너 간 데이터 공유

```bash
# 1. Pod 생성 (writer + reader 두 컨테이너)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-demo
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "while true; do date >> /shared/log.txt; sleep 5; done"]
    volumeMounts:
    - name: shared
      mountPath: /shared
  - name: reader
    image: busybox
    command: ["sh", "-c", "tail -f /shared/log.txt"]
    volumeMounts:
    - name: shared
      mountPath: /shared
  volumes:
  - name: shared
    emptyDir: {}
EOF

# 2. reader 컨테이너에서 로그 확인 (writer가 쓴 데이터)
kubectl logs emptydir-demo -c reader

# 3. Pod 삭제 후 데이터 확인
kubectl delete pod emptydir-demo
# → emptyDir 데이터는 Pod와 함께 소멸!
```

### 실습 2: 정적 프로비저닝 (PV → PVC → Pod)

```bash
# 1. PV 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: static-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /tmp/k8s-pv-data
    type: DirectoryOrCreate
EOF

# 2. PV 상태 확인
kubectl get pv static-pv
# STATUS: Available

# 3. PVC 생성 (PV에 바인딩)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: static-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: manual
EOF

# 4. PV/PVC 상태 확인 (Bound!)
kubectl get pv static-pv
kubectl get pvc static-pvc
# 둘 다 STATUS: Bound

# 5. Pod에서 PVC 사용
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pv-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh", "-c", "echo 'PV에 저장된 데이터!' > /data/message.txt && sleep 3600"]
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: static-pvc
EOF

# 6. 데이터 확인
kubectl exec pv-pod -- cat /data/message.txt
# 출력: PV에 저장된 데이터!

# 7. Pod 삭제 후 데이터 확인 (PV에 유지됨!)
kubectl delete pod pv-pod

# 새 Pod 생성하여 같은 PVC 사용
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pv-pod-2
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh", "-c", "cat /data/message.txt && sleep 3600"]
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: static-pvc
EOF

kubectl logs pv-pod-2
# 출력: PV에 저장된 데이터!  ← Pod가 바뀌어도 데이터 유지!

# 8. 정리
kubectl delete pod pv-pod-2
kubectl delete pvc static-pvc
kubectl get pv static-pv
# STATUS: Released (Retain 정책이므로 PV 유지)
kubectl delete pv static-pv
```

### 실습 3: 동적 프로비저닝 (StorageClass → PVC → 자동 PV)

```bash
# 1. StorageClass 확인 (기존에 있는지)
kubectl get sc

# 2. hostPath 기반 StorageClass 생성 (테스트용)
# ※ 프로덕션에서는 CSI 기반 StorageClass 사용
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner   # 수동 프로비저닝
volumeBindingMode: WaitForFirstConsumer
EOF

# 클라우드 환경이라면 기본 StorageClass 사용:
# kubectl get sc  →  기본(default) StorageClass 이름 확인

# 3. PVC 생성 (StorageClass 지정)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: local-storage
EOF

# 4. 상태 확인
kubectl get pvc dynamic-pvc
# WaitForFirstConsumer → Pending (Pod 생성 시 바인딩)

# 5. 정리
kubectl delete pvc dynamic-pvc
kubectl delete sc local-storage
```

### 실습 4: StatefulSet + volumeClaimTemplates

```bash
# 1. Headless Service + StatefulSet 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-headless
spec:
  clusterIP: None
  selector:
    app: web-sts
  ports:
  - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: web-headless
  replicas: 3
  selector:
    matchLabels:
      app: web-sts
  template:
    metadata:
      labels:
        app: web-sts
    spec:
      containers:
      - name: nginx
        image: nginx
        volumeMounts:
        - name: www
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: www
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
      # storageClassName: 기본 StorageClass 사용
EOF

# 2. Pod와 PVC 확인 (각 Pod마다 고유 PVC!)
kubectl get pods -l app=web-sts
kubectl get pvc -l app=web-sts
# NAME         STATUS   VOLUME     CAPACITY
# www-web-0    Bound    pvc-xxx    1Gi
# www-web-1    Bound    pvc-yyy    1Gi
# www-web-2    Bound    pvc-zzz    1Gi

# 3. 각 Pod에 고유 데이터 쓰기
kubectl exec web-0 -- sh -c "echo 'I am web-0' > /usr/share/nginx/html/index.html"
kubectl exec web-1 -- sh -c "echo 'I am web-1' > /usr/share/nginx/html/index.html"
kubectl exec web-2 -- sh -c "echo 'I am web-2' > /usr/share/nginx/html/index.html"

# 4. Pod 삭제 후 데이터 확인 (재생성 시 같은 PVC!)
kubectl delete pod web-1
# StatefulSet이 web-1을 자동 재생성

# 재생성된 web-1의 데이터 확인
kubectl exec web-1 -- cat /usr/share/nginx/html/index.html
# 출력: I am web-1  ← 데이터 유지!

# 5. Headless Service로 개별 Pod 접근
kubectl run test --image=busybox --rm -it --restart=Never -- \
  wget -qO- http://web-0.web-headless:80
# 출력: I am web-0

kubectl run test --image=busybox --rm -it --restart=Never -- \
  wget -qO- http://web-1.web-headless:80
# 출력: I am web-1

# 6. 정리
kubectl delete statefulset web
kubectl delete svc web-headless
# ⚠️ PVC는 자동 삭제되지 않음!
kubectl get pvc -l app=web-sts
kubectl delete pvc www-web-0 www-web-1 www-web-2
```

### 실습 5: PV/PVC 상태 전이 관찰

```bash
# PV/PVC 라이프사이클을 직접 관찰하는 실습

# 1. PV 생성 → Available 상태
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: lifecycle-pv
spec:
  capacity:
    storage: 2Gi
  accessModes: ["ReadWriteOnce"]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: lifecycle-test
  hostPath:
    path: /tmp/lifecycle-test
    type: DirectoryOrCreate
EOF

kubectl get pv lifecycle-pv
# STATUS: Available

# 2. PVC 생성 → PV가 Bound 상태로 전이
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: lifecycle-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 2Gi
  storageClassName: lifecycle-test
EOF

kubectl get pv lifecycle-pv
# STATUS: Bound
kubectl get pvc lifecycle-pvc
# STATUS: Bound

# 3. PVC 삭제 → PV가 Released 상태로 전이
kubectl delete pvc lifecycle-pvc
kubectl get pv lifecycle-pv
# STATUS: Released (Retain 정책이므로 데이터 유지, 재사용 불가)

# 4. Released PV 재사용 (claimRef 제거)
kubectl patch pv lifecycle-pv -p '{"spec":{"claimRef": null}}'
kubectl get pv lifecycle-pv
# STATUS: Available (다시 사용 가능!)

# 5. 정리
kubectl delete pv lifecycle-pv
```

---

## 12. 정리 및 핵심 요약

### 한눈에 보는 K8s 스토리지

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   개발자                                                        │
│     │                                                           │
│     │  PVC 생성 ("10Gi SSD 주세요")                              │
│     ▼                                                           │
│   ┌──────────────┐                                              │
│   │     PVC      │  요청: 10Gi, RWO, StorageClass: fast-ssd    │
│   └──────┬───────┘                                              │
│          │                                                      │
│          │  StorageClass가 자동으로 PV 생성 (동적 프로비저닝)      │
│          ▼                                                      │
│   ┌──────────────┐     ┌──────────────────┐                     │
│   │      PV      │ ◀── │  StorageClass    │                     │
│   │  (자동 생성)  │     │  provisioner:    │                     │
│   └──────┬───────┘     │  CSI 드라이버     │                     │
│          │              └──────────────────┘                     │
│          │                                                      │
│          │  CSI 드라이버가 실제 스토리지 볼륨 생성                  │
│          ▼                                                      │
│   ┌──────────────────────┐                                      │
│   │   스토리지 백엔드      │                                      │
│   │  (vSphere VMDK,      │                                      │
│   │   AWS EBS, NFS 등)   │                                      │
│   └──────────────────────┘                                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 포인트 7가지

| # | 포인트 | 설명 |
|---|--------|------|
| 1 | **Pod는 일시적, 데이터는 영구적** | Pod가 죽어도 PV의 데이터는 유지됨. DB, 파일 저장에 PV 필수 |
| 2 | **PV/PVC로 역할 분리** | 관리자가 PV/StorageClass 준비, 개발자는 PVC로 요청만 |
| 3 | **동적 프로비저닝이 표준** | StorageClass + CSI로 PV 자동 생성. 수동 PV 생성은 최소화 |
| 4 | **CSI가 업계 표준** | in-tree 플러그인은 deprecated. 모든 신규 스토리지는 CSI 사용 |
| 5 | **AccessMode를 정확히 선택** | RWO(단일 노드), RWX(다중 노드 공유), 스토리지 백엔드 지원 확인 |
| 6 | **StatefulSet = 상태 저장 앱의 핵심** | 각 Pod에 고유 PVC, 순서 보장, 안정적 네트워크 ID 제공 |
| 7 | **Reclaim Policy 주의** | Delete는 데이터 영구 삭제! 프로덕션에서는 Retain 권장 |

### 언제 무엇을 사용해야 하는가?

```
┌─────────────────────────────────────────────────────────────┐
│                    선택 가이드                                 │
│                                                             │
│  Q: 같은 Pod의 컨테이너 간 임시 파일 공유?                     │
│  A: → emptyDir                                              │
│                                                             │
│  Q: 단일 Pod에서 데이터 영구 저장? (MySQL, PostgreSQL)         │
│  A: → PVC (RWO) + Deployment 또는 StatefulSet               │
│                                                             │
│  Q: DB 클러스터처럼 각 Pod가 독립 볼륨 필요?                   │
│  A: → StatefulSet + volumeClaimTemplates                    │
│                                                             │
│  Q: 여러 Pod가 같은 파일을 공유 읽기/쓰기?                     │
│  A: → PVC (RWX) + NFS 또는 CephFS 기반 StorageClass         │
│                                                             │
│  Q: ConfigMap/Secret을 파일로 Pod에 넣고 싶다면?              │
│  A: → configMap/secret Volume (PV 불필요)                    │
│                                                             │
│  Q: vSphere 환경에서 동적 프로비저닝?                          │
│  A: → vSphere CSI + SPBM 기반 StorageClass                  │
│                                                             │
│  Q: 스토리지 스냅샷이 필요?                                   │
│  A: → VolumeSnapshot (CSI 드라이버 스냅샷 지원 필요)           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### CKA/CKAD 시험 빈출 포인트

| 주제 | 자주 나오는 문제 유형 |
|------|---------------------|
| PV/PVC 생성 | 정적 프로비저닝 — PV 생성 후 PVC 바인딩 |
| StorageClass | 동적 프로비저닝 설정, 기본 StorageClass 지정 |
| Pod Volume 마운트 | PVC를 Pod에 마운트하는 YAML 작성 |
| AccessMode | RWO/ROX/RWX 차이 이해, 시나리오별 선택 |
| StatefulSet | volumeClaimTemplates, Headless Service, 순서 보장 |
| 볼륨 확장 | PVC spec.resources.requests.storage 수정 |
| Reclaim Policy | Retain/Delete 동작 차이, Released PV 처리 |
| 트러블슈팅 | PVC Pending 원인 분석, Pod 마운트 실패 해결 |

---

> **다음 단계**: 이 교육 자료를 학습한 후, [`k8s-learn.sh`](k8s-learn.sh)의 **7. PersistentVolumeClaim**, **8. StatefulSet** 실습을 통해 실제 볼륨을 생성하고 데이터 영속성을 직접 확인해 보세요. 또한 vSphere 환경이라면 [`k8s-install.sh`](k8s-install.sh)에서 vSphere CSI Driver 설치 옵션을 활용해 보세요.
