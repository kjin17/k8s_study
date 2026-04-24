# 03. PID 관리 도구 및 전략

## 해결책 비교

| 도구 | 크기 | 특징 | 추천 상황 |
|------|------|------|----------|
| `tini` | ~20KB | Docker 공식 내장, 경량 init | 대부분의 경우 |
| `dumb-init` | ~25KB | Heroku 개발, 시그널 재작성 가능 | 복잡한 시그널 처리 필요 시 |
| `s6-overlay` | ~3MB | 완전한 프로세스 수퍼바이저 | 멀티 프로세스 컨테이너 |
| `bash trap` | 0KB | 추가 설치 없음 | 단순 스크립트 |

---

## 1. tini (Docker 공식 권장)

Docker에 내장된 경량 init 시스템입니다. 좀비 프로세스 제거와 시그널 전달을 처리합니다.

### 사용 방법 A: Docker --init 플래그

```bash
# 가장 간단한 방법 — tini를 자동으로 PID 1로 사용
docker run --init -d nginx

# 확인
docker exec <container> ps aux
# PID 1: /sbin/docker-init (tini)
# PID 2: nginx
```

### 사용 방법 B: Dockerfile에 직접 포함

```dockerfile
FROM ubuntu:22.04

# tini 설치
ENV TINI_VERSION=v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

COPY app /app/server

ENTRYPOINT ["/tini", "--"]
CMD ["/app/server"]
```

### 사용 방법 C: 패키지 매니저로 설치

```dockerfile
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y tini

FROM node:20-alpine
RUN apk add --no-cache tini

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]
```

### tini 동작 원리

```
[tini PID 1]
    ├── SIGTERM 수신 → 자식에게 SIGTERM 전달
    ├── 자식 프로세스 wait() 처리 → 좀비 방지
    └── 모든 자식 종료 시 tini도 종료
```

---

## 2. dumb-init

시그널 재작성(rewrite) 기능이 있어 복잡한 시그널 처리에 유용합니다.

```dockerfile
FROM python:3.11-slim
RUN pip install dumb-init

COPY app.py /app.py
ENTRYPOINT ["dumb-init", "--"]
CMD ["python", "/app.py"]
```

```bash
# 시그널 재작성 예시: SIGTERM → SIGQUIT으로 변환
ENTRYPOINT ["dumb-init", "--rewrite", "15:3", "--"]
# SIGTERM(15)을 받으면 자식에게 SIGQUIT(3) 전달
```

---

## 3. s6-overlay (멀티 프로세스 컨테이너)

여러 프로세스를 하나의 컨테이너에서 실행할 때 사용합니다.
(원칙적으로는 컨테이너당 1프로세스를 권장하지만, 레거시 환경에서 필요한 경우)

```dockerfile
FROM ubuntu:22.04
ADD https://github.com/just-containers/s6-overlay/releases/download/v3.1.6.2/s6-overlay-noarch.tar.xz /tmp/
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz

# 서비스 정의
COPY s6-services/nginx /etc/s6-overlay/s6-rc.d/nginx
COPY s6-services/app   /etc/s6-overlay/s6-rc.d/app

ENTRYPOINT ["/init"]
```

---

## 4. Shell Script에서 trap 사용

추가 도구 없이 쉘 스크립트에서 시그널을 처리합니다.

```bash
#!/bin/bash
# entrypoint.sh

# 시그널 핸들러 등록
cleanup() {
    echo "SIGTERM 수신 — graceful shutdown 시작"
    kill -TERM "$child_pid" 2>/dev/null
    wait "$child_pid"
    echo "종료 완료"
    exit 0
}
trap cleanup SIGTERM SIGINT

# 앱 실행 (백그라운드)
/app/server &
child_pid=$!

# 자식 프로세스 대기 (wait가 없으면 시그널 못 받음)
wait "$child_pid"
```

```dockerfile
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

---

## 언어별 시그널 처리 구현

### Node.js
```javascript
process.on('SIGTERM', async () => {
  console.log('SIGTERM 수신 — 서버 종료 중...');
  server.close(() => {
    console.log('HTTP 서버 종료');
    process.exit(0);
  });
});
```

### Python
```python
import signal, sys

def handle_sigterm(signum, frame):
    print("SIGTERM 수신 — 종료 중...")
    # 정리 작업
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)
```

### Go
```go
quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
<-quit
log.Println("SIGTERM 수신 — shutdown 시작")
// graceful shutdown 로직
```
