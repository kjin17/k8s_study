# 02. 네임스페이스 종류별 상세

## 1. PID 네임스페이스

프로세스 ID 공간을 격리합니다. 컨테이너 내부의 첫 번째 프로세스가 PID 1이 됩니다.

```bash
# 새 PID 네임스페이스에서 ps 실행
sudo unshare --pid --fork --mount-proc /bin/bash
ps aux
# PID 1: bash  ← 격리된 공간에서 PID 1

# 호스트에서 보면 실제 PID는 다름
# (다른 터미널에서)
ps aux | grep bash
```

**중첩 PID 네임스페이스:**
- 부모 네임스페이스에서는 자식 네임스페이스 프로세스가 보임
- 자식 네임스페이스에서는 부모 프로세스가 보이지 않음

---

## 2. NET 네임스페이스

네트워크 스택(인터페이스, 라우팅 테이블, iptables, 소켓)을 격리합니다.

```bash
# 새 네트워크 네임스페이스 생성
sudo ip netns add myns

# 네임스페이스 목록
ip netns list

# 해당 네임스페이스에서 명령 실행
sudo ip netns exec myns ip link show
# lo만 있고 eth0 없음 (격리됨)

sudo ip netns exec myns ip addr
# 127.0.0.1만 존재

# veth pair로 호스트-컨테이너 네트워크 연결
sudo ip link add veth0 type veth peer name veth1
sudo ip link set veth1 netns myns

sudo ip addr add 10.0.0.1/24 dev veth0
sudo ip link set veth0 up

sudo ip netns exec myns ip addr add 10.0.0.2/24 dev veth1
sudo ip netns exec myns ip link set veth1 up
sudo ip netns exec myns ip link set lo up

# 통신 테스트
ping 10.0.0.2 -c 3
sudo ip netns exec myns ping 10.0.0.1 -c 3

# 정리
sudo ip netns del myns
```

---

## 3. MNT 네임스페이스

파일시스템 마운트 포인트를 격리합니다. 컨테이너의 루트 파일시스템 격리에 사용됩니다.

```bash
# 새 마운트 네임스페이스
sudo unshare --mount /bin/bash

# 이 네임스페이스에서만 tmpfs 마운트
mount -t tmpfs tmpfs /mnt
df -h /mnt
# tmpfs 마운트됨

# 호스트에서는 보이지 않음
# (다른 터미널에서)
df -h /mnt
# tmpfs 없음
```

**pivot_root / chroot와 조합:**
```bash
# chroot로 루트 파일시스템 변경 (컨테이너 기초)
sudo unshare --mount --fork /bin/bash
mount --bind /path/to/rootfs /path/to/rootfs
cd /path/to/rootfs
pivot_root . old_root
exec /bin/bash
```

---

## 4. UTS 네임스페이스

호스트명(hostname)과 NIS 도메인명을 격리합니다.

```bash
# 새 UTS 네임스페이스
sudo unshare --uts /bin/bash

# 호스트명 변경 (이 네임스페이스에서만 적용)
hostname container-1
hostname
# container-1

# 호스트에서는 변경 안 됨
# (다른 터미널에서)
hostname
# 원래 호스트명 유지
```

---

## 5. IPC 네임스페이스

System V IPC(공유 메모리, 세마포어, 메시지 큐)와 POSIX 메시지 큐를 격리합니다.

```bash
# 새 IPC 네임스페이스
sudo unshare --ipc /bin/bash

# 공유 메모리 세그먼트 생성
ipcmk -M 1024
# Shared memory id: 0

# 호스트에서는 보이지 않음
ipcs -m
# (다른 터미널) — 해당 IPC 세그먼트 없음
```

---

## 6. USER 네임스페이스

UID/GID 매핑을 격리합니다. 컨테이너 내부에서 root이지만 호스트에서는 일반 사용자로 실행 가능합니다.

```bash
# root 권한 없이 새 USER 네임스페이스 생성
unshare --user --map-root-user /bin/bash

# 네임스페이스 내부에서는 root
whoami
# root
id
# uid=0(root) gid=0(root)

# 호스트에서 보면 실제 UID는 일반 사용자
# /proc/<pid>/uid_map 에서 매핑 확인
cat /proc/self/uid_map
# 0  1000  1   (컨테이너 0 = 호스트 1000)
```

**Rootless 컨테이너의 핵심:**
```bash
# Docker rootless mode — USER 네임스페이스 활용
dockerd-rootless-setuptool.sh install
docker run --rm alpine whoami
# root (컨테이너 내부)
# 실제로는 호스트의 일반 사용자로 실행됨
```

---

## 네임스페이스 내 자원 제한 요약

| 네임스페이스 | 제한 가능한 자원 | 방법 |
|------------|--------------|------|
| PID | 프로세스 수 | cgroup pids + PID NS 조합 |
| NET | 네트워크 대역폭 | tc (traffic control) + NET NS |
| MNT | 파일시스템 공간 | quota + MNT NS |
| USER | UID/GID 범위 | uid_map/gid_map 매핑 |
| (모든 NS) | CPU/Memory/I/O | cgroup (별도 챕터) |

```bash
# 네트워크 대역폭 제한 (tc 사용)
sudo ip netns exec myns tc qdisc add dev veth1 root tbf \
    rate 1mbit burst 32kbit latency 400ms
# veth1 인터페이스를 1Mbps로 제한

# 파일시스템 쿼터 (MNT NS 내)
mount -t tmpfs -o size=100m tmpfs /container/data
# tmpfs 크기를 100MB로 제한
```
