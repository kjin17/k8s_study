# 컨테이너 PID 관리 교육 자료

> 리눅스 환경에서 Docker 컨테이너가 PID(Process ID)를 관리하는 방법을 학습합니다.

---

## 📚 목차

| 파일 | 내용 |
|------|------|
| `01_linux_pid_namespace.md` | 리눅스 PID 네임스페이스 개념 |
| `02_container_pid1.md` | 컨테이너의 PID 1 (init 프로세스) 문제 |
| `03_pid_management.md` | PID 관리 도구 및 전략 (tini, dumb-init) |
| `04_docker_pid_options.md` | Docker PID 관련 옵션 및 설정 |
| `05_hands_on.md` | 실습 예제 |

---

## 🎯 학습 목표

1. 리눅스 PID 네임스페이스와 컨테이너 격리 원리를 이해한다
2. 컨테이너 PID 1 문제(좀비 프로세스, 시그널 처리)를 파악한다
3. tini, dumb-init 등 init 시스템 도구 활용법을 익힌다
4. `--pid` 옵션으로 네임스페이스를 공유/격리하는 방법을 실습한다

---

## 📋 사전 지식

- 리눅스 기본 명령어 (ps, kill, top)
- Docker 기본 사용법
- 프로세스/시그널 기본 개념
