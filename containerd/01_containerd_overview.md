# 01. containerd 개요 및 아키텍처

## containerd란?

CNCF Graduated 프로젝트로, **업계 표준 컨테이너 런타임**입니다.
Docker에서 분리되어 독립 프로젝트가 되었으며, Kubernetes 1.20부터 기본 런타임으로 채택되었습니다.

컨테이너의 전체 생명주기(이미지 pull, 컨테이너 생성/시작/정지/삭제, 스냅샷, 네트워크)를 관리합니다.

---

## 역사적 배경

```
Docker Engine (2013)
    │
    └── containerd 분리 (2016) → CNCF 기증 (2017)
    └── runc 분리 (OCI 표준)

Kubernetes Docker 지원 종료 (1.24, 2022)
    └── containerd 또는 CRI-O 직접 사용으로 전환
```

**왜 Docker를 제거했나?**
- Kubernetes는 CRI 인터페이스로 런타임과 통신
- Docker는 CRI를 직접 지원하지 않아 dockershim 중간 레이어 필요
- dockershim 유지 비용 과다 → 제거 결정
- containerd는 CRI 플러그인을 기본 내장

---

## 아키텍처

```
┌─────────────────────────────────────────────────────┐
│                    containerd                        │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │  CRI Plugin │  │  Content    │  │  Snapshotter│  │
│  │ (gRPC 서버) │  │  Store      │  │  (레이어)   │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │  Task       │  │  Images     │  │  Metadata   │  │
│  │  Service    │  │  Service    │  │  (boltdb)   │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  │
│                                                      │
│  소켓: /run/containerd/containerd.sock               │
└─────────────────────────────────────────────────────┘
          │
          ▼
  containerd-shim-runc-v2
          │
          ▼
        runc (OCI 런타임)
          │
          ▼
    컨테이너 프로세스
```

---

## 주요 기능

| 기능 | 설명 |
|------|------|
| **이미지 관리** | OCI 이미지 pull/push/list/remove |
| **컨테이너 관리** | 생성/시작/정지/삭제/exec |
| **스냅샷** | overlayfs 기반 레이어 관리 |
| **네임스페이스** | 논리적 격리 (k8s, default 등) |
| **CRI 플러그인** | kubelet gRPC 통신 인터페이스 |
| **이벤트** | 컨테이너 이벤트 스트리밍 |
| **Content Store** | OCI 아티팩트 저장소 |

---

## containerd 네임스페이스

containerd는 내부적으로 **네임스페이스**로 리소스를 격리합니다.

| 네임스페이스 | 용도 |
|------------|------|
| `k8s.io` | Kubernetes Pod/컨테이너 |
| `moby` | Docker 컨테이너 |
| `default` | ctr CLI 기본값 |

```bash
# 네임스페이스 목록
ctr namespace ls

# 특정 네임스페이스의 컨테이너
ctr -n k8s.io container ls

# Kubernetes 파드 이미지 목록
ctr -n k8s.io image ls
```

---

## 설정 파일

```toml
# /etc/containerd/config.toml (기본 설정)

version = 2

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.9"

  [plugins."io.containerd.grpc.v1.cri".containerd]
    snapshotter = "overlayfs"
    default_runtime_name = "runc"

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      runtime_type = "io.containerd.runc.v2"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true    # systemd cgroup 드라이버 (Kubernetes 권장)

[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["https://registry-1.docker.io"]
```

---

## 프로세스 구조

```bash
# 실행 중인 containerd 관련 프로세스 확인
ps aux | grep containerd

# 출력 예시:
# containerd (메인 데몬)
# containerd-shim-runc-v2 -namespace k8s.io -id <container-id>
# /pause  (sandbox 컨테이너)
# nginx   (실제 앱 컨테이너)
```
