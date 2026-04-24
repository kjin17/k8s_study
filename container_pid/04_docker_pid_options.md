# 04. Docker PID 관련 옵션 및 설정

## 1. --init 플래그

tini를 PID 1으로 자동 삽입합니다. 가장 간단한 좀비/시그널 문제 해결책입니다.

```bash
docker run --init -d myapp

# docker-compose.yml
services:
  app:
    image: myapp
    init: true      # --init 플래그와 동일
```

---

## 2. --pid 옵션 (PID 네임스페이스 공유)

### 호스트 PID 네임스페이스 공유

```bash
# 컨테이너가 호스트의 모든 프로세스를 볼 수 있음
docker run --pid=host -it ubuntu ps aux
# 호스트 전체 프로세스 목록이 출력됨

# 주요 사용 사례: 디버깅, 프로파일링, strace
docker run --pid=host --privileged -it nicolaka/netshoot
```

### 컨테이너 간 PID 네임스페이스 공유

```bash
# 컨테이너 A 실행
docker run -d --name app-container myapp

# 컨테이너 B가 컨테이너 A의 PID 네임스페이스 공유
docker run --pid=container:app-container -it ubuntu ps aux
# app-container 내의 프로세스가 보임

# 사용 사례: 사이드카 디버거, 프로파일러
```

```yaml
# docker-compose.yml
services:
  app:
    image: myapp

  debugger:
    image: debug-tools
    pid: "service:app"    # app 서비스의 PID 네임스페이스 공유
```

---

## 3. --pids-limit 옵션 (PID 수 제한)

컨테이너 내에서 생성할 수 있는 최대 프로세스 수를 제한합니다.
Fork Bomb 공격 방어에 유용합니다.

```bash
# 최대 100개 프로세스로 제한
docker run --pids-limit 100 -d myapp

# 현재 PID 수 확인
docker stats --no-stream --format "{{.PIDs}}" <container>

# cgroup에서 직접 확인
cat /sys/fs/cgroup/pids/docker/<container-id>/pids.current
cat /sys/fs/cgroup/pids/docker/<container-id>/pids.max
```

```yaml
# docker-compose.yml
services:
  app:
    image: myapp
    pids_limit: 100
```

---

## 4. --stop-signal 옵션

`docker stop` 시 전송할 시그널을 변경합니다.

```bash
# SIGQUIT으로 종료 (기본은 SIGTERM)
docker run --stop-signal=SIGQUIT -d nginx

# Dockerfile에서 설정
STOPSIGNAL SIGQUIT
```

---

## 5. --stop-timeout 옵션

SIGTERM 전송 후 SIGKILL로 강제 종료하기까지 대기 시간 (기본 10초)

```bash
# 30초 대기 후 SIGKILL
docker run --stop-timeout=30 -d myapp

docker stop --time=30 <container>

# docker-compose.yml
services:
  app:
    image: myapp
    stop_grace_period: 30s
    stop_signal: SIGTERM
```

---

## 6. Dockerfile STOPSIGNAL / HEALTHCHECK

```dockerfile
FROM node:20-alpine

# 종료 시그널 설정
STOPSIGNAL SIGTERM

# 헬스체크 — 비정상 시 컨테이너 재시작 트리거
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["node", "server.js"]
```

---

## 7. cgroup v2와 PID 제한 (최신 리눅스)

```bash
# cgroup v2 사용 여부 확인
stat -f -c %T /sys/fs/cgroup
# tmpfs → cgroup v1
# cgroup2fs → cgroup v2

# cgroup v2에서 컨테이너 PID 정보
ls /sys/fs/cgroup/system.slice/docker-<id>.scope/
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/pids.current
cat /sys/fs/cgroup/system.slice/docker-<id>.scope/pids.max
```

---

## 옵션 요약

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--init` | tini를 PID 1으로 사용 | false |
| `--pid=host` | 호스트 PID 네임스페이스 공유 | 격리됨 |
| `--pid=container:name` | 다른 컨테이너와 PID 공유 | 격리됨 |
| `--pids-limit` | 최대 PID 수 제한 | 무제한 |
| `--stop-signal` | docker stop 시그널 | SIGTERM |
| `--stop-timeout` | SIGKILL 전 대기 시간 | 10초 |
