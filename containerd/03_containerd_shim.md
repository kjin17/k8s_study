# 03. containerd-shim 동작 원리

## containerd-shim이란?

containerd와 실제 컨테이너 프로세스(runc) 사이에서 동작하는 **중간 프로세스**입니다.
컨테이너 하나당 하나의 shim 프로세스가 생성됩니다.

---

## 왜 shim이 필요한가?

```
[containerd 없이]
containerd → runc → 컨테이너
문제: containerd가 재시작되면 모든 컨테이너가 종료됨

[containerd-shim 있을 때]
containerd → containerd-shim → runc → 컨테이너
장점: containerd가 재시작되어도 shim이 살아있어 컨테이너 유지
```

**shim의 핵심 역할:**

1. **containerd 데몬 의존성 분리** — containerd 재시작/업그레이드 시에도 컨테이너 유지
2. **표준 I/O 관리** — stdin/stdout/stderr 파이프 유지
3. **종료 상태 수집** — 컨테이너 종료 코드를 containerd에 보고
4. **runc 실행 후 대기** — runc는 컨테이너 시작 후 종료, shim이 프로세스 감시
5. **ttrpc 서버** — containerd와 경량 gRPC(ttrpc)로 통신

---

## shim 버전

| 버전 | 바이너리 | 특징 |
|------|---------|------|
| v1 | `containerd-shim` | 레거시, 각 컨테이너마다 runc 직접 실행 |
| **v2** | `containerd-shim-runc-v2` | 현재 표준, Pod 내 모든 컨테이너가 하나의 shim 공유 |

```bash
# 실행 중인 shim 프로세스 확인
ps aux | grep containerd-shim

# 출력 예시
# containerd-shim-runc-v2
#   -namespace k8s.io
#   -id <sandbox-id>       ← pause 컨테이너 (Pod 전체)
#   -address /run/containerd/containerd.sock
```

---

## shim v2의 Pod 레벨 관리

shim v2에서는 **Pod(sandbox)당 하나의 shim**이 Pod 내 모든 컨테이너를 관리합니다.

```
Pod (sandbox)
  └── containerd-shim-runc-v2 (1개)
        ├── pause 컨테이너 (infra container)
        ├── app 컨테이너 A
        └── app 컨테이너 B (사이드카)
```

**shim v1 vs shim v2 비교:**

| 항목 | shim v1 | shim v2 |
|------|---------|---------|
| shim 수 | 컨테이너당 1개 | Pod당 1개 |
| 메모리 | 많이 사용 | 효율적 |
| 네임스페이스 공유 | 어려움 | 자연스러움 |
| 성능 | 낮음 | 높음 |

---

## shim 생명주기

```
1. containerd가 shim 바이너리 실행
        │
        ▼
2. shim이 runc를 호출하여 컨테이너 시작
        │
        ▼
3. runc는 컨테이너 생성 후 종료 (shim은 계속 실행)
        │
        ▼
4. shim이 컨테이너 프로세스를 감시
   - I/O 파이프 관리
   - ttrpc로 containerd와 통신
        │
        ▼
5. 컨테이너 종료 시
   - 종료 코드 containerd에 보고
   - shim 프로세스 종료
```

---

## shim 프로세스 트리

```bash
# 실제 프로세스 트리 확인
pstree -p | grep -A5 containerd

# 예시:
# systemd(1)
# └── containerd(1234)
#     └── containerd-shim-runc-v2(5678)   ← Pod shim
#         ├── pause(5690)                 ← 인프라 컨테이너
#         └── nginx(5701)                 ← 앱 컨테이너

# shim의 실제 PID 확인
ls /run/containerd/io.containerd.runtime.v2.task/k8s.io/
cat /run/containerd/io.containerd.runtime.v2.task/k8s.io/<id>/init.pid
```

---

## shim 소켓 통신

```
containerd ←──ttrpc──→ containerd-shim
                        (Unix 소켓: /run/containerd/.../<id>/shim.sock)
```

```bash
# shim 소켓 확인
ls /run/containerd/io.containerd.runtime.v2.task/k8s.io/<container-id>/
# address   init.pid   log   log.json   options.json   runtime   shim.sock
```

---

## containerd 재시작 시 동작

```bash
# containerd 재시작
systemctl restart containerd

# 재시작 전후 컨테이너 상태 확인
kubectl get pods   # Pod는 Running 유지
ps aux | grep shim # shim 프로세스 살아있음

# containerd가 재연결 시:
# 1. 기존 shim 소켓 재발견
# 2. 컨테이너 상태 복원
# 3. 정상 운영 재개
```

---

## 커스텀 런타임 shim

runc 외에 다른 OCI 런타임도 shim으로 지원합니다.

| 런타임 | shim 바이너리 | 특징 |
|--------|-------------|------|
| runc | `containerd-shim-runc-v2` | 기본 OCI 런타임 |
| kata-containers | `containerd-shim-kata-v2` | VM 기반 격리 |
| gVisor (runsc) | `containerd-shim-runsc-v1` | 커널 샌드박스 |
| Wasm (runwasi) | `containerd-shim-wasmedge-v1` | WebAssembly 컨테이너 |

```yaml
# RuntimeClass로 커스텀 런타임 지정
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata
handler: kata   # containerd-shim-kata-v2 호출
---
apiVersion: v1
kind: Pod
spec:
  runtimeClassName: kata   # 이 Pod는 Kata Containers로 실행
  containers:
    - name: app
      image: nginx
```
