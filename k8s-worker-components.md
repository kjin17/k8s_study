# Kubernetes 워커 노드(Worker Node) 핵심 컴포넌트 교육

> Kubernetes 클러스터에서 **실제 워크로드를 실행하는** 워커 노드의 핵심 컴포넌트를 다룹니다.
> kubelet, Container Runtime(containerd), kube-proxy, DaemonSet의 역할과 동작 원리를 이해하고, crictl을 활용한 노드 수준 트러블슈팅까지 다룹니다.

---

## 목차

1. [워커 노드 개요](#1-워커-노드-개요)
2. [kubelet](#2-kubelet)
3. [Container Runtime과 containerd](#3-container-runtime과-containerd)
4. [CRI (Container Runtime Interface)](#4-cri-container-runtime-interface)
5. [kube-proxy](#5-kube-proxy)
6. [DaemonSet](#6-daemonset)
7. [Pod의 생명주기와 워커 노드](#7-pod의-생명주기와-워커-노드)
8. [crictl — 컨테이너 런타임 디버깅 도구](#8-crictl--컨테이너-런타임-디버깅-도구)
9. [워커 노드 트러블슈팅 가이드](#9-워커-노드-트러블슈팅-가이드)
10. [실습: 워커 노드 동작 확인](#10-실습-워커-노드-동작-확인)
11. [정리 및 핵심 요약](#11-정리-및-핵심-요약)

---

## 1. 워커 노드 개요

### 한 문장 정의

> **워커 노드(Worker Node)**는 Control Plane의 지시를 받아 **실제 컨테이너를 실행하고 관리하는 노드**입니다. 사용자의 애플리케이션이 실행되는 곳이 바로 워커 노드입니다.

### 비유로 이해하기

```
┌─────────────────────────────────────────────────────────────┐
│                    공장 비유                                   │
│                                                             │
│   Control Plane = 본사 (경영/기획)                             │
│   ┌─────────────────┐                                        │
│   │  본사            │  "A 제품 3개, B 제품 5개 생산해라"       │
│   │  (Master Node)  │                                        │
│   └────────┬────────┘                                        │
│            │ 생산 지시                                        │
│            ▼                                                 │
│   Worker Node = 공장 (실제 생산)                               │
│   ┌─────────────────────────────────────────────────────┐    │
│   │                                                     │    │
│   │  ┌────────────┐  공장장: kubelet                     │    │
│   │  │  kubelet   │  "본사 지시를 받아 생산 라인을 관리"    │    │
│   │  └─────┬──────┘                                     │    │
│   │        │ 생산 지시                                   │    │
│   │        ▼                                             │    │
│   │  ┌────────────┐  생산 라인: containerd               │    │
│   │  │ containerd │  "실제 제품(컨테이너)을 만드는 기계"    │    │
│   │  └─────┬──────┘                                     │    │
│   │        │                                             │    │
│   │        ▼                                             │    │
│   │  ┌─────┐ ┌─────┐ ┌─────┐  제품(컨테이너)             │    │
│   │  │Pod-1│ │Pod-2│ │Pod-3│                             │    │
│   │  └─────┘ └─────┘ └─────┘                             │    │
│   │                                                     │    │
│   │  ┌────────────┐  물류 담당: kube-proxy               │    │
│   │  │ kube-proxy │  "제품 배송 경로를 관리"                │    │
│   │  └────────────┘                                     │    │
│   │                                                     │    │
│   └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 워커 노드 컴포넌트 전체 구조

```
┌──────────────────── Worker Node ─────────────────────────────┐
│                                                              │
│  ┌────────────────────────────────────────────────────────┐   │
│  │                     kubelet                            │   │
│  │                                                        │   │
│  │  • API Server와 통신 (Pod 스펙 수신, 상태 보고)          │   │
│  │  • Pod 생명주기 관리 (생성, 삭제, 재시작)                 │   │
│  │  • 헬스 체크 (liveness, readiness, startup probe)       │   │
│  │  • 볼륨 마운트/언마운트                                  │   │
│  │  • 리소스 모니터링 (cAdvisor 내장)                       │   │
│  │                                                        │   │
│  └───────────┬───────────────────────────────┬────────────┘   │
│              │ CRI (gRPC)                    │                │
│              ▼                               │                │
│  ┌────────────────────────┐                  │                │
│  │     containerd         │                  │                │
│  │                        │                  │                │
│  │  • 이미지 Pull/관리     │                  │                │
│  │  • 컨테이너 생성/실행   │                  │                │
│  │  • 스냅샷 관리          │                  │                │
│  └───────────┬────────────┘                  │                │
│              │ OCI Runtime                   │                │
│              ▼                               │                │
│  ┌────────────────────────┐                  │                │
│  │       runc             │                  │                │
│  │  (저수준 런타임)        │                  │                │
│  │  • namespace 생성      │                  │                │
│  │  • cgroup 설정         │                  │                │
│  │  • 프로세스 실행        │                  │                │
│  └───────────┬────────────┘                  │                │
│              │                               │                │
│              ▼                               │                │
│  ┌────────────────────────────────────────┐   │                │
│  │              Pod들                      │   │                │
│  │  ┌──────┐  ┌──────┐  ┌──────┐          │   │                │
│  │  │ C1   │  │ C2   │  │ C3   │  ...     │   │                │
│  │  └──────┘  └──────┘  └──────┘          │   │                │
│  └────────────────────────────────────────┘   │                │
│                                               │                │
│  ┌────────────────────────────────────────────┘                │
│  │                                                            │
│  ▼                                                            │
│  ┌────────────────────────────────────────────────────────┐   │
│  │                    kube-proxy                           │   │
│  │                                                        │   │
│  │  • Service → Pod 트래픽 규칙 관리                        │   │
│  │  • iptables 또는 IPVS 규칙 설정                          │   │
│  │  • 노드 포트 리스닝 (NodePort Service)                   │   │
│  └────────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌── DaemonSet으로 배포되는 컴포넌트들 ─────────────────────┐   │
│  │  CNI Plugin (Calico/Cilium/Antrea)                      │   │
│  │  Log Agent (Fluent Bit)                                 │   │
│  │  Monitoring Agent (node-exporter)                       │   │
│  │  CSI Node Plugin (vSphere CSI Node)                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### 컴포넌트 요약

| 컴포넌트 | 실행 방식 | 역할 | 비유 |
|---------|----------|------|------|
| **kubelet** | 시스템 서비스 (systemd) | Pod 생명주기 관리, API Server와 통신 | 공장장 |
| **containerd** | 시스템 서비스 (systemd) | 컨테이너 이미지/실행 관리 | 생산 기계 |
| **runc** | 바이너리 (containerd가 호출) | 리눅스 커널 기능으로 컨테이너 격리 실행 | 기계 부품 |
| **kube-proxy** | DaemonSet (Pod) | Service 네트워크 규칙 관리 | 물류 담당 |
| **CNI Plugin** | DaemonSet (Pod) | Pod 네트워크 연결 | 통신 인프라 |

---

## 2. kubelet

### 역할

> **kubelet**은 각 워커 노드에서 실행되는 **에이전트**로, API Server로부터 Pod 스펙을 받아 **컨테이너가 정상적으로 실행되도록 관리하는** 워커 노드의 핵심 프로세스입니다.

```
┌─────────────────────────────────────────────────────────────┐
│                kubelet의 핵심 역할 7가지                       │
│                                                             │
│  ① Pod 관리                                                  │
│     API Server에서 할당된 Pod 스펙 수신 → 컨테이너 실행         │
│                                                             │
│  ② 상태 보고                                                  │
│     Pod 상태, 노드 상태를 주기적으로 API Server에 보고           │
│                                                             │
│  ③ 헬스 체크 실행                                              │
│     liveness/readiness/startup probe 실행 → 실패 시 재시작    │
│                                                             │
│  ④ 볼륨 관리                                                  │
│     CSI 드라이버와 연동하여 볼륨 마운트/언마운트                 │
│                                                             │
│  ⑤ 이미지 관리                                                │
│     Container Runtime에 이미지 Pull 요청                      │
│                                                             │
│  ⑥ 리소스 모니터링                                             │
│     내장 cAdvisor로 컨테이너 CPU/메모리/디스크 사용량 수집       │
│                                                             │
│  ⑦ Static Pod 관리                                            │
│     /etc/kubernetes/manifests/ 디렉터리의 YAML을 직접 실행     │
│     (Control Plane 컴포넌트가 이 방식으로 실행됨)               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### kubelet의 동작 흐름

```
┌─────────────────────────────────────────────────────────────┐
│                kubelet 동작 루프                               │
│                                                             │
│  ┌───────────────┐                                          │
│  │  API Server   │  Watch: "이 노드에 할당된 Pod 목록"        │
│  └───────┬───────┘                                          │
│          │                                                  │
│          ▼                                                  │
│  ┌───────────────────────────────────────────────────┐      │
│  │                   kubelet                          │      │
│  │                                                   │      │
│  │  1. 원하는 상태 수신                                │      │
│  │     "nginx Pod를 실행해야 한다"                      │      │
│  │                │                                   │      │
│  │                ▼                                   │      │
│  │  2. 현재 상태 확인                                  │      │
│  │     "현재 이 노드에 nginx Pod가 없다"                │      │
│  │                │                                   │      │
│  │                ▼                                   │      │
│  │  3. 차이 해소 (Reconciliation)                     │      │
│  │     ├── 이미지 Pull (없으면)                        │      │
│  │     ├── 볼륨 마운트 (필요하면)                       │      │
│  │     ├── 샌드박스(Pause 컨테이너) 생성                │      │
│  │     ├── CNI 호출 → 네트워크 설정                     │      │
│  │     └── 앱 컨테이너 생성 및 시작                     │      │
│  │                │                                   │      │
│  │                ▼                                   │      │
│  │  4. 상태 보고                                      │      │
│  │     "nginx Pod: Running, 컨테이너 Ready"             │      │
│  │     → API Server에 전송                             │      │
│  │                │                                   │      │
│  │                ▼                                   │      │
│  │  5. 지속적 모니터링                                 │      │
│  │     ├── Probe 실행 (liveness, readiness)            │      │
│  │     ├── 리소스 사용량 수집 (cAdvisor)                │      │
│  │     └── 컨테이너 크래시 → 재시작 (restartPolicy)     │      │
│  │                                                   │      │
│  │  이 루프를 약 10초 간격으로 반복                      │      │
│  └───────────────────────────────────────────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 노드 상태 보고 (Node Status)

```
┌─────────────────────────────────────────────────────────────┐
│          kubelet이 API Server에 보고하는 노드 정보              │
│                                                             │
│  kubectl describe node worker-1 로 확인 가능                  │
│                                                             │
│  ┌─── Conditions (상태) ───────────────────────────────┐     │
│  │                                                     │     │
│  │  Ready            : True   ← 정상 동작 중             │     │
│  │  MemoryPressure   : False  ← 메모리 부족 아님          │     │
│  │  DiskPressure     : False  ← 디스크 부족 아님          │     │
│  │  PIDPressure      : False  ← PID 부족 아님            │     │
│  │  NetworkUnavailable: False  ← 네트워크 정상            │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  ┌─── Capacity / Allocatable ──────────────────────────┐     │
│  │                                                     │     │
│  │  Capacity (전체):      Allocatable (Pod에 할당 가능): │     │
│  │  cpu: 4               cpu: 3800m                    │     │
│  │  memory: 16Gi         memory: 15Gi                  │     │
│  │  pods: 110            pods: 110                     │     │
│  │  ephemeral-storage:   ephemeral-storage:            │     │
│  │    100Gi                95Gi                        │     │
│  │                                                     │     │
│  │  ※ 차이 = kubelet/OS 예약분 (system-reserved)       │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  ┌─── Node Info ───────────────────────────────────────┐     │
│  │                                                     │     │
│  │  OS: Linux (Ubuntu 22.04)                           │     │
│  │  Kernel: 5.15.0-78-generic                          │     │
│  │  Container Runtime: containerd://1.7.2              │     │
│  │  Kubelet Version: v1.31.0                           │     │
│  │  Architecture: amd64                                │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  Heartbeat: kubelet은 10초마다 Lease 오브젝트를 갱신하여       │
│  자신이 살아있음을 API Server에 알림                            │
│  (40초 이상 미응답 시 Node Controller가 NotReady 처리)         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### kubelet 설정 확인

```bash
# kubelet 프로세스 상태 확인
sudo systemctl status kubelet

# kubelet 설정 파일 위치
cat /var/lib/kubelet/config.yaml

# 주요 설정 항목:
# clusterDNS:           CoreDNS Service IP (보통 10.96.0.10)
# clusterDomain:        cluster.local
# staticPodPath:        /etc/kubernetes/manifests
# containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
# cgroupDriver:         systemd
# maxPods:              110 (노드당 최대 Pod 수)
# nodeStatusUpdateFrequency: 10s (상태 보고 주기)
# evictionHard:         메모리/디스크 임계치 초과 시 Pod 축출
#   memory.available:   100Mi
#   nodefs.available:   10%
#   imagefs.available:  15%

# kubelet 로그 확인
sudo journalctl -u kubelet -f --no-pager -l
sudo journalctl -u kubelet --since "10 minutes ago"
```

### Probe (헬스 체크)

```
┌─────────────────────────────────────────────────────────────┐
│          kubelet이 실행하는 3가지 Probe                        │
│                                                             │
│  ┌─── Liveness Probe ──────────────────────────────────┐    │
│  │                                                      │    │
│  │  "컨테이너가 살아있는가?"                               │    │
│  │  실패 시 → 컨테이너 재시작 (kill + restart)             │    │
│  │                                                      │    │
│  │  예: 앱이 데드락에 빠져서 응답 불가 → 재시작으로 복구     │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── Readiness Probe ─────────────────────────────────┐    │
│  │                                                      │    │
│  │  "트래픽을 받을 준비가 됐는가?"                          │    │
│  │  실패 시 → Service Endpoints에서 제거 (트래픽 차단)     │    │
│  │  컨테이너는 재시작하지 않음!                             │    │
│  │                                                      │    │
│  │  예: 앱 초기화 중이거나 DB 연결 대기 중 → 트래픽 차단     │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── Startup Probe ──────────────────────────────────┐     │
│  │                                                      │    │
│  │  "앱이 처음 시작하는 데 시간이 오래 걸리는가?"            │    │
│  │  성공할 때까지 liveness/readiness 비활성화               │    │
│  │  실패 시 → 컨테이너 재시작                               │    │
│  │                                                      │    │
│  │  예: Java 앱 기동 시 30초 이상 소요 → 그 동안 보호        │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  Probe 방식:                                                 │
│  ├── httpGet:  HTTP 요청 → 200~399 응답이면 성공              │
│  ├── tcpSocket: TCP 포트 연결 → 연결 성공이면 성공             │
│  └── exec:     컨테이너 내 명령 실행 → exit code 0이면 성공    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

```yaml
# Probe 설정 예시
apiVersion: v1
kind: Pod
metadata:
  name: probe-demo
spec:
  containers:
  - name: app
    image: my-app:1.0
    ports:
    - containerPort: 8080

    # Startup Probe: 앱 기동 대기 (최대 5분)
    startupProbe:
      httpGet:
        path: /healthz
        port: 8080
      failureThreshold: 30     # 30번 실패 허용
      periodSeconds: 10        # 10초 간격 → 최대 300초(5분)

    # Liveness Probe: 앱 생존 확인
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 0   # startup probe 이후이므로 0
      periodSeconds: 10        # 10초 간격
      failureThreshold: 3      # 3번 연속 실패 시 재시작

    # Readiness Probe: 트래픽 수신 준비 확인
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      periodSeconds: 5         # 5초 간격
      failureThreshold: 3      # 3번 실패 시 Endpoints에서 제거
```

### Static Pod

```
┌─────────────────────────────────────────────────────────────┐
│                    Static Pod란?                              │
│                                                             │
│  kubelet이 API Server 없이 직접 관리하는 Pod                   │
│  /etc/kubernetes/manifests/ 디렉터리에 YAML 파일을 놓으면      │
│  kubelet이 자동으로 Pod를 생성/관리                             │
│                                                             │
│  ┌─── /etc/kubernetes/manifests/ ──────────────────────┐     │
│  │                                                     │     │
│  │  etcd.yaml                    ← etcd Pod             │     │
│  │  kube-apiserver.yaml          ← API Server Pod       │     │
│  │  kube-controller-manager.yaml ← Controller Manager   │     │
│  │  kube-scheduler.yaml          ← Scheduler Pod        │     │
│  │                                                     │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  특징:                                                       │
│  ├── API Server가 다운되어도 kubelet이 독립적으로 실행          │
│  ├── kubectl에서 보이지만 삭제 불가 (Mirror Pod)              │
│  ├── YAML 파일 수정 시 kubelet이 자동 재시작                   │
│  ├── YAML 파일 삭제 시 Pod 자동 제거                           │
│  └── Control Plane 컴포넌트가 이 방식으로 실행됨               │
│                                                             │
│  활용:                                                       │
│  ├── Control Plane 컴포넌트 실행 (kubeadm 기본 방식)          │
│  └── API Server 없이도 실행해야 하는 중요 에이전트              │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Container Runtime과 containerd

### Container Runtime의 역할

> **Container Runtime**은 kubelet의 요청을 받아 **실제 컨테이너를 생성, 시작, 중지, 삭제하는** 소프트웨어입니다. Kubernetes에서 가장 널리 사용되는 런타임은 **containerd**입니다.

### Container Runtime 계층 구조

```
┌─────────────────────────────────────────────────────────────┐
│              Container Runtime 계층 구조                       │
│                                                             │
│  ┌──────────────────────┐                                   │
│  │       kubelet        │  "Pod를 실행해줘"                   │
│  └──────────┬───────────┘                                   │
│             │ CRI (gRPC)                                    │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │  고수준 런타임         │  containerd, CRI-O               │
│  │  (High-Level)        │                                   │
│  │                      │  이미지 관리, 스냅샷,               │
│  │                      │  네트워크, 스토리지 관리             │
│  └──────────┬───────────┘                                   │
│             │ OCI Runtime Spec                              │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │  저수준 런타임         │  runc, crun, kata-containers     │
│  │  (Low-Level)         │                                   │
│  │                      │  리눅스 커널 기능을 사용하여          │
│  │                      │  실제 프로세스 격리 실행              │
│  │                      │  (namespace, cgroup, seccomp)     │
│  └──────────┬───────────┘                                   │
│             │                                               │
│             ▼                                               │
│  ┌──────────────────────┐                                   │
│  │  리눅스 커널           │  namespace, cgroup, overlay FS   │
│  └──────────────────────┘                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### containerd 상세

```
┌─────────────────────────────────────────────────────────────┐
│                    containerd 구조                             │
│                                                             │
│  ┌─── containerd (데몬) ──────────────────────────────┐     │
│  │                                                     │     │
│  │  ┌───────────────┐  ┌───────────────┐               │     │
│  │  │  CRI Plugin   │  │ Image Service │               │     │
│  │  │               │  │               │               │     │
│  │  │ kubelet에서   │  │ 이미지 Pull    │               │     │
│  │  │ 오는 gRPC     │  │ 이미지 저장    │               │     │
│  │  │ 요청 처리     │  │ 이미지 삭제    │               │     │
│  │  └───────────────┘  └───────────────┘               │     │
│  │                                                     │     │
│  │  ┌───────────────┐  ┌───────────────┐               │     │
│  │  │  Container    │  │  Snapshotter  │               │     │
│  │  │  Service      │  │               │               │     │
│  │  │               │  │ 이미지 레이어  │               │     │
│  │  │ 컨테이너 생성 │  │ 관리 (overlay │               │     │
│  │  │ 시작/중지/삭제│  │  fs 등)       │               │     │
│  │  └───────┬───────┘  └───────────────┘               │     │
│  │          │                                          │     │
│  │          │ OCI 호출                                  │     │
│  │          ▼                                          │     │
│  │  ┌───────────────┐                                  │     │
│  │  │  containerd   │  runc 바이너리를 실행하여          │     │
│  │  │  -shim-runc   │  컨테이너 프로세스 관리            │     │
│  │  │  -v2          │  (1 shim = 1 컨테이너 그룹)       │     │
│  │  └───────┬───────┘                                  │     │
│  │          │                                          │     │
│  │          ▼                                          │     │
│  │  ┌───────────────┐                                  │     │
│  │  │     runc      │  실제 컨테이너 프로세스 생성       │     │
│  │  └───────────────┘                                  │     │
│  │                                                     │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                             │
│  containerd-shim의 역할:                                      │
│  ├── runc가 컨테이너 생성 후 종료되면 shim이 부모 프로세스 역할 │
│  ├── containerd가 재시작되어도 컨테이너는 계속 실행             │
│  └── stdin/stdout/stderr 스트림 관리                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### containerd vs Docker vs CRI-O 비교

```
┌─────────────────────────────────────────────────────────────┐
│              Container Runtime 변천사                         │
│                                                             │
│  K8s 1.24 이전: Docker(dockershim) 사용 가능                  │
│  K8s 1.24 이후: dockershim 제거! containerd/CRI-O만 지원     │
│                                                             │
│  ┌─── Docker 방식 (K8s 1.24 이전, deprecated) ──────────┐   │
│  │                                                       │   │
│  │  kubelet → dockershim → Docker Engine → containerd    │   │
│  │                                       → runc          │   │
│  │                                                       │   │
│  │  불필요한 계층이 많음 (Docker CLI, Docker API 등)       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── containerd 방식 (현재 주류) ─────────────────────┐     │
│  │                                                       │   │
│  │  kubelet → containerd (CRI Plugin) → runc             │   │
│  │                                                       │   │
│  │  ✅ 간결한 구조, 낮은 오버헤드                          │   │
│  │  ✅ Docker 이미지와 100% 호환 (OCI 표준)               │   │
│  │  ✅ 가장 널리 사용됨                                    │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─── CRI-O 방식 ────────────────────────────────────┐      │
│  │                                                       │   │
│  │  kubelet → CRI-O → runc                               │   │
│  │                                                       │   │
│  │  ✅ K8s 전용으로 설계, 경량                             │   │
│  │  ✅ Red Hat/OpenShift 기본 런타임                       │   │
│  │  ❌ 범용 컨테이너 관리 기능은 제한적                     │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

| 항목 | containerd | CRI-O | Docker Engine |
|------|-----------|-------|--------------|
| **CRI 지원** | 네이티브 (내장 플러그인) | 네이티브 | dockershim 필요 (제거됨) |
| **K8s 호환** | K8s 1.1+ | K8s 1.12+ | K8s 1.24에서 제거 |
| **이미지 형식** | OCI, Docker | OCI, Docker | Docker |
| **리소스 사용** | 낮음 | 매우 낮음 | 높음 |
| **CLI 도구** | ctr, nerdctl | crictl | docker |
| **주요 사용** | EKS, AKS, GKE, kubeadm | OpenShift, RHEL | 개발 환경 |

### containerd 설정 확인

```bash
# containerd 서비스 상태 확인
sudo systemctl status containerd

# containerd 설정 파일
cat /etc/containerd/config.toml

# 주요 설정 항목:
# [plugins."io.containerd.grpc.v1.cri"]
#   sandbox_image = "registry.k8s.io/pause:3.9"   ← Pause 컨테이너 이미지
#
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
#   runtime_type = "io.containerd.runc.v2"
#
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
#   SystemdCgroup = true   ← kubelet과 같은 cgroup 드라이버 사용

# containerd 버전 확인
containerd --version

# containerd 소켓 위치
ls -la /run/containerd/containerd.sock
```

### Pause 컨테이너 (Sandbox)

```
┌─────────────────────────────────────────────────────────────┐
│              Pause 컨테이너란?                                 │
│                                                             │
│  모든 Pod에는 보이지 않는 "Pause" 컨테이너가 있습니다.          │
│  Pause 컨테이너는 Pod의 네트워크 네임스페이스를 보유합니다.      │
│                                                             │
│  ┌────────────── Pod ──────────────────────────────┐        │
│  │                                                 │        │
│  │  ┌──────────────────────────────────────────┐   │        │
│  │  │  Pause 컨테이너 (sandbox)                 │   │        │
│  │  │  - 네트워크 네임스페이스 소유               │   │        │
│  │  │  - IP 주소 보유                            │   │        │
│  │  │  - 아무것도 하지 않고 "pause" (대기)        │   │        │
│  │  │  - 다른 컨테이너보다 먼저 시작              │   │        │
│  │  └──────────────────────────────────────────┘   │        │
│  │       ▲              ▲              ▲            │        │
│  │       │ 네트워크 공유 │ 네트워크 공유 │            │        │
│  │  ┌────┴─────┐  ┌────┴─────┐  ┌────┴─────┐      │        │
│  │  │ App 컨테 │  │ Sidecar  │  │ Log 컨테 │      │        │
│  │  │ 이너     │  │ 컨테이너 │  │ 이너     │      │        │
│  │  └──────────┘  └──────────┘  └──────────┘      │        │
│  │                                                 │        │
│  └─────────────────────────────────────────────────┘        │
│                                                             │
│  왜 필요한가?                                                 │
│  ├── 앱 컨테이너가 크래시해도 네트워크 설정 유지               │
│  ├── Pod 내 모든 컨테이너가 같은 네트워크 공유                 │
│  └── PID 1 역할로 좀비 프로세스 수거                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. CRI (Container Runtime Interface)

### CRI란?

> **CRI(Container Runtime Interface)**는 kubelet과 Container Runtime 사이의 **표준 gRPC 인터페이스**입니다. CRI 덕분에 kubelet은 어떤 런타임이든 동일한 방식으로 통신할 수 있습니다.

```
┌─────────────────────────────────────────────────────────────┐
│                    CRI 인터페이스 구조                          │
│                                                             │
│  kubelet                                                    │
│     │                                                       │
│     │  gRPC (unix socket)                                   │
│     │  /run/containerd/containerd.sock                      │
│     │                                                       │
│     ▼                                                       │
│  ┌──────────────────────────────────────────────────────┐    │
│  │                   CRI API                             │    │
│  │                                                      │    │
│  │  RuntimeService:          ImageService:               │    │
│  │  ├── RunPodSandbox()      ├── PullImage()            │    │
│  │  ├── StopPodSandbox()     ├── ListImages()           │    │
│  │  ├── RemovePodSandbox()   ├── RemoveImage()          │    │
│  │  ├── CreateContainer()    └── ImageStatus()          │    │
│  │  ├── StartContainer()                                │    │
│  │  ├── StopContainer()                                 │    │
│  │  ├── RemoveContainer()                               │    │
│  │  ├── ListContainers()                                │    │
│  │  ├── ContainerStatus()                               │    │
│  │  └── ExecSync()                                      │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
│     │                        │                               │
│     ▼                        ▼                               │
│  containerd              CRI-O                               │
│  (CRI Plugin 내장)       (CRI 네이티브)                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### CRI 호출 흐름 (Pod 생성)

```
kubelet이 API Server에서 새 Pod 스펙을 받았을 때:

1. RunPodSandbox()
   → Pause 컨테이너 생성
   → 네트워크 네임스페이스 생성
   → CNI 호출하여 IP 할당

2. PullImage() (이미지가 없으면)
   → 레지스트리에서 컨테이너 이미지 다운로드

3. CreateContainer()
   → 컨테이너 생성 (아직 시작하지 않음)
   → 볼륨 마운트, 환경 변수 설정

4. StartContainer()
   → 컨테이너 프로세스 시작
   → runc를 통해 격리된 프로세스 실행

5. ContainerStatus() (주기적)
   → 컨테이너 상태 조회
   → kubelet이 API Server에 보고
```

---

## 5. kube-proxy

> kube-proxy의 상세 동작 원리는 [k8s-networking.md](k8s-networking.md)에서 다루고 있습니다. 여기서는 워커 노드 관점에서 핵심만 정리합니다.

### 워커 노드에서의 kube-proxy

```
┌─────────────────────────────────────────────────────────────┐
│          kube-proxy의 워커 노드 내 위치                        │
│                                                             │
│  kube-proxy는 DaemonSet으로 모든 노드에 Pod 형태로 실행됩니다. │
│                                                             │
│  ┌──── Worker Node ─────────────────────────────────────┐   │
│  │                                                       │   │
│  │  ┌─── kube-proxy Pod ───────────────────────────┐     │   │
│  │  │                                               │     │   │
│  │  │  1. API Server에서 Service/Endpoints Watch     │     │   │
│  │  │  2. 변경 감지 시 iptables/IPVS 규칙 업데이트    │     │   │
│  │  │                                               │     │   │
│  │  └───────────────────────────────────────────────┘     │   │
│  │                    │                                   │   │
│  │                    ▼ 규칙 설정                          │   │
│  │  ┌─── 리눅스 커널 ─────────────────────────────────┐   │   │
│  │  │                                                 │   │   │
│  │  │  iptables / IPVS 규칙                            │   │   │
│  │  │                                                 │   │   │
│  │  │  10.96.0.100:80 → DNAT → 10.244.1.5:8080       │   │   │
│  │  │                        → 10.244.2.10:8080       │   │   │
│  │  │                                                 │   │   │
│  │  └─────────────────────────────────────────────────┘   │   │
│  │                                                       │   │
│  └───────────────────────────────────────────────────────┘   │
│                                                             │
│  핵심: kube-proxy는 "규칙 설정자"이며,                         │
│  실제 패킷 전달은 리눅스 커널(netfilter)이 처리                 │
└─────────────────────────────────────────────────────────────┘
```

```bash
# kube-proxy 관련 명령어
kubectl get pods -n kube-system -l k8s-app=kube-proxy          # Pod 상태
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=20    # 로그 확인
kubectl get configmap kube-proxy -n kube-system -o yaml        # 설정 확인

# iptables 규칙 확인 (노드에서 실행)
sudo iptables -t nat -L KUBE-SERVICES -n | head -20
sudo iptables -t nat -L -n | grep -c KUBE                     # 규칙 수 확인
```

---

## 6. DaemonSet

### DaemonSet이란?

> **DaemonSet**은 **클러스터의 모든 노드(또는 특정 노드)에 Pod를 하나씩 자동으로 배포하는** 컨트롤러입니다. 노드가 추가되면 자동으로 Pod가 생성되고, 노드가 제거되면 Pod도 함께 삭제됩니다.

```
┌─────────────────────────────────────────────────────────────┐
│              DaemonSet 동작 원리                               │
│                                                             │
│  DaemonSet: "모든 노드에 log-agent를 배포하라"                 │
│                                                             │
│  ┌── Node 1 ──┐  ┌── Node 2 ──┐  ┌── Node 3 ──┐           │
│  │ ┌────────┐ │  │ ┌────────┐ │  │ ┌────────┐ │           │
│  │ │log-    │ │  │ │log-    │ │  │ │log-    │ │           │
│  │ │agent   │ │  │ │agent   │ │  │ │agent   │ │           │
│  │ └────────┘ │  │ └────────┘ │  │ └────────┘ │           │
│  └────────────┘  └────────────┘  └────────────┘           │
│                                                             │
│  Node 4 추가 →                                               │
│  ┌── Node 4 ──┐                                             │
│  │ ┌────────┐ │  ← DaemonSet Controller가 자동 생성!         │
│  │ │log-    │ │                                             │
│  │ │agent   │ │                                             │
│  │ └────────┘ │                                             │
│  └────────────┘                                             │
│                                                             │
│  Node 2 제거 →  log-agent Pod도 자동 제거                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 대표적인 DaemonSet 사용 사례

```
┌─────────────────────────────────────────────────────────────┐
│              DaemonSet 사용 사례                               │
│                                                             │
│  ┌─── 시스템 필수 ──────────────────────────────────────┐    │
│  │                                                      │    │
│  │  kube-proxy        : 모든 노드의 Service 규칙 관리     │    │
│  │  CNI Plugin        : 모든 노드의 Pod 네트워크 제공      │    │
│  │   (Calico/Cilium)                                    │    │
│  │  CSI Node Plugin   : 모든 노드의 볼륨 마운트/언마운트   │    │
│  │   (vSphere CSI)                                      │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── 모니터링 ────────────────────────────────────────┐     │
│  │                                                      │    │
│  │  node-exporter     : 노드 하드웨어/OS 메트릭 수집      │    │
│  │  cAdvisor          : 컨테이너 리소스 메트릭 수집        │    │
│  │  Datadog Agent     : 모니터링 SaaS 에이전트            │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── 로그 수집 ───────────────────────────────────────┐     │
│  │                                                      │    │
│  │  Fluent Bit        : 경량 로그 수집기                  │    │
│  │  Fluentd           : 로그 수집/변환/전달               │    │
│  │  Filebeat          : Elastic 로그 수집기               │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── 보안/스토리지 ──────────────────────────────────┐      │
│  │                                                      │    │
│  │  Falco             : 런타임 보안 감지                  │    │
│  │  Longhorn Manager  : 분산 스토리지 노드 에이전트        │    │
│  │                                                      │    │
│  └──────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### DaemonSet YAML 예시

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
  namespace: monitoring
  labels:
    app: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      # 특정 노드에만 배포 (선택)
      # nodeSelector:
      #   role: worker

      tolerations:
      # Master 노드의 Taint를 허용 (Master에도 배포하고 싶을 때)
      - key: node-role.kubernetes.io/control-plane
        effect: NoSchedule

      containers:
      - name: log-agent
        image: fluent/fluent-bit:latest
        resources:
          limits:
            memory: 200Mi
            cpu: 200m
          requests:
            memory: 100Mi
            cpu: 100m
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: containerlog
          mountPath: /var/lib/docker/containers
          readOnly: true

      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: containerlog
        hostPath:
          path: /var/lib/docker/containers
```

### DaemonSet vs Deployment 비교

| 항목 | DaemonSet | Deployment |
|------|-----------|------------|
| **배포 방식** | 모든 노드에 1개씩 | replicas 수만큼 자유 배치 |
| **스케줄링** | 노드 추가 시 자동 | Scheduler가 결정 |
| **Pod 수** | 노드 수 = Pod 수 | replicas 값에 따름 |
| **용도** | 노드 수준 에이전트 | 일반 애플리케이션 |
| **롤링 업데이트** | 지원 (maxUnavailable) | 지원 (maxSurge, maxUnavailable) |
| **hostPath 접근** | 자연스러움 (노드마다 1개) | 비권장 (어떤 노드에 갈지 불확실) |

### 특정 노드에만 DaemonSet 배포

```yaml
# 방법 1: nodeSelector
spec:
  template:
    spec:
      nodeSelector:
        node-type: gpu               # gpu 라벨이 있는 노드에만

# 방법 2: nodeAffinity
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values: ["linux"]     # Linux 노드에만
```

---

## 7. Pod의 생명주기와 워커 노드

### Pod 생성부터 종료까지 (워커 노드 관점)

```
┌─────────────────────────────────────────────────────────────┐
│         워커 노드에서의 Pod 생명주기                             │
│                                                             │
│  ① Scheduler가 이 노드에 Pod 배치 결정                        │
│     │                                                       │
│     ▼                                                       │
│  ② kubelet이 API Server로부터 Pod 스펙 수신                   │
│     │                                                       │
│     ▼                                                       │
│  ③ kubelet → containerd: RunPodSandbox()                    │
│     ├── Pause 컨테이너 생성                                  │
│     ├── 네트워크 네임스페이스 생성                              │
│     └── CNI 호출 → Pod IP 할당                               │
│     │                                                       │
│     ▼                                                       │
│  ④ kubelet → containerd: PullImage() (필요 시)               │
│     └── 레지스트리에서 이미지 다운로드                          │
│     │                                                       │
│     ▼                                                       │
│  ⑤ kubelet: Volume 마운트 (PVC, ConfigMap, Secret 등)        │
│     └── CSI 드라이버와 연동하여 볼륨 Attach/Mount              │
│     │                                                       │
│     ▼                                                       │
│  ⑥ kubelet → containerd: CreateContainer() + StartContainer()│
│     ├── Init Containers 먼저 순서대로 실행 (있으면)            │
│     └── App Containers 병렬 시작                              │
│     │                                                       │
│     ▼                                                       │
│  ⑦ kubelet: postStart Hook 실행 (정의된 경우)                 │
│     │                                                       │
│     ▼                                                       │
│  ⑧ kubelet: Startup Probe 시작 (정의된 경우)                  │
│     └── 성공할 때까지 대기                                     │
│     │                                                       │
│     ▼                                                       │
│  ⑨ kubelet: Liveness + Readiness Probe 시작                  │
│     ├── Readiness 성공 → Endpoints에 Pod IP 등록             │
│     └── 이제부터 Service 트래픽 수신 가능!                     │
│     │                                                       │
│     ▼                                                       │
│  ⑩ Pod Running 상태 🟢                                       │
│     ├── kubelet이 지속적으로 Probe 실행                       │
│     ├── 컨테이너 크래시 시 restartPolicy에 따라 재시작          │
│     └── 리소스 사용량을 cAdvisor로 수집                        │
│                                                             │
│  ─── Pod 종료 시 ──────────────────────────────               │
│                                                             │
│  ⑪ Pod 삭제 요청 수신                                         │
│     │                                                       │
│     ▼                                                       │
│  ⑫ Endpoints에서 Pod IP 제거 (트래픽 차단)                    │
│     + preStop Hook 실행 (정의된 경우)                          │
│     + SIGTERM 전송                                           │
│     │                                                       │
│     ▼                                                       │
│  ⑬ terminationGracePeriodSeconds 대기 (기본 30초)             │
│     └── 이 시간 내에 종료되지 않으면 SIGKILL 강제 종료           │
│     │                                                       │
│     ▼                                                       │
│  ⑭ kubelet → containerd: StopContainer() + RemoveContainer() │
│     └── RemovePodSandbox() → Pause 컨테이너 제거              │
│     └── CNI: 네트워크 정리, Volume: 언마운트                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 컨테이너 재시작 정책 (restartPolicy)

```
┌─────────────────────────────────────────────────────────────┐
│              restartPolicy 동작                               │
│                                                             │
│  Always (기본값):                                              │
│  컨테이너가 종료되면 항상 재시작                                │
│  └── 일반 서비스 (웹 서버, API 서버 등)                        │
│                                                             │
│  OnFailure:                                                  │
│  비정상 종료(exit code ≠ 0)일 때만 재시작                       │
│  └── Job, 배치 처리                                           │
│                                                             │
│  Never:                                                      │
│  절대 재시작하지 않음                                           │
│  └── 일회성 디버깅 Pod                                        │
│                                                             │
│  재시작 백오프:                                                │
│  10초 → 20초 → 40초 → 80초 → ... → 최대 5분                   │
│  (CrashLoopBackOff 상태)                                      │
│  연속 10분 정상 실행되면 백오프 초기화                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. crictl — 컨테이너 런타임 디버깅 도구

### crictl이란?

> **crictl**은 CRI 호환 컨테이너 런타임을 디버깅하기 위한 **CLI 도구**입니다. Docker의 `docker` 명령어처럼 컨테이너와 이미지를 직접 관리할 수 있지만, CRI 표준 인터페이스를 통해 동작합니다.

```
┌─────────────────────────────────────────────────────────────┐
│              crictl vs docker vs ctr vs nerdctl              │
│                                                             │
│  ┌─── crictl ──────────────────────────────────────────┐    │
│  │  CRI 표준 디버깅 도구                                 │    │
│  │  K8s 관점에서 컨테이너/Pod 관리                        │    │
│  │  containerd, CRI-O 모두 지원                          │    │
│  │  ✅ K8s 환경 트러블슈팅에 최적                         │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── ctr ─────────────────────────────────────────────┐    │
│  │  containerd 네이티브 CLI (저수준)                      │    │
│  │  containerd 직접 제어, K8s와 무관                      │    │
│  │  네임스페이스: k8s.io (K8s 컨테이너)                   │    │
│  │  ❌ 사용이 불편, 디버깅 전용                            │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─── nerdctl ─────────────────────────────────────────┐    │
│  │  containerd 용 Docker 호환 CLI                        │    │
│  │  docker 명령어와 거의 동일한 UX                        │    │
│  │  ✅ Docker에 익숙한 사용자에게 적합                     │    │
│  │  ❌ 별도 설치 필요                                     │    │
│  └──────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### crictl 초기 설정

```bash
# crictl 설정 파일 생성 (없으면)
sudo cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# 또는 환경변수로 설정
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock

# crictl 버전 확인
crictl version
# Version:  0.1.0
# RuntimeName:  containerd
# RuntimeVersion:  1.7.2
```

### crictl 핵심 명령어

#### Pod 관련

```bash
# Pod(샌드박스) 목록 확인
sudo crictl pods
# POD ID          CREATED       STATE   NAME                     NAMESPACE
# abc123def456    2 hours ago   Ready   nginx-xxx-yyy            default
# 789ghi012jkl    3 hours ago   Ready   kube-proxy-zzz           kube-system

# 특정 Pod 상세 정보
sudo crictl inspectp <pod-id>

# Pod 이름으로 필터링
sudo crictl pods --name nginx

# Namespace로 필터링
sudo crictl pods --namespace kube-system

# 상태로 필터링
sudo crictl pods --state ready
sudo crictl pods --state notready

# Pod의 리소스 사용량
sudo crictl statsp
```

#### 컨테이너 관련

```bash
# 컨테이너 목록 (실행 중인 것만)
sudo crictl ps
# CONTAINER       IMAGE          CREATED        STATE     NAME      POD ID
# aaa111bbb222    nginx:latest   2 hours ago    Running   nginx     abc123def456

# 모든 컨테이너 (중지/종료 포함)
sudo crictl ps -a

# 컨테이너 상세 정보 (JSON)
sudo crictl inspect <container-id>

# 컨테이너 로그 확인
sudo crictl logs <container-id>
sudo crictl logs --tail 50 <container-id>          # 마지막 50줄
sudo crictl logs --since "2024-01-15T10:00:00Z" <container-id>  # 특정 시간 이후
sudo crictl logs -f <container-id>                 # 실시간 로그 (follow)

# 컨테이너 내부에서 명령 실행
sudo crictl exec -it <container-id> sh
sudo crictl exec <container-id> cat /etc/hostname

# 컨테이너 리소스 사용량
sudo crictl stats
# CONTAINER       CPU %    MEM           DISK        INODES
# aaa111bbb222    0.50     25.6MiB       16.4kB      12

# 컨테이너 중지/삭제 (비상 시에만!)
sudo crictl stop <container-id>
sudo crictl rm <container-id>
```

#### 이미지 관련

```bash
# 이미지 목록
sudo crictl images
# IMAGE                          TAG       IMAGE ID       SIZE
# docker.io/library/nginx        latest    a8758716bb6a   67.3MB
# registry.k8s.io/pause          3.9       e6f181688397   750kB

# 이미지 상세 정보
sudo crictl inspecti <image-id-or-name>

# 이미지 Pull
sudo crictl pull nginx:latest

# 이미지 삭제 (사용 중이 아닌 이미지)
sudo crictl rmi <image-id>

# 사용되지 않는 이미지 정리
sudo crictl rmi --prune
```

### docker 명령어 → crictl 매핑

| docker 명령어 | crictl 명령어 | 설명 |
|-------------|-------------|------|
| `docker ps` | `crictl ps` | 실행 중인 컨테이너 목록 |
| `docker ps -a` | `crictl ps -a` | 모든 컨테이너 목록 |
| `docker inspect` | `crictl inspect` | 컨테이너 상세 정보 |
| `docker logs` | `crictl logs` | 컨테이너 로그 |
| `docker exec` | `crictl exec` | 컨테이너 내 명령 실행 |
| `docker images` | `crictl images` | 이미지 목록 |
| `docker pull` | `crictl pull` | 이미지 다운로드 |
| `docker stats` | `crictl stats` | 리소스 사용량 |
| (없음) | `crictl pods` | Pod(샌드박스) 목록 |
| (없음) | `crictl statsp` | Pod 리소스 사용량 |

---

## 9. 워커 노드 트러블슈팅 가이드

### 단계별 진단 흐름

```
문제: "워커 노드가 NotReady 상태입니다!"
        │
        ▼
┌─── 1단계: 노드 상태 확인 ────────────────────────────────┐
│  kubectl describe node <node-name>                       │
│  → Conditions 확인 (Ready, MemoryPressure 등)             │
│  → Events 확인 (에러 메시지)                               │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌─── 2단계: kubelet 상태 확인 (노드 SSH 접속) ────────────┐
│  sudo systemctl status kubelet                           │
│  sudo journalctl -u kubelet --since "5 minutes ago"      │
│                                                          │
│  자주 보는 에러:                                          │
│  ├── "failed to run Kubelet: running with swap on"       │
│  │   → 해결: sudo swapoff -a                             │
│  ├── "unable to connect to API server"                   │
│  │   → 해결: 네트워크/인증서 확인                          │
│  ├── "node not found"                                    │
│  │   → 해결: kubelet 인증서 갱신                           │
│  └── "PLEG is not healthy"                               │
│      → 해결: containerd 상태 확인                          │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌─── 3단계: Container Runtime 확인 ────────────────────────┐
│  sudo systemctl status containerd                        │
│  sudo crictl info                                        │
│  sudo crictl pods                                        │
│                                                          │
│  자주 보는 에러:                                          │
│  ├── containerd 서비스 중지                                │
│  │   → 해결: sudo systemctl restart containerd            │
│  ├── 소켓 파일 없음                                       │
│  │   → 해결: containerd 재설치/재시작                      │
│  └── 이미지 Pull 실패                                     │
│      → 해결: 레지스트리 연결, 인증 확인                     │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌─── 4단계: 시스템 리소스 확인 ────────────────────────────┐
│  free -h          # 메모리 확인                           │
│  df -h            # 디스크 확인                           │
│  top              # CPU/프로세스 확인                      │
│  sudo dmesg -T    # 커널 메시지 (OOM Killer 등)           │
│                                                          │
│  자주 보는 문제:                                          │
│  ├── 메모리 부족 → kubelet이 Pod Eviction 시작             │
│  ├── 디스크 부족 → 이미지 Pull 실패, 로그 쓰기 실패        │
│  └── OOM Killer → 커널이 프로세스 강제 종료                │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌─── 5단계: 네트워크 확인 ─────────────────────────────────┐
│  ping <master-ip>                  # Master 연결           │
│  curl -k https://<master-ip>:6443  # API Server 연결      │
│  sudo iptables -L -n               # 방화벽 규칙           │
│  ip route                           # 라우팅 테이블         │
│  sudo crictl pods --namespace kube-system  # CNI Pod 상태   │
└──────────────────────────────────────────────────────────┘
```

### Pod 수준 트러블슈팅 (워커 노드에서)

```bash
# ─── Pod가 시작되지 않을 때 ───

# kubectl 수준 확인 (Master 또는 kubeconfig 설정된 곳)
kubectl describe pod <pod-name>             # Events 확인
kubectl get pod <pod-name> -o yaml          # 상세 스펙 확인

# 워커 노드 SSH 접속 후 crictl로 확인
sudo crictl pods --name <pod-name>          # Pod 샌드박스 상태
sudo crictl ps -a | grep <pod-name>         # 컨테이너 상태 (종료된 것 포함)
sudo crictl logs <container-id>             # 컨테이너 로그
sudo crictl inspect <container-id> | grep -A 10 "status"  # 종료 이유

# ─── 자주 보는 Pod 상태별 원인 ───

# ImagePullBackOff
sudo crictl pull <image-name>               # 이미지 수동 Pull 테스트
# → 레지스트리 주소 오타, 인증 실패, 이미지 미존재

# CrashLoopBackOff
sudo crictl logs <container-id>             # 앱 로그에서 에러 확인
sudo crictl inspect <container-id>          # exit code 확인
# exit code 1: 앱 에러, 137: OOM Killed, 139: Segfault

# ContainerCreating (장시간)
sudo journalctl -u kubelet --since "5 min ago" | grep -i error
# → 볼륨 마운트 실패, 이미지 Pull 지연, CNI 오류

# Evicted
kubectl describe pod <pod-name>             # eviction 이유 확인
# → 디스크 부족 (ephemeral-storage), 메모리 부족
```

### 주요 로그 파일 위치

```bash
# ─── 컴포넌트별 로그 위치 ───

# kubelet 로그 (systemd 기반)
sudo journalctl -u kubelet -f

# containerd 로그 (systemd 기반)
sudo journalctl -u containerd -f

# 컨테이너 로그 (기본 위치)
/var/log/containers/<pod-name>_<namespace>_<container-name>-<container-id>.log

# Pod 로그 (kubelet이 관리)
/var/log/pods/<namespace>_<pod-name>_<pod-uid>/<container-name>/

# 커널 로그 (OOM Killer, 하드웨어 에러 등)
sudo dmesg -T | tail -50
/var/log/syslog           # Ubuntu
/var/log/messages         # CentOS/RHEL

# kubelet 설정
/var/lib/kubelet/config.yaml
/var/lib/kubelet/kubeadm-flags.env

# Static Pod 매니페스트 (Master 노드)
/etc/kubernetes/manifests/
```

### 자주 발생하는 문제와 해결

| 증상 | 원인 | 확인 방법 | 해결 |
|------|------|----------|------|
| 노드 NotReady | kubelet 중지 | `systemctl status kubelet` | `systemctl restart kubelet` |
| 노드 NotReady | containerd 중지 | `systemctl status containerd` | `systemctl restart containerd` |
| 노드 NotReady | swap 활성화 | `free -h` (Swap 확인) | `swapoff -a` + fstab 수정 |
| Pod Evicted | 디스크 부족 | `df -h` | 불필요 이미지/로그 정리 |
| Pod Evicted | 메모리 부족 | `free -h`, `dmesg \| grep oom` | 리소스 확보, 리밋 조정 |
| ImagePullBackOff | 이미지/레지스트리 문제 | `crictl pull <image>` | 이미지 이름, 인증 확인 |
| CrashLoopBackOff | 앱 에러 | `crictl logs <cid>` | 앱 로그 분석, 설정 확인 |
| PLEG not healthy | containerd 과부하 | `journalctl -u kubelet` | containerd 재시작, 노드 리소스 확인 |
| 인증서 만료 | kubelet 인증서 기한 초과 | `openssl x509 -in ... -noout -dates` | `kubeadm certs renew` |
| CNI 오류 | CNI Plugin 장애 | `crictl pods -s notready` | CNI Pod 재시작, 로그 확인 |

---

## 10. 실습: 워커 노드 동작 확인

### 실습 1: kubelet 동작 관찰

```bash
# 1. kubelet 상태 확인
sudo systemctl status kubelet

# 2. kubelet 설정 확인
sudo cat /var/lib/kubelet/config.yaml | head -30

# 3. 노드 상태 확인 (kubelet이 보고하는 정보)
kubectl describe node $(hostname) | grep -A 10 "Conditions:"

# 4. kubelet 로그 실시간 관찰 (별도 터미널에서)
sudo journalctl -u kubelet -f --no-pager

# 5. Pod 생성하면서 kubelet 로그 관찰
kubectl run kubelet-test --image=nginx
# → kubelet 로그에서 컨테이너 생성 과정 확인:
#   "SyncLoop (ADD, ...): nginx"
#   "Pulling image nginx"
#   "Successfully pulled image"
#   "Created container"
#   "Started container"

# 6. 정리
kubectl delete pod kubelet-test
```

### 실습 2: containerd와 crictl 활용

```bash
# 1. containerd 상태 확인
sudo systemctl status containerd
sudo crictl info | head -20

# 2. 현재 실행 중인 Pod 확인 (crictl)
sudo crictl pods
# kubectl get pods 와 비교해 보세요!

# 3. 실행 중인 컨테이너 확인
sudo crictl ps

# 4. Pause 컨테이너 확인 (보이지 않는 샌드박스)
sudo crictl ps -a | grep pause
# 모든 Pod마다 pause 컨테이너가 있는 것을 확인!

# 5. 특정 컨테이너의 상세 정보
sudo crictl inspect $(sudo crictl ps -q | head -1) | python3 -m json.tool | head -40

# 6. 이미지 목록
sudo crictl images

# 7. 컨테이너 리소스 사용량
sudo crictl stats
sudo crictl statsp    # Pod 단위
```

### 실습 3: 컨테이너 로그 분석

```bash
# 1. 의도적으로 크래시하는 Pod 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: crash-demo
spec:
  containers:
  - name: crash
    image: busybox
    command: ["sh", "-c", "echo 'Starting...' && sleep 5 && exit 1"]
EOF

# 2. Pod 상태 관찰 (CrashLoopBackOff 발생)
kubectl get pod crash-demo -w
# NAME         READY   STATUS             RESTARTS   AGE
# crash-demo   0/1     CrashLoopBackOff   3          2m

# 3. kubectl로 로그 확인
kubectl logs crash-demo
kubectl logs crash-demo --previous    # 이전 크래시된 컨테이너 로그

# 4. 워커 노드에서 crictl로 확인 (SSH 접속 후)
sudo crictl ps -a | grep crash-demo
# 종료된 컨테이너 여러 개가 보임 (재시작 이력)

sudo crictl logs <container-id>       # 각 컨테이너의 로그 확인

sudo crictl inspect <container-id> | grep -A 5 "exitCode"
# "exitCode": 1  ← 비정상 종료

# 5. 노드의 로그 파일 직접 확인
ls /var/log/pods/ | grep crash-demo
cat /var/log/pods/default_crash-demo_*/crash/*.log

# 6. 정리
kubectl delete pod crash-demo
```

### 실습 4: DaemonSet 동작 관찰

```bash
# 1. DaemonSet 생성
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-info
spec:
  selector:
    matchLabels:
      app: node-info
  template:
    metadata:
      labels:
        app: node-info
    spec:
      tolerations:
      - effect: NoSchedule
        operator: Exists
      containers:
      - name: info
        image: busybox
        command: ["sh", "-c", "echo Node: \$(hostname) && sleep 3600"]
        resources:
          limits:
            memory: 64Mi
            cpu: 50m
EOF

# 2. DaemonSet 확인 (모든 노드에 1개씩!)
kubectl get daemonset node-info
# NAME        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR
# node-info   3         3         3       3            3           <none>

kubectl get pods -l app=node-info -o wide
# 각 노드에 하나씩 배포된 것을 확인

# 3. 각 Pod의 로그 확인 (어떤 노드에서 실행 중인지)
kubectl logs -l app=node-info
# Node: worker-1
# Node: worker-2
# Node: master

# 4. 정리
kubectl delete daemonset node-info
```

### 실습 5: Probe와 재시작 관찰

```bash
# 1. Liveness Probe가 있는 Pod 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: probe-demo
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh", "-c", "touch /tmp/healthy && sleep 30 && rm /tmp/healthy && sleep 600"]
    livenessProbe:
      exec:
        command: ["cat", "/tmp/healthy"]
      initialDelaySeconds: 5
      periodSeconds: 5
EOF

# 2. Pod 상태 관찰 (30초 후 /tmp/healthy 삭제 → Probe 실패 → 재시작)
kubectl get pod probe-demo -w
# 30초 후:
# NAME         READY   STATUS    RESTARTS   AGE
# probe-demo   1/1     Running   0          30s
# probe-demo   1/1     Running   1          60s   ← 재시작!

# 3. 이벤트에서 Probe 실패와 재시작 확인
kubectl describe pod probe-demo | tail -15
# Events:
#   Warning  Unhealthy  Liveness probe failed: cat: /tmp/healthy: No such file
#   Normal   Killing    Container app failed liveness probe, will be restarted

# 4. 정리
kubectl delete pod probe-demo
```

### 실습 6: Static Pod 생성 (Master 노드에서)

```bash
# ⚠️ 이 실습은 Master 노드에서 수행합니다

# 1. Static Pod 매니페스트 디렉터리 확인
ls /etc/kubernetes/manifests/
# etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

# 2. Static Pod 생성 (YAML 파일을 디렉터리에 놓기만 하면 됨!)
sudo cat > /etc/kubernetes/manifests/static-nginx.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: static-nginx
  labels:
    app: static-nginx
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 80
EOF

# 3. 몇 초 후 Pod 확인 (kubelet이 자동으로 생성)
kubectl get pods | grep static-nginx
# static-nginx-<node-name>   1/1     Running   0          10s

# 4. kubectl로 삭제 시도 → 다시 생성됨! (kubelet이 관리하므로)
kubectl delete pod static-nginx-<node-name>
kubectl get pods | grep static-nginx
# 다시 Running! (YAML 파일이 존재하는 한 계속 실행)

# 5. 진짜 삭제: YAML 파일 제거
sudo rm /etc/kubernetes/manifests/static-nginx.yaml
# 몇 초 후 자동 삭제됨
kubectl get pods | grep static-nginx
# (없음)
```

---

## 11. 정리 및 핵심 요약

### 한눈에 보는 워커 노드

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   API Server                                                    │
│      │                                                          │
│      │  "이 Pod를 실행해라"                                       │
│      ▼                                                          │
│   ┌──────────┐  시스템 서비스 (systemd)                           │
│   │ kubelet  │  Pod 스펙 수신 → Probe → 상태 보고                 │
│   └────┬─────┘                                                   │
│        │ CRI (gRPC)                                              │
│        ▼                                                        │
│   ┌────────────┐  시스템 서비스 (systemd)                         │
│   │ containerd │  이미지 Pull → 컨테이너 생성/실행                 │
│   └────┬───────┘                                                 │
│        │ OCI                                                     │
│        ▼                                                        │
│   ┌──────┐                                                       │
│   │ runc │  커널 namespace + cgroup → 격리된 프로세스               │
│   └──┬───┘                                                       │
│      │                                                          │
│      ▼                                                          │
│   Pod (컨테이너들)                                                │
│      │                                                          │
│      │ 네트워크                                                   │
│      ▼                                                          │
│   kube-proxy + CNI Plugin (DaemonSet)                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 핵심 포인트 7가지

| # | 포인트 | 설명 |
|---|--------|------|
| 1 | **kubelet은 워커 노드의 핵심** | Pod 관리, 상태 보고, Probe 실행, 볼륨 관리 — 모든 것의 시작점 |
| 2 | **containerd가 표준 런타임** | Docker는 K8s에서 제거됨. containerd 또는 CRI-O가 표준 |
| 3 | **CRI로 런타임 추상화** | kubelet은 CRI만 알면 됨. 어떤 런타임이든 교체 가능 |
| 4 | **DaemonSet = 노드마다 1개** | 로그 수집, 모니터링, CNI, CSI 등 노드 수준 에이전트에 필수 |
| 5 | **Probe로 앱 건강 관리** | Liveness(재시작), Readiness(트래픽 차단), Startup(기동 대기) |
| 6 | **crictl로 노드 수준 디버깅** | kubectl 없이 노드에서 직접 컨테이너/Pod 상태 확인 가능 |
| 7 | **Static Pod는 kubelet이 직접 관리** | API Server 없이도 동작. Control Plane 컴포넌트가 이 방식 |

### 트러블슈팅 체크리스트

```
워커 노드 문제 발생 시 확인 순서:

□ kubectl describe node <name>       — 노드 상태/이벤트
□ systemctl status kubelet           — kubelet 동작 여부
□ journalctl -u kubelet              — kubelet 에러 로그
□ systemctl status containerd        — 런타임 동작 여부
□ crictl pods / crictl ps -a         — Pod/컨테이너 상태
□ crictl logs <container-id>         — 컨테이너 로그
□ free -h / df -h / top              — 시스템 리소스
□ dmesg -T | tail                    — 커널 메시지 (OOM 등)
□ ip route / ping <master-ip>        — 네트워크 연결
```

### CKA/CKAD 시험 빈출 포인트

| 주제 | 자주 나오는 문제 유형 |
|------|---------------------|
| kubelet | systemctl로 상태 확인/재시작, 설정 파일 경로 |
| Static Pod | /etc/kubernetes/manifests/에 YAML 생성/삭제 |
| Container Runtime | containerd 설정, CRI 소켓 경로 |
| DaemonSet | YAML 작성, Toleration으로 Master 포함, nodeSelector |
| Probe | liveness/readiness/startup 설정, 실패 시 동작 이해 |
| crictl | 컨테이너 로그 확인, Pod 상태 디버깅 |
| 노드 트러블슈팅 | NotReady 원인 분석, kubelet/containerd 재시작 |
| 로그 확인 | journalctl, /var/log/pods/, crictl logs |

---

> **다음 단계**: 이 교육 자료를 학습한 후, 실제 워커 노드에 SSH 접속하여 `crictl` 명령어를 직접 실행해 보세요. [`k8s-master-components.md`](k8s-master-components.md)와 함께 읽으면 Control Plane과 워커 노드의 협업 구조가 한눈에 들어옵니다.
