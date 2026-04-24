# 04. cgroup으로 자원 제한하기

## 사전 준비

```bash
# cgroup v2 사용 여부 확인
stat -fc %T /sys/fs/cgroup
# cgroup2fs → v2 기준으로 진행

# cgcreate 도구 설치 (선택)
sudo apt-get install -y cgroup-tools   # Ubuntu/Debian
sudo yum install -y libcgroup-tools    # RHEL/CentOS
```

---

## 1. CPU 제한

### cgroup v2 방식

```bash
# 새 cgroup 생성
sudo mkdir /sys/fs/cgroup/myapp

# CPU 제한 설정 — cpu.max: "quota period"
# 100000us(0.1초) 중 50000us(0.05초)만 사용 → 1코어의 50%
sudo echo "50000 100000" > /sys/fs/cgroup/myapp/cpu.max

# 특정 CPU 코어만 사용 (cpuset)
sudo echo "0-1" > /sys/fs/cgroup/myapp/cpuset.cpus
sudo echo "0"   > /sys/fs/cgroup/myapp/cpuset.mems

# 프로세스를 cgroup에 추가
echo $$ > /sys/fs/cgroup/myapp/cgroup.procs

# 확인
cat /sys/fs/cgroup/myapp/cpu.max
# 50000 100000
```

### cgroup v1 방식

```bash
# cpu.cfs_quota_us / cpu.cfs_period_us
sudo mkdir /sys/fs/cgroup/cpu/myapp
sudo echo 50000  > /sys/fs/cgroup/cpu/myapp/cpu.cfs_quota_us   # 50ms
sudo echo 100000 > /sys/fs/cgroup/cpu/myapp/cpu.cfs_period_us  # 100ms period

# cpu.shares — 상대적 가중치 (기본 1024)
sudo echo 512 > /sys/fs/cgroup/cpu/myapp/cpu.shares   # 다른 그룹의 절반
```

### CPU 사용률 모니터링

```bash
# cpu.stat 읽기
cat /sys/fs/cgroup/myapp/cpu.stat
# usage_usec       123456789    ← 총 CPU 사용 시간 (마이크로초)
# user_usec        98765432
# system_usec      24691357
# throttled_usec   5000000      ← 쓰로틀링된 시간 (제한 초과)
# nr_throttled     42           ← 쓰로틀링 발생 횟수
```

---

## 2. 메모리 제한

### cgroup v2 방식

```bash
sudo mkdir /sys/fs/cgroup/myapp

# 메모리 최대 사용량 제한 (256MB)
sudo echo "268435456" > /sys/fs/cgroup/myapp/memory.max
# 또는
sudo echo "256M" > /sys/fs/cgroup/myapp/memory.max

# 메모리 + 스왑 합산 제한
sudo echo "512M" > /sys/fs/cgroup/myapp/memory.swap.max

# OOM killer 비활성화 (제한 초과 시 프로세스 kill 대신 대기)
sudo echo "1" > /sys/fs/cgroup/myapp/memory.oom.group

# 현재 메모리 사용량 확인
cat /sys/fs/cgroup/myapp/memory.current
cat /sys/fs/cgroup/myapp/memory.stat
```

### cgroup v1 방식

```bash
sudo mkdir /sys/fs/cgroup/memory/myapp

# 메모리 제한
sudo echo 268435456 > /sys/fs/cgroup/memory/myapp/memory.limit_in_bytes

# 스왑 포함 제한
sudo echo 536870912 > /sys/fs/cgroup/memory/myapp/memory.memsw.limit_in_bytes

# OOM 동작 설정
sudo echo 0 > /sys/fs/cgroup/memory/myapp/memory.oom_control
# 0 = OOM killer 활성화 (기본)
# 1 = OOM killer 비활성화 (프로세스 일시정지)
```

### 메모리 통계 읽기

```bash
cat /sys/fs/cgroup/myapp/memory.stat
# anon            104857600   ← 익명 메모리 (힙, 스택)
# file            52428800    ← 파일 캐시
# slab            8388608     ← 커널 슬랩 캐시
# pgfault         1234        ← 페이지 폴트 수
# oom_kill        0           ← OOM kill 횟수
```

---

## 3. 블록 I/O 제한

