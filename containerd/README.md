# containerd & containerd-shim 교육 자료

> Kubernetes의 기본 컨테이너 런타임인 **containerd**와
> 컨테이너 생명주기를 관리하는 **containerd-shim**의 아키텍처와 동작 원리를 학습합니다.

---

## 📚 목차

| 파일 | 내용 |
|------|------|
| `01_containerd_overview.md` | containerd 개요 및 아키텍처 |
| `02_containerd_components.md` | containerd 핵심 컴포넌트 상세 |
| `03_containerd_shim.md` | containerd-shim 동작 원리 및 역할 |
| `04_cri_interface.md` | CRI(Container Runtime Interface)와 containerd |
| `05_containerd_vs_others.md` | containerd vs Docker vs CRI-O 비교 |
| `06_hands_on.md` | 실습 예제 (ctr, crictl, nerdctl) |

---

## 🎯 학습 목표

1. containerd가 Kubernetes 에코시스템에서 하는 역할을 이해한다
2. containerd-shim이 왜 필요한지, 어떻게 동작하는지 파악한다
3. CRI 인터페이스를 통해 kubelet과 containerd가 통신하는 방식을 이해한다
4. ctr, crictl, nerdctl CLI 도구를 활용해 컨테이너를 직접 관리한다

---

## 컨테이너 런타임 계층 구조

```
kubectl
  │
kubelet
  │ CRI (gRPC)
containerd  ←── 고수준 런타임 (High-level Runtime)
  │
containerd-shim
  │
runc          ←── 저수준 런타임 (Low-level Runtime, OCI)
  │
컨테이너 프로세스
```
