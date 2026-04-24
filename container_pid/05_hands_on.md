# 05. 실습 예제

## 실습 환경
- Linux 호스트 또는 Docker Desktop (Mac/Windows)
- Docker 20.10+

---

## 실습 1: 좀비 프로세스 직접 확인

### 1-1. 좀비 프로세스 발생시키기

```bash
# 좀비 프로세스를 만드는 테스트 컨테이너 실행
docker run -d --name zombie-test ubuntu:22.04 bash -c "
  # 자식 프로세스를 생성하고 wait()를 호출하지 않음
  while true; do
    bash -c 'exit 0' &   # 자식 생성 후 즉시 종료
    sleep 2
  done
"

# 좀비 확인 (10초 후)
sleep 10
docker exec zombie-test ps aux
# Z 상태의 프로세스 확인

# 정리
docker rm -f zombie-test
```

### 1-2. tini로 해결

```bash
# tini 없이 실행 → 좀비 발생
docker run -d --name no-tini ubuntu:22.04 bash -c "
  while true; do bash -c 'exit 0' & sleep 1; done
"

# tini 있이 실행 → 좀비 없음
docker run -d --init --name with-tini ubuntu:22.04 bash -c "
  while true; do bash -c 'exit 0' & sleep 1; done
"

# 10초 후 비교
sleep 10
echo "=== tini 없음 ==="
docker exec no-tini ps aux | grep -c Z || echo "좀비: 0개"

echo "=== tini 있음 ==="
docker exec with-tini ps aux | grep -c Z || echo "좀비: 0개"

# 정리
docker rm -f no-tini with-tini
```

---

## 실습 2: 시그널 처리 비교

### 2-1. Shell form vs Exec form

```bash
# Shell form — SIGTERM이 sh에 전달되고 자식에게 전파 안 됨
cat > /tmp/Dockerfile.shell << 'EOF'
FROM ubuntu:22.04
RUN apt-get update -qq && apt-get install -y -qq curl
CMD sleep 300
EOF

# Exec form — SIGTERM이 sleep에 직접 전달
cat > /tmp/Dockerfile.exec << 'EOF'
FROM ubuntu:22.04
CMD ["sleep", "300"]
EOF

# 빌드 및 실행
docker build -t test-shell -f /tmp/Dockerfile.shell /tmp
docker build -t test-exec  -f /tmp/Dockerfile.exec  /tmp

docker run -d --name shell-test test-shell
docker run -d --name exec-test  test-exec

# docker stop 시간 측정
time docker stop shell-test   # 10초 후 SIGKILL (느림)
time docker stop exec-test    # 즉시 종료 (빠름)

# 정리
docker rm shell-test exec-test
docker rmi test-shell test-exec
```

### 2-2. Node.js graceful shutdown 테스트

```bash
# Node.js 서버 작성
cat > /tmp/server.js << 'EOF'
const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200);
  res.end('Hello World\n');
});

server.listen(3000, () => {
  console.log('서버 시작: port 3000');
});

// SIGTERM graceful shutdown 처리
process.on('SIGTERM', () => {
  console.log('SIGTERM 수신 — graceful shutdown 시작');
  server.close(() => {
    console.log('서버 종료 완료');
    process.exit(0);
  });
});
EOF

# Dockerfile 작성
cat > /tmp/Dockerfile.node << 'EOF'
FROM node:20-alpine
RUN apk add --no-cache tini
COPY server.js /server.js
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "/server.js"]
EOF

# 빌드 및 실행
docker build -t node-graceful -f /tmp/Dockerfile.node /tmp
docker run -d --name node-test -p 3000:3000 node-graceful

# 동작 확인
curl http://localhost:3000

# graceful shutdown 테스트
time docker stop node-test
docker logs node-test
# 출력: SIGTERM 수신 → 서버 종료 완료

# 정리
docker rm node-test
docker rmi node-graceful
```

---

## 실습 3: PID 제한 테스트

```bash
# PID 100개 제한으로 컨테이너 실행
docker run -d --name pid-limit --pids-limit 100 ubuntu:22.04 sleep 300

# 현재 PID 수 확인
docker stats --no-stream --format "PIDs: {{.PIDs}}" pid-limit

# 제한 초과 시도 (fork bomb 방어 확인)
docker exec pid-limit bash -c "
  for i in \$(seq 1 200); do sleep 10 & done
  echo '생성된 프로세스:'; ps aux | wc -l
"
# 100개 이상 생성 불가 — 오류 발생

# 정리
docker rm -f pid-limit
```

---

## 실습 4: 컨테이너 간 PID 공유 (디버깅)

```bash
# 대상 컨테이너 실행
docker run -d --name target-app nginx

# target-app의 PID 네임스페이스를 공유하는 디버그 컨테이너
docker run -it --rm \
  --pid=container:target-app \
  ubuntu:22.04 \
  ps aux
# nginx 프로세스들이 보임

# strace로 프로세스 추적 (고급)
docker run -it --rm \
  --pid=container:target-app \
  --cap-add SYS_PTRACE \
  ubuntu:22.04 bash -c "
    apt-get install -y strace -qq
    strace -p \$(pgrep nginx | head -1)
  "

# 정리
docker rm -f target-app
```

---

## 실습 5: /proc로 컨테이너 프로세스 분석

```bash
# 컨테이너 실행
docker run -d --name proc-test nginx

# 호스트에서 컨테이너 PID 확인
CONTAINER_PID=$(docker inspect proc-test --format '{{.State.Pid}}')
echo "호스트 PID: $CONTAINER_PID"

# 호스트에서 컨테이너 프로세스 정보 확인
cat /proc/$CONTAINER_PID/status | grep -E "Name|Pid|PPid|State"

# 네임스페이스 확인
ls -la /proc/$CONTAINER_PID/ns/

# cgroup 확인
cat /proc/$CONTAINER_PID/cgroup

# 컨테이너 내부에서 보이는 PID
docker exec proc-test cat /proc/1/status | grep -E "Name|Pid"
# PID: 1 (컨테이너 내부 기준)

# 정리
docker rm -f proc-test
```

---

## 체크리스트: 올바른 PID 관리

```
✅ CMD/ENTRYPOINT에 exec form 사용 (["/app/server"])
✅ --init 플래그 또는 tini/dumb-init 사용
✅ 애플리케이션에서 SIGTERM 핸들러 구현
✅ docker-compose에 stop_grace_period 설정
✅ 운영 환경에서 --pids-limit 설정
✅ 멀티 프로세스 컨테이너는 s6-overlay 또는 supervisord 사용
```
