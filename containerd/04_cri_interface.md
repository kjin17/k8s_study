# 04. CRI(Container Runtime Interface)와 containerd

## CRI란?

Kubernetes가 컨테이너 런타임과 통신하기 위한 **gRPC 기반 표준 인터페이스**입니다.
kubelet은 CRI를 통해 특정 런타임에 종속되지 않고 다양한 런타임을 사용할 수 있습니다.

---

## CRI 아키텍처

```
┌─────────────────────────────────────────────────────┐
│                     kubelet                          │
│  ┌──────────────┐          ┌──────────────────────┐  │
│  │ RuntimeService│          │   ImageService       │  │
│  │ (Pod/컨테이너)│          │ (이미지 pull/list)   │  │
│  └──────┬───────┘          └──────────┬───────────┘  │
└─────────┼──────────────────────────────┼─────────────┘
          │ gRPC (Unix socket)           │
          ▼                              ▼
┌─────────────────────────────────────────────────────┐
│              containerd CRI Plugin                   │
│         /run/containerd/containerd.sock              │
└─────────────────────────────────────────────────────┘
```

---

## CRI API — RuntimeService

Pod와 컨테이너의 생명주기를 관리하는 API입니다.

### Sandbox(Pod) 관련

| 메서드 | 설명 |
|--------|------|
| `RunPodSandbox` | Pod sandbox(pause 컨테이너) 생성 |
| `StopPodSandbox` | Pod sandbox 정지 |
| `RemovePodSandbox` | Pod sandbox 삭제 |
| `PodSandboxStatus` | Pod sandbox 상태 조회 |
| `ListPodSandbox` | Pod sandbox 목록 조회 |

### 컨테이너 관련

| 메서드 | 설명 |
|--------|------|
| `CreateContainer` | 컨테이너 생성 |
| `StartContainer` | 컨테이너 시작 |
| `StopContainer` | 컨테이너 정지 |
| `RemoveContainer` | 컨테이너 삭제 |
| `ListContainers` | 컨테이너 목록 |
| `ContainerStatus` | 컨테이너 상태 |
| `ExecSync` | 컨테이너 내 명령 동기 실행 |
| `Exec` | 컨테이너 내 명령 비동기 실행 |
| `Attach` | 컨테이너 표준 I/O 연결 |
| `PortForward` | 포트 포워딩 |

---

## CRI API — ImageService

| 메서드 | 설명 |
|--------|------|
| `PullImage` | 이미지 pull |
| `ListImages` | 이미지 목록 |
| `ImageStatus` | 이미지 상태/정보 |
| `RemoveImage` | 이미지 삭제 |
| `ImageFsInfo` | 이미지 파일시스템 사용량 |

---

## Pod 생성 시 CRI 호출 흐름

```
kubelet이 PodSpec 수신
    │
    ▼
1. ImageService.PullImage()
   → 각 컨테이너 이미지 pull
    │
    ▼
2. RuntimeService.RunPodSandbox()
   → pause 컨테이너 생성 (네트워크 네임스페이스 확보)
   → CNI 플러그인 호출 (Pod IP 할당)
    │
    ▼
3. RuntimeService.CreateContainer()
   → 각 컨테이너 생성 (pause의 네임스페이스 공유)
    │
    ▼
4. RuntimeService.StartContainer()
   → 각 컨테이너 시작
```

---

## pause 컨테이너 (infra container)

Pod의 네트워크/IPC 네임스페이스를 보유하는 특수 컨테이너입니다.

```bash
# pause 컨테이너 확인
crictl pods
crictl ps | grep pause

# pause 이미지
crictl images | grep pause
# registry.k8s.io/pause:3.9

# pause 컨테이너의 역할
# - PID 1로 고아 프로세스 수집
# - 네트워크 네임스페이스 유지 (앱 컨테이너가 재시작해도 IP 유지)
# - IPC 네임스페이스 공유
```

---

## kubelet CRI 설정

```yaml
# /var/lib/kubelet/config.yaml
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
imageServiceEndpoint: unix:///run/containerd/containerd.sock
```

```bash
# kubelet 런타임 설정 확인
ps aux | grep kubelet | grep container-runtime
# --container-runtime-endpoint=unix:///run/containerd/containerd.sock

# CRI 소켓 통신 확인
crictl info
```

---

## CRI 디버깅

```bash
# crictl 설정
cat /etc/crictl.yaml
# runtime-endpoint: unix:///run/containerd/containerd.sock
# image-endpoint: unix:///run/containerd/containerd.sock
# timeout: 10

# Pod 목록 (kubelet 관점)
crictl pods

# 컨테이너 목록
crictl ps -a

# 이미지 목록
crictl images

# 컨테이너 로그
crictl logs <container-id>

# 컨테이너 내 명령 실행
crictl exec -it <container-id> /bin/sh

# Pod inspect
crictl inspectp <pod-id>

# 컨테이너 inspect
crictl inspect <container-id>
```
