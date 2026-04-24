# 리눅스 cgroup & namespace 교육 자료

> 컨테이너 기술의 핵심 기반인 **리눅스 cgroup**과 **namespace**를 학습합니다.
> Docker/Kubernetes가 컨테이너를 격리하고 자원을 제한하는 원리를 이해합니다.

---

## 📚 목차

| 파일 | 내용 |
|------|------|
| `01_namespace_overview.md` | 리눅스 네임스페이스 개요 및 종류 |
| `02_namespace_types.md` | 네임스페이스 종류별 상세 (PID/NET/MNT/UTS/IPC/USER) |
| `03_cgroup_overview.md` | cgroup 개요, v1 vs v2 |
| `04_cgroup_resource_limit.md` | cgroup으로 자원 제한 (CPU/Memory/I/O/PID) |
| `05_docker_integration.md` | Docker/Kubernetes에서의 namespace + cgroup 활용 |
| `06_hands_on.md` | 실습 예제 |

---

## 🎯 학습 목표

1. 리눅스 네임스페이스 6종의 역할과 격리 방식을 이해한다
2. cgroup v1과 v2의 차이를 파악한다
3. cgroup으로 CPU, Memory, I/O, PID를 직접 제한해본다
4. 네임스페이스 내 자원을 제한하는 방법을 실습한다
5. Docker/Kubernetes가 내부적으로 어떻게 활용하는지 이해한다

---

## 📋 컨테이너 = namespace + cgroup

```
컨테이너
 ├── namespace  → 격리 (무엇을 볼 수 있나?)
 │    ├── PID   → 프로세스 ID 격리
 │    ├── NET   → 네트워크 스택 격리
 │    ├── MNT   → 파일시스템 마운트 격리
 │    ├── UTS   → 호스트명/도메인 격리
 │    ├── IPC   → IPC 자원 격리
 │    └── USER  → UID/GID 격리
 │
 └── cgroup    → 제한 (얼마나 쓸 수 있나?)
      ├── cpu   → CPU 사용량 제한
      ├── memory → 메모리 사용량 제한
      ├── blkio  → 블록 I/O 제한
      └── pids   → 프로세스 수 제한
```
