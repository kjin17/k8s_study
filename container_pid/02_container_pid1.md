# 02. 컨테이너의 PID 1 문제

## PID 1의 특별한 역할

리눅스에서 PID 1은 **init 프로세스**로 시스템 전체의 최상위 프로세스입니다.
컨테이너에서 첫 번째로 실행되는 프로세스가 PID 1이 됩니다.

PID 1은 일반 프로세스와 다른 특수한 책임이 있습니다:

1. **고아 프로세스(Orphan Process) 입양** — 부모가 죽은 자식 프로세스를 맡아 정리
2. **좀비 프로세스(Zombie Process) 회수** — `wait()` 시스템 콜로 종료된 자식을 정리
3. **시그널 처리** — SIGTERM, SIGINT 등 시그널에 반응하여 graceful shutdown

---

## 문제 1: 좀비 프로세스 (Zombie Process)

### 발생 원인
자식 프로세스가 종료되면 부모가 `wait()`를 호출해야 PCB(프로세스 제어 블록)가 정리됩니다.
PID 1이 `wait()`를 호출하지 않으면 좀비 프로세스가 쌓입니다.

```
[컨테이너 PID 1: 앱 프로세스]
    ├── [자식 PID 2: 작업 스레드] → 종료 → 좀비(Z) 상태 대기
    ├── [자식 PID 3: 작업 스레드] → 종료 → 좀비(Z) 상태 대기
    └── wait()를 호출하지 않으면 영원히 쌓임
```

```bash
# 좀비 프로세스 확인
docker exec <container> ps aux | grep 'Z'
# 상태가 'Z'인 프로세스 = 좀비

# 또는
docker exec <container> cat /proc/PID/status | grep State
# State: Z (zombie)
```

### 실제 발생 예시

```dockerfile
# 잘못된 예: 쉘 스크립트가 PID 1
FROM ubuntu
COPY start.sh /start.sh
CMD ["/bin/sh", "/start.sh"]   # sh가 PID 1 → 자식 좀비 미처리
```

```bash
#!/bin/sh
# start.sh
/app/worker &        # 백그라운드 자식 프로세스 생성
/app/server          # 서버 실행
# worker 종료 시 sh(PID 1)가 wait() 안 하면 좀비 발생
```

---

## 문제 2: 시그널 전달 문제

### SIGTERM이 전달되지 않는 경우

```bash
docker stop <container>
# Docker는 PID 1에 SIGTERM 전송 → 10초 후 SIGKILL
```

**Shell form CMD 문제:**
```dockerfile
# 문제 있는 방법 (shell form)
CMD /app/server
# 실제 실행: /bin/sh -c "/app/server"
# sh(PID 1) → server(PID 2)
# SIGTERM이 sh에 전달되지만 sh는 자식에게 전달 안 함 → SIGKILL로 강제 종료
```

**Exec form 해결:**
```dockerfile
# 올바른 방법 (exec form)
CMD ["/app/server"]
# server가 직접 PID 1 → SIGTERM 직접 수신 → graceful shutdown
```

---

## 문제 3: 고아 프로세스 처리

PID 1이 죽으면 컨테이너 전체가 종료됩니다.
고아 프로세스가 발생해도 호스트의 init(systemd)이 처리하지 못하고,
컨테이너 내에서 처리해야 합니다.

```bash
# 고아 프로세스 시뮬레이션
docker exec <container> bash -c "
  bash -c 'sleep 100 &'   # 고아가 될 프로세스
  exit                     # 부모 종료
"
# sleep이 PID 1의 자식으로 입양됨
# PID 1이 이를 처리할 수 없으면 좀비로 남음
```

---

## 언어/프레임워크별 시그널 처리 현황

| 언어/런타임 | 기본 시그널 처리 | 비고 |
|------------|----------------|------|
| Go | ✅ 양호 | 직접 signal.Notify 처리 가능 |
| Node.js | ⚠️ 주의 | process.on('SIGTERM') 구현 필요 |
| Python | ⚠️ 주의 | signal.signal() 구현 필요 |
| Java (JVM) | ⚠️ 주의 | ShutdownHook 등록 필요 |
| Nginx | ✅ 양호 | SIGTERM graceful shutdown 지원 |
| Shell script | ❌ 위험 | trap 미구현 시 자식 미처리 |
