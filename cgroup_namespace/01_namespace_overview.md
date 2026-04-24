# 01. 리눅스 네임스페이스 개요

## 네임스페이스란?

리눅스 네임스페이스는 프로세스가 시스템 자원의 **격리된 뷰(view)**를 갖도록 하는 커널 기능입니다.
같은 호스트에서 실행되지만 서로 다른 네임스페이스에 있는 프로세스는 서로를 인식하지 못합니다.

---

## 네임스페이스 종류 (7종)

| 네임스페이스 | 커널 상수 | 격리 대상 | 도입 버전 |
|------------|----------|---------|---------|
| **PID** | `CLONE_NEWPID` | 프로세스 ID | 3.8 |
| **NET** | `CLONE_NEWNET` | 네트워크 스택 (인터페이스, 라우팅, iptables) | 2.6.24 |
| **MNT** | `CLONE_NEWNS` | 파일시스템 마운트 포인트 | 2.4.19 |
| **UTS** | `CLONE_NEWUTS` | 호스트명, 도메인명 | 2.6.19 |
| **IPC** | `CLONE_NEWIPC` | System V IPC, POSIX 메시지 큐 | 2.6.19 |
| **USER** | `CLONE_NEWUSER` | UID/GID 매핑 | 3.8 |
| **CGROUP** | `CLONE_NEWCGROUP` | cgroup 루트 디렉토리 뷰 | 4.6 |

---

## 네임스페이스 확인 명령어

```bash
# 현재 프로세스의 네임스페이스 확인
ls -la /proc/self/ns/
# lrwxrwxrwx cgroup -> cgroup:[4026531835]
# lrwxrwxrwx ipc    -> ipc:[4026531839]
# lrwxrwxrwx mnt    -> mnt:[4026531841]
# lrwxrwxrwx net    -> net:[4026531840]
# lrwxrwxrwx pid    -> pid:[4026531836]
# lrwxrwxrwx user   -> user:[4026531837]
# lrwxrwxrwx uts    -> uts:[4026531838]

# 특정 프로세스 네임스페이스 확인
ls -la /proc/<PID>/ns/

# 시스템 전체 네임스페이스 목록
lsns

# 특정 타입만 확인
lsns -t pid
lsns -t net
```

---

## 네임스페이스 생성 방법

### 1. unshare — 현재 프로세스를 새 네임스페이스로 분리

```bash
# 새 PID + UTS 네임스페이스로 bash 실행
sudo unshare --pid --uts --fork --mount-proc /bin/bash

# 새 네트워크 네임스페이스
sudo unshare --net /bin/bash

# 모든 네임스페이스 새로 생성
sudo unshare --pid --net --mount --uts --ipc --fork --mount-proc /bin/bash
```

### 2. clone() 시스템 콜 (프로그래밍)

```c
#define _GNU_SOURCE
#include <sched.h>

// 새 PID + 네트워크 네임스페이스로 자식 프로세스 생성
int pid = clone(child_func, stack_top,
    CLONE_NEWPID | CLONE_NEWNET | SIGCHLD, NULL);
```

### 3. nsenter — 기존 네임스페이스에 참여

```bash
# 특정 PID의 네임스페이스로 진입
sudo nsenter --target <PID> --pid --net --mount /bin/bash

# Docker 컨테이너 네임스페이스 진입
CONTAINER_PID=$(docker inspect <container> --format '{{.State.Pid}}')
sudo nsenter --target $CONTAINER_PID --pid --net --mount /bin/bash
```

---

## 네임스페이스 생명주기

```
생성 (clone/unshare)
    │
    ▼
유지 (프로세스 실행 중 또는 /proc/<pid>/ns/ 바인드 마운트)
    │
    ▼
소멸 (마지막 프로세스 종료 + 참조 없음)
```

```bash
# 네임스페이스를 파일로 고정 (프로세스 없어도 유지)
touch /tmp/mnt-ns
sudo mount --bind /proc/self/ns/mnt /tmp/mnt-ns

# 나중에 해당 네임스페이스로 진입
sudo nsenter --mount=/tmp/mnt-ns /bin/bash
```
