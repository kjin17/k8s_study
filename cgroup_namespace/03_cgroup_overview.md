# 03. cgroup 개요

## cgroup(Control Group)이란?

리눅스 커널 기능으로 프로세스 그룹의 **자원 사용량을 제한, 측정, 격리**합니다.
namespace가 "무엇을 볼 수 있나"를 제어한다면, cgroup은 "얼마나 쓸 수 있나"를 제어합니다.

---

## cgroup이 제어하는 자원

| 서브시스템 | 제어 대상 |
|-----------|---------|
| `cpu` | CPU 사용 시간 (shares, quota) |
| `cpuset` | 사용 가능한 CPU 코어/NUMA 노드 |
| `memory` | 메모리 사용량, OOM 제어 |
| `blkio` | 블록 디바이스 I/O 속도/횟수 |
| `pids` | 프로세스/스레드 수 |
| `net_cls` | 네트워크 패킷에 class ID 부여 |
| `devices` | 디바이스 접근 허용/거부 |
| `freezer` | 프로세스 그룹 일시 정지/재개 |

---

## cgroup v1 vs cgroup v2

### cgroup v1 (전통 방식)
- 서브시스템별 독립 계층 구조
- `/sys/fs/cgroup/<subsystem>/` 형태
- 프로세스가 여러 서브시스템에 분산 가능

```
/sys/fs/cgroup/
├── cpu/
│   └── docker/
│       └── <container-id>/
├── memory/
│   └── docker/
│       └── <container-id>/
└── pids/
    └── docker/
        └── <container-id>/
```

### cgroup v2 (통합 계층)
- 단일 통합 계층 구조 (Linux 4.5+, 기본 채택: Ubuntu 21.10+, RHEL 9+)
- `/sys/fs/cgroup/` 하나의 트리
- 더 일관된 인터페이스, Thread mode 지원

```
/sys/fs/cgroup/
└── system.slice/
    └── docker-<id>.scope/
        ├── cpu.max           ← CPU 제한
        ├── memory.max        ← 메모리 제한
        ├── io.max            ← I/O 제한
        └── pids.max          ← PID 제한
```

### 버전 확인

```bash
# cgroup 버전 확인
stat -fc %T /sys/fs/cgroup
# tmpfs   → cgroup v1
# cgroup2fs → cgroup v2

# 또는
mount | grep cgroup
# cgroup2 on /sys/fs/cgroup → v2
# cgroup on /sys/fs/cgroup/cpu → v1

# Docker에서 확인
docker info | grep "Cgroup"
# Cgroup Driver: systemd
# Cgroup Version: 2
```

---

## cgroup 계층 구조

cgroup은 계층(hierarchy) 구조로 관리됩니다. 부모의 제한이 자식에게도 적용됩니다.

```
root cgroup (/)
    ├── system.slice/
    │   ├── docker.service/
    │   │   └── docker-<id>.scope/  ← 컨테이너
    │   └── sshd.service/
    └── user.slice/
        └── user-1000.slice/
            └── session-1.scope/
```

---

## cgroup 관련 도구

```bash
# systemd-cgtop — cgroup별 자원 사용량 실시간 확인
systemd-cgtop

# cgls — cgroup 트리 확인
systemd-cgls

# 특정 cgroup 상태 확인
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/memory.current
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/cpu.stat

# cgroup에 프로세스 추가
echo <PID> > /sys/fs/cgroup/mygroup/cgroup.procs
```