### cgroup v2 방식

```bash
# 디바이스 번호 확인
ls -la /dev/sda
# brw-rw---- 8, 0  ← 8:0 이 메이저:마이너 번호

# io.max 설정: "major:minor rbps=<읽기속도> wbps=<쓰기속도> riops=<읽기IOPS> wiops=<쓰기IOPS>"
sudo echo "8:0 rbps=10485760 wbps=10485760" > /sys/fs/cgroup/myapp/io.max
# 읽기/쓰기 각 10MB/s로 제한

# IOPS 제한
sudo echo "8:0 riops=1000 wiops=1000" > /sys/fs/cgroup/myapp/io.max

# I/O 통계
cat /sys/fs/cgroup/myapp/io.stat
# 8:0 rbytes=... wbytes=... rios=... wios=...
```

### cgroup v1 방식

```bash
sudo mkdir /sys/fs/cgroup/blkio/myapp

# 읽기 속도 제한 (10MB/s)
sudo echo "8:0 10485760" > /sys/fs/cgroup/blkio/myapp/blkio.throttle.read_bps_device

# 쓰기 속도 제한
sudo echo "8:0 10485760" > /sys/fs/cgroup/blkio/myapp/blkio.throttle.write_bps_device

# IOPS 제한
sudo echo "8:0 1000" > /sys/fs/cgroup/blkio/myapp/blkio.throttle.read_iops_device
sudo echo "8:0 1000" > /sys/fs/cgroup/blkio/myapp/blkio.throttle.write_iops_device
```

---

## 4. PID 수 제한

```bash
# cgroup v2
sudo echo "100" > /sys/fs/cgroup/myapp/pids.max

# 현재 PID 수 확인
cat /sys/fs/cgroup/myapp/pids.current

# cgroup v1
sudo mkdir /sys/fs/cgroup/pids/myapp
sudo echo 100 > /sys/fs/cgroup/pids/myapp/pids.max
```

---

## 5. 네임스페이스 내 자원 제한 (통합)

namespace + cgroup을 조합하여 완전히 격리된 환경에서 자원을 제한합니다.

```bash
#!/bin/bash
# namespace + cgroup 조합 스크립트

CGROUP_NAME="isolated-app"
CGROUP_PATH="/sys/fs/cgroup/$CGROUP_NAME"

# 1. cgroup 생성 및 자원 제한 설정
sudo mkdir -p $CGROUP_PATH
sudo echo "100000 200000" > $CGROUP_PATH/cpu.max     # CPU 50%
sudo echo "256M"          > $CGROUP_PATH/memory.max  # 메모리 256MB
sudo echo "50"            > $CGROUP_PATH/pids.max    # 프로세스 50개

# 2. 새 네임스페이스에서 프로세스 실행 + cgroup 적용
sudo unshare --pid --net --mount --uts --fork --mount-proc \
    bash -c "
        # 현재 프로세스를 cgroup에 등록
        echo \$\$ > $CGROUP_PATH/cgroup.procs
        
        # 호스트명 설정
        hostname isolated-container
        
        # 실제 앱 실행
        exec /path/to/app
    "
```

---

## systemd를 통한 cgroup 자원 제한

```bash
# 서비스에 CPU/메모리 제한 적용
sudo systemctl set-property docker.service CPUQuota=50%
sudo systemctl set-property docker.service MemoryMax=4G

# 또는 unit 파일에 직접 설정
# /etc/systemd/system/myapp.service
[Service]
CPUQuota=50%
MemoryMax=512M
TasksMax=100
IOReadBandwidthMax=/dev/sda 10M
IOWriteBandwidthMax=/dev/sda 10M
```

---

## 자원 제한 확인 명령어 모음

```bash
# 전체 cgroup 트리와 자원 사용량
systemd-cgtop -d 1

# 특정 cgroup 상세 확인
systemd-cgls /system.slice/docker.service

# 프로세스가 속한 cgroup 확인
cat /proc/<PID>/cgroup

# cgroup v2 전체 설정 확인
cat /sys/fs/cgroup/<group>/cpu.max
cat /sys/fs/cgroup/<group>/memory.max
cat /sys/fs/cgroup/<group>/pids.max
cat /sys/fs/cgroup/<group>/io.max
```
