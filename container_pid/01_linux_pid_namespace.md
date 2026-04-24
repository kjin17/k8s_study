# 01. 리눅스 PID 네임스페이스

## PID 네임스페이스란?

리눅스 네임스페이스는 프로세스가 시스템 자원을 격리해서 보는 메커니즘입니다.
PID 네임스페이스는 **프로세스 ID 공간을 격리**하여 컨테이너 내부에서 독립적인 PID 체계를 갖도록 합니다.

---

## 호스트 vs 컨테이너 PID 관계

```
호스트 PID 공간           컨테이너 PID 공간
─────────────────         ─────────────────
PID 1  (systemd)          PID 1  (nginx)     ← 컨테이너 내 첫 프로세스
PID 2  (kthreadd)         PID 2  (worker)
PID 100 (dockerd)
PID 3201 (containerd)
PID 3892 (nginx)          ← 호스트에서 보면 3892
```

- 컨테이너 내부에서 `ps` → PID 1, 2, ... 로 보임
- 호스트에서 `ps` → 실제 PID(3892 등)로 보임
- 같은 프로세스지만 **네임스페이스에 따라 PID가 다름**

---

## PID 네임스페이스 확인

```bash
# 호스트에서 컨테이너 프로세스 확인
docker run -d --name nginx-test nginx

# 컨테이너 내부 PID 확인
docker exec nginx-test ps aux
# PID 1: nginx master process

# 호스트에서 같은 프로세스 확인
ps aux | grep nginx
# 호스트 PID는 훨씬 큰 숫자

# 네임스페이스 직접 확인
docker inspect nginx-test --format '{{.State.Pid}}'
# 출력: 호스트에서의 실제 PID

ls -la /proc/$(docker inspect nginx-test --format '{{.State.Pid}}')/ns/pid
# lrwxrwxrwx pid -> pid:[4026532xxx]  ← 고유 네임스페이스 ID
```

---

## PID 네임스페이스 계층 구조

PID 네임스페이스는 **부모-자식 계층**을 형성합니다.

```
Host PID NS (root)
  └── Container A PID NS
        └── (중첩 컨테이너 가능)
  └── Container B PID NS
```

- 부모 네임스페이스에서는 자식 네임스페이스의 프로세스가 보임
- 자식 네임스페이스에서는 부모/형제의 프로세스가 보이지 않음

---

## 네임스페이스 관련 시스템 콜

| 시스템 콜 | 설명 |
|-----------|------|
| `clone(CLONE_NEWPID)` | 새 PID 네임스페이스로 프로세스 생성 |
| `unshare(CLONE_NEWPID)` | 현재 프로세스를 새 네임스페이스로 이동 |
| `setns()` | 기존 네임스페이스에 참여 |

```bash
# unshare로 새 PID 네임스페이스 진입 (실습)
sudo unshare --fork --pid --mount-proc /bin/bash

# 새 쉘 내에서 확인
ps aux
# PID 1: bash  ← 격리된 공간
# PID 2: ps
```

---

## /proc 파일시스템과 PID

컨테이너는 자체 `/proc`를 마운트하여 독립적인 프로세스 정보를 제공합니다.

```bash
# 컨테이너 내부 /proc 확인
docker exec nginx-test ls /proc/
# 1  2  3  ...  (컨테이너 내부 PID 기준)

# 호스트의 /proc와 다름
ls /proc/
# 1  2  3  ...  (호스트 전체 프로세스)
```
