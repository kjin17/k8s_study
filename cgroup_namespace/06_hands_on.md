# 06. 실습 예제

## 실습 1: 네임스페이스 격리 직접 체험

### 1-1. UTS + PID 네임스페이스 격리

```bash
# 새 UTS + PID 네임스페이스로 진입
sudo unshare --uts --pid --fork --mount-proc /bin/bash

# 호스트명 변경 (이 네임스페이스에서만 적용)
hostname my-container
hostname
# my-container

# 프로세스 확인 (PID 1이 bash)
ps aux
# PID 1: bash
# PID 2: ps

# 호스트에서는 원래 호스트명 유지됨 (새 터미널 확인)
exit
```

### 1-2. 네트워크 네임스페이스 격리 및 연결

```bash
# 새 네트워크 네임스페이스 생성
sudo ip netns add test-ns

# 격리된 네트워크 확인 (lo만 존재)
sudo ip netns exec test-ns ip link show

# veth pair 생성 (호스트-네임스페이스 연결)
sudo ip link add veth-host type veth peer name veth-ns
sudo ip link set veth-ns netns test-ns

# IP 설정
sudo ip addr add 192.168.100.1/24 dev veth-host
sudo ip link set veth-host up

sudo ip netns exec test-ns ip addr add 192.168.100.2/24 dev veth-ns
sudo ip netns exec test-ns ip link set veth-ns up
sudo ip netns exec test-ns ip link set lo up

# 통신 테스트
ping -c 3 192.168.100.2
sudo ip netns exec test-ns ping -c 3 192.168.100.1

# 정리
sudo ip netns del test-ns
```

---

## 실습 2: cgroup으로 CPU 제한

```bash
# cgroup 생성
sudo mkdir /sys/fs/cgroup/test-cpu

# CPU 20% 제한 (cgroup v2)
sudo bash -c "echo '20000 100000' > /sys/fs/cgroup/test-cpu/cpu.max"

# stress 도구 설치
sudo apt-get install -y stress

# 제한 없이 CPU 사용 (별도 터미널에서 top으로 확인)
stress --cpu 1 --timeout 10 &
PID=$!
top -p $PID -n 1 -b | grep stress
# CPU 사용률: ~100%
wait $PID

# cgroup에 등록 후 CPU 사용 (20% 제한)
stress --cpu 1 --timeout 30 &
PID=$!
echo $PID | sudo tee /sys/fs/cgroup/test-cpu/cgroup.procs
top -p $PID -n 3 -b | grep stress
# CPU 사용률: ~20%로 제한됨
wait $PID

# 쓰로틀링 확인
cat /sys/fs/cgroup/test-cpu/cpu.stat | grep throttled
# nr_throttled: X  (쓰로틀링 발생 횟수)

# 정리
sudo rmdir /sys/fs/cgroup/test-cpu
```

---

## 실습 3: cgroup으로 메모리 제한 + OOM 관찰

```bash
# cgroup 생성 및 메모리 50MB 제한
sudo mkdir /sys/fs/cgroup/test-mem
sudo bash -c "echo '52428800' > /sys/fs/cgroup/test-mem/memory.max"

# 메모리 사용 확인용 Python 스크립트 작성
cat > /tmp/mem_test.py << 'EOF'
import time
data = []
for i in range(100):
    data.append(b'x' * 1024 * 1024)  # 1MB씩 할당
    print(f"할당: {i+1}MB")
    time.sleep(0.2)
EOF

# 제한 없이 실행
python3 /tmp/mem_test.py &
PID=$!
wait $PID  # 100MB 할당 성공

# cgroup에 등록 후 실행 (50MB 제한)
python3 /tmp/mem_test.py &
PID=$!
echo $PID | sudo tee /sys/fs/cgroup/test-mem/cgroup.procs
wait $PID
# 50MB 초과 시 OOM Kill 발생

# OOM 이벤트 확인
cat /sys/fs/cgroup/test-mem/memory.events
# oom: 1
# oom_kill: 1

# dmesg에서 OOM killer 로그 확인
dmesg | grep -i "oom" | tail -5

# 정리
sudo rmdir /sys/fs/cgroup/test-mem
```

---

## 실습 4: Docker 자원 제한 검증

```bash
# 메모리 128MB, CPU 0.5 제한으로 컨테이너 실행
docker run -d --name resource-test \
    --memory=128m \
    --cpus=0.5 \
    --pids-limit=50 \
    ubuntu:22.04 sleep 3600

# cgroup 경로 확인
CID=$(docker inspect resource-test --format '{{.Id}}')
CGROUP_PATH="/sys/fs/cgroup/system.slice/docker-${CID}.scope"

# 설정 확인
echo "=== CPU 제한 ==="
cat $CGROUP_PATH/cpu.max

echo "=== 메모리 제한 ==="
cat $CGROUP_PATH/memory.max

echo "=== PID 제한 ==="
cat $CGROUP_PATH/pids.max

# 실시간 자원 사용량
docker stats resource-test --no-stream

# 컨테이너 내에서 stress 테스트
docker exec resource-test bash -c "
    apt-get install -y stress -qq
    stress --cpu 2 --vm 1 --vm-bytes 200M --timeout 5
"
# CPU는 0.5로 제한, 메모리 200MB 시도 시 OOM 발생

# 정리
docker rm -f resource-test
```

---

## 실습 5: namespace + cgroup 통합 — 미니 컨테이너 만들기

```bash
# Alpine rootfs 준비
mkdir /tmp/mini-container
docker export $(docker create alpine) | tar -C /tmp/mini-container -xf -

# cgroup 설정
sudo mkdir /sys/fs/cgroup/mini-container
sudo bash -c "echo '50000 100000' > /sys/fs/cgroup/mini-container/cpu.max"
sudo bash -c "echo '67108864'     > /sys/fs/cgroup/mini-container/memory.max"
sudo bash -c "echo '20'           > /sys/fs/cgroup/mini-container/pids.max"

# 새 네임스페이스 + cgroup 적용하여 프로세스 실행
sudo unshare --pid --net --mount --uts --ipc --fork bash -c "
    # cgroup 등록
    echo \$\$ > /sys/fs/cgroup/mini-container/cgroup.procs

    # 호스트명 설정
    hostname mini-container

    # rootfs 마운트
    mount --bind /tmp/mini-container /tmp/mini-container
    cd /tmp/mini-container

    # pivot_root로 루트 변경
    mkdir -p old_root
    pivot_root . old_root
    
    # 필수 마운트
    mount -t proc proc /proc
    
    # 쉘 실행
    exec /bin/sh
"

# mini-container 쉘에서 확인
ps aux        # PID 1이 sh
hostname      # mini-container
cat /proc/meminfo | grep MemTotal  # 제한된 메모리 뷰

# 정리
sudo rmdir /sys/fs/cgroup/mini-container
sudo rm -rf /tmp/mini-container
```

---

## 요약: namespace vs cgroup

| 항목 | namespace | cgroup |
|------|-----------|--------|
| 목적 | 격리 (무엇을 볼 수 있나) | 제한 (얼마나 쓸 수 있나) |
| 대상 | PID, 네트워크, 파일시스템, 호스트명 등 | CPU, 메모리, I/O, PID 수 |
| 인터페이스 | `/proc/<pid>/ns/`, `unshare`, `nsenter` | `/sys/fs/cgroup/`, `systemd` |
| 컨테이너 역할 | 프로세스 격리 공간 제공 | 자원 사용량 제한 및 보장 |
