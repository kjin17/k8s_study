# 02. containerd 핵심 컴포넌트

## 1. Content Store

OCI 이미지 레이어, 설정, 매니페스트를 **content-addressable** 방식으로 저장합니다.
동일한 SHA256 다이제스트를 가진 레이어는 중복 저장하지 않습니다.

```
/var/lib/containerd/io.containerd.content.v1.content/
├── blobs/
│   └── sha256/
│       ├── abc123...  ← 이미지 레이어
│       ├── def456...  ← 이미지 설정
│       └── ghi789...  ← 이미지 매니페스트
└── ingest/            ← 다운로드 중인 임시 파일
```

```bash
# Content Store 조회
ctr content ls

# 특정 블롭 정보
ctr content info sha256:<digest>
```

---

## 2. Snapshotter (스냅샷)

컨테이너 파일시스템 레이어를 관리합니다. 기본값은 **overlayfs**입니다.

```
이미지 레이어 (읽기 전용)
  Layer 1: ubuntu base
  Layer 2: nginx 설치
  Layer 3: 설정 파일
      │
      ▼
  컨테이너 레이어 (읽기/쓰기) ← 컨테이너 실행 시 추가
```

```bash
# 스냅샷 목록
ctr -n k8s.io snapshot ls

# overlayfs 마운트 확인
mount | grep overlay

# 스냅샷 사용량 확인
du -sh /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/
```

**지원 Snapshotter 종류:**

| Snapshotter | 특징 | 요구사항 |
|------------|------|---------|
| `overlayfs` | 기본값, 대부분 환경 | Linux 커널 3.18+ |
| `native` | 단순 파일 복사 | - |
| `devmapper` | LVM 기반 | block device 필요 |
| `zfs` | ZFS 파일시스템 | ZFS 설치 필요 |
| `stargz` | 지연 로딩(lazy-pull) | eStargz 이미지 포맷 |

---

## 3. Metadata Store (boltdb)

컨테이너, 이미지, 스냅샷 메타데이터를 **boltdb**에 저장합니다.

```
/var/lib/containerd/io.containerd.metadata.v1.bolt/
└── meta.db    ← boltdb 파일
```

```bash
# 메타데이터 확인 (bbolt 도구)
bbolt buckets /var/lib/containerd/io.containerd.metadata.v1.bolt/meta.db
```

---

## 4. Task Service

실행 중인 컨테이너(Task)를 관리합니다. 각 Task는 containerd-shim 프로세스와 연결됩니다.

```bash
# 실행 중인 Task 목록
ctr -n k8s.io task ls

# Task 상태
ctr -n k8s.io task ps <container-id>

# Task에 명령 실행
ctr -n k8s.io task exec --exec-id shell <container-id> /bin/sh
```

---

## 5. CRI Plugin

kubelet과 gRPC로 통신하는 인터페이스입니다. containerd에 내장되어 있습니다.

```
kubelet
  │ gRPC (CRI)
  ├── RuntimeService  → Pod/컨테이너 생명주기
  └── ImageService    → 이미지 pull/list/remove

containerd CRI Plugin
  ├── /run/containerd/containerd.sock (Unix 소켓)
  └── 내부적으로 containerd API 호출
```

```bash
# CRI 소켓 확인
ls -la /run/containerd/containerd.sock

# crictl로 CRI 직접 호출 (kubelet과 동일한 인터페이스)
crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps
crictl images
crictl pods
```

---

## 6. 이미지 서비스

OCI 이미지 풀/푸시/목록/삭제를 처리합니다.

```bash
# 이미지 pull
ctr image pull docker.io/library/nginx:latest

# 이미지 목록
ctr -n k8s.io image ls

# 이미지 상세
ctr image info docker.io/library/nginx:latest

# 이미지 삭제
ctr image rm docker.io/library/nginx:latest

# private registry pull
ctr image pull --user <user>:<password> myregistry.com/myimage:tag
```

---

## 주요 디렉토리 구조

```
/var/lib/containerd/
├── io.containerd.content.v1.content/      ← 이미지 블롭
├── io.containerd.metadata.v1.bolt/        ← 메타데이터 DB
├── io.containerd.snapshotter.v1.overlayfs/ ← 파일시스템 레이어
│   ├── metadata.db
│   └── snapshots/
│       └── <id>/
│           ├── fs/    ← upperdir (컨테이너 쓰기 레이어)
│           └── work/  ← overlayfs work 디렉토리
└── tmpmounts/

/run/containerd/
├── containerd.sock        ← 메인 소켓
├── containerd.sock.ttrpc  ← ttrpc 소켓
└── io.containerd.runtime.v2.task/
    └── k8s.io/
        └── <container-id>/  ← 각 컨테이너 런타임 상태
```
