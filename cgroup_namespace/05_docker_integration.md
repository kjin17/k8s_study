# 05. Docker/Kubernetes에서의 namespace + cgroup 활용

## Docker의 내부 동작

Docker 컨테이너를 생성할 때 내부적으로 다음을 수행합니다:

```
docker run --cpus=0.5 --memory=256m nginx
    │
    ├── namespace 생성 (PID, NET, MNT, UTS, IPC)
    ├── cgroup 생성 (/sys/fs/cgroup/.../docker-<id>/)
    │   ├── cpu.max = "50000 100000"   (0.5 CPU)
    │   └── memory.max = "268435456"  (256MB)
    ├── overlayfs로 이미지 레이어 마운트
    ├── veth pair 생성 및 NET NS에 연결
    └── PID 1로 지정된 프로세스 실행
```

---

## Docker 자원 제한 옵션 ↔ cgroup 매핑

### CPU 제한

```bash
# --cpus: CPU 코어 수 제한
docker run --cpus=0.5 nginx
# → cpu.max = "50000 100000"

# --cpu-shares: 상대적 가중치 (기본 1024)
docker run --cpu-shares=512 nginx
# → cpu.weight = 20  (cgroup v2 변환값)

# --cpuset-cpus: 특정 코어만 사용
docker run --cpuset-cpus="0,1" nginx
# → cpuset.cpus = "0-1"

# 현재 컨테이너 CPU 설정 확인
CGROUP=$(docker inspect <container> --format '{{.Id}}')
cat /sys/fs/cgroup/system.slice/docker-${CGROUP}.scope/cpu.max
```

### 메모리 제한

```bash
# --memory: 메모리 최대 사용량
docker run --memory=256m nginx
# → memory.max = "268435456"

# --memory-swap: 메모리+스왑 합산 제한
docker run --memory=256m --memory-swap=512m nginx
# → memory.swap.max = "268435456"

# --memory-reservation: 소프트 제한 (권고치)
docker run --memory=256m --memory-reservation=128m nginx
# → memory.low = "134217728"

# OOM 발생 시 점수 조정 (-1000 ~ 1000, 낮을수록 kill 방지)
docker run --oom-score-adj=-500 nginx
```

### I/O 제한

```bash
# --device-read-bps / --device-write-bps
docker run --device-read-bps=/dev/sda:10mb nginx
# → io.max = "8:0 rbps=10485760"

# --device-read-iops / --device-write-iops
docker run --device-read-iops=/dev/sda:1000 nginx
```

### PID 제한

```bash
# --pids-limit
docker run --pids-limit=100 nginx
# → pids.max = "100"
```

---

## cgroup 실제 경로 확인 (Docker)

```bash
# 컨테이너 ID
CID=$(docker inspect <container> --format '{{.Id}}')

# cgroup v2 경로
ls /sys/fs/cgroup/system.slice/docker-${CID}.scope/

# 주요 파일 확인
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/cpu.max
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/memory.max
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/pids.max
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/memory.current
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/cpu.stat
```

---

## Kubernetes의 자원 관리

Kubernetes는 Pod spec의 `resources`를 cgroup으로 변환합니다.

```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: app
      image: nginx
      resources:
        requests:               # 스케줄링 기준 (최소 보장)
          cpu: "250m"           # 0.25 CPU
          memory: "128Mi"
        limits:                 # cgroup 제한값
          cpu: "500m"           # 0.5 CPU
          memory: "256Mi"
```

### requests vs limits → cgroup 매핑

| Kubernetes | cgroup v2 파일 | 의미 |
|-----------|--------------|------|
| `limits.cpu` | `cpu.max` | 최대 CPU 사용량 |
| `requests.cpu` | `cpu.weight` | CPU 상대적 가중치 |
| `limits.memory` | `memory.max` | 메모리 초과 시 OOM |
| `requests.memory` | `memory.min` | 최소 보장 메모리 |

```bash
# kubelet이 생성하는 cgroup 경로
/sys/fs/cgroup/kubepods.slice/
└── kubepods-burstable.slice/         # QoS: Burstable
    └── kubepods-burstable-pod<uid>.slice/
        └── <container-id>.scope/
            ├── cpu.max
            └── memory.max
```

### QoS 클래스와 cgroup

| QoS 클래스 | 조건 | cgroup 위치 |
|-----------|------|------------|
| Guaranteed | requests == limits | `kubepods-guaranteed.slice` |
| Burstable | requests < limits | `kubepods-burstable.slice` |
| BestEffort | requests/limits 미설정 | `kubepods-besteffort.slice` |

```bash
# 노드에서 Pod cgroup 확인
kubectl get pod <pod-name> -o jsonpath='{.metadata.uid}'
# → pod UID로 cgroup 경로 추적 가능
```

---

## 네임스페이스 확인 (Docker + Kubernetes)

```bash
# Docker 컨테이너의 네임스페이스 확인
CPID=$(docker inspect <container> --format '{{.State.Pid}}')
ls -la /proc/$CPID/ns/

# Kubernetes Pod의 네임스페이스 확인
kubectl get pod <pod> -o jsonpath='{.spec.hostPID}'     # PID 공유 여부
kubectl get pod <pod> -o jsonpath='{.spec.hostNetwork}' # 네트워크 공유 여부

# 컨테이너 네임스페이스에 직접 진입 (디버깅)
CPID=$(docker inspect <container> --format '{{.State.Pid}}')
sudo nsenter --target $CPID --pid --net --mount /bin/bash
```
