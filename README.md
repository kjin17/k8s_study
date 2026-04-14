# Kubernetes Study Scripts

Kubernetes 클러스터 **자동 설치**, **오브젝트 학습**, **애드온 설치**를 위한 인터랙티브 쉘 스크립트 모음입니다.
**컨테이너 기초 교육 자료**, **Kubernetes 마스터 노드 컴포넌트 교육 자료**, **Kubernetes 네트워킹 심화 교육 자료**, **Harbor & Trivy 프라이빗 레지스트리 교육 자료**, **Git & GitHub 기초 교육 자료**도 함께 제공합니다.

---

## 파일 목록

| 파일 | 용도 |
|------|------|
| [`container-basics.md`](container-basics.md) | 리눅스 컨테이너 기초 교육 (입문자용) |
| [`k8s-master-components.md`](k8s-master-components.md) | K8s 마스터 노드(Control Plane) 핵심 컴포넌트 교육 |
| [`k8s-networking.md`](k8s-networking.md) | K8s 네트워킹 심화 교육 (CNI, kube-proxy, CoreDNS, Ingress, LoadBalancer) |
| [`harbor-registry.md`](harbor-registry.md) | Harbor & Trivy 프라이빗 레지스트리 교육 |
| [`git-basics.md`](git-basics.md) | Git & GitHub 기초 교육 (입문자용) |
| `k8s-install.sh` | 가상머신 3대에 K8s 클러스터 자동 설치 |
| `k8s-learn.sh`   | K8s 오브젝트 인터랙티브 학습 (입문자용) |
| `k8s-addon.sh`   | 자주 쓰는 오픈소스 애드온 인터랙티브 설치 |
| `harbor-registry.sh` | Harbor & Trivy 인터랙티브 설치/실습 |

---

## k8s-install.sh — 클러스터 자동 설치

리눅스 가상머신 3대에 SSH로 접속하여 **1 Master + 2 Worker** 구성의 Kubernetes 클러스터를 자동으로 설치합니다.

### 클러스터 구성

```
┌─────────────────────────────────────────────┐
│           Kubernetes Cluster                │
│                                             │
│   ┌───────────────┐                         │
│   │  Master Node  │  kubeadm init           │
│   │  (Control     │  API Server             │
│   │   Plane)      │  etcd, Scheduler        │
│   └───────┬───────┘                         │
│           │ kubeadm join                    │
│     ┌─────┴─────┐                           │
│     │           │                           │
│ ┌───┴───┐   ┌───┴───┐                       │
│ │Worker1│   │Worker2│                       │
│ └───────┘   └───────┘                       │
└─────────────────────────────────────────────┘
```

### 지원 OS

| OS | 버전 |
|----|------|
| Ubuntu | 20.04 LTS, 22.04 LTS |
| CentOS | 7, 8 |
| RHEL | 7, 8, 9 |
| Rocky Linux | 8, 9 |
| AlmaLinux | 8, 9 |

### 최소 사양 (노드당)

| 항목 | 최솟값 |
|------|--------|
| CPU | 2 코어 |
| 메모리 | 2 GB |
| 디스크 | 20 GB |
| 네트워크 | 인터넷 연결 가능 |

### 사전 요구사항

로컬 머신에 `sshpass` 설치 필요:

```bash
# macOS
brew install hudochenkov/sshpass/sshpass

# Ubuntu / Debian
sudo apt-get install -y sshpass openssh-client

# CentOS / RHEL
sudo yum install -y sshpass openssh-clients
```

각 VM 조건:
- 기본 OS만 설치된 상태 (추가 패키지 불필요)
- SSH 접속 가능 (계정/비밀번호)
- `sudo` 권한 보유
- 인터넷 연결 가능

### 실행

```bash
chmod +x k8s-install.sh
./k8s-install.sh
```

### 입력 항목

**노드 정보 (3개 노드)**

| 항목 | 설명 | 예시 |
|------|------|------|
| IP 주소 | 각 VM의 IP | `192.168.1.10` |
| SSH 사용자명 | SSH 계정 | `root` |
| SSH 비밀번호 | SSH 비밀번호 | |
| 호스트명 | K8s 노드명으로 사용 | `k8s-master` |

**Kubernetes 설정**

| 항목 | 선택지 | 기본값 |
|------|--------|--------|
| K8s 버전 | 1.31 / 1.30 / 1.29 / 직접입력 | `1.31` |
| CNI 플러그인 | Antrea / Calico / Cilium | - |
| Pod CIDR | CNI별 자동 제안 | CNI 종류마다 상이 |
| Service CIDR | 직접 입력 | `10.96.0.0/12` |

**vSphere CSI Driver (선택)**

vSphere 환경에서 PersistentVolume 동적 프로비저닝이 필요한 경우 설치합니다.

| 항목 | 설명 |
|------|------|
| vCenter IP/FQDN | vCenter Server 주소 |
| vCenter 포트 | 기본 `443` |
| vCenter 사용자명 | 예: `administrator@vsphere.local` |
| vCenter 비밀번호 | |
| Datacenter 이름 | vSphere Datacenter 이름 |
| 클러스터 고유 ID | K8s 클러스터 식별자 |
| Datastore 경로 | 예: `/DC1/datastore/ds1` |
| Storage Policy | SPBM 정책 이름 (선택) |
| CSI 버전 | 기본 `3.3.0` |

> **vSphere CSI 전제 조건**
> - 모든 VM에서 `disk.EnableUUID = TRUE` 설정 필요
> - VM Hardware 버전 15 이상
> - vSphere 6.7U3 / ESXi 6.7U3 이상
> - K8s 노드 이름 = vSphere VM 이름 일치

### CNI 플러그인 비교

| CNI | 특징 | Pod CIDR 기본값 |
|-----|------|-----------------|
| **Antrea** | VMware 공식, NetworkPolicy 풍부, NSX 연동 가능 | `10.244.0.0/16` |
| **Calico** | BGP/IPIP 지원, 대규모 클러스터에 적합 | `192.168.0.0/16` |
| **Cilium** | eBPF 기반 고성능, 강력한 네트워크 보안 정책 | `10.0.0.0/8` |

### 설치 흐름

```
1. 로컬 의존성 확인 (sshpass, ssh, scp)
        ↓
2. 인터랙티브 입력 수집
        ↓
3. 설치 구성 요약 확인 및 최종 승인
        ↓
4. Pre-flight Checks (SSH 연결 / CPU / 메모리 / 디스크 / 인터넷 / sudo)
        ↓
5. 3개 노드 병렬 초기화
   ├── 호스트명 설정 + /etc/hosts 구성
   ├── Swap 비활성화
   ├── 커널 모듈 로드 (overlay, br_netfilter)
   ├── sysctl 설정
   ├── SELinux / firewalld 비활성화 (CentOS/RHEL)
   ├── containerd 설치 (SystemdCgroup=true)
   └── kubeadm / kubelet / kubectl 설치
        ↓
6. Master 노드 초기화 (kubeadm init)
        ↓
7. CNI 플러그인 설치
        ↓
8. Worker 노드 클러스터 조인 (kubeadm join)
        ↓
9. vSphere CSI Driver 설치 (선택)
        ↓
10. 클러스터 상태 검증
```

### 설치 후 확인

```bash
# Master 노드 접속
ssh <user>@<master-ip>

# 노드 상태 확인
kubectl get nodes -o wide

# 시스템 Pod 상태 확인
kubectl get pods -n kube-system

# vSphere CSI 확인 (설치한 경우)
kubectl get pods -n vmware-system-csi
kubectl get storageclass
```

### kubeconfig 로컬 복사

```bash
mkdir -p ~/.kube
scp <user>@<master-ip>:~/.kube/config ~/.kube/config
kubectl get nodes
```

### 로그

실행 디렉터리에 타임스탬프가 포함된 로그 파일이 자동 생성됩니다.

```
k8s-install-20240329-143022.log
```

### 주의 사항

- 스크립트 실행 시 **각 노드의 기존 Kubernetes 설정이 초기화**됩니다.
- SSH 비밀번호는 메모리에만 저장되며 파일에 기록되지 않습니다.
- 설치 중 네트워크가 끊기면 일부 단계가 실패할 수 있습니다. 로그 파일을 확인하세요.

---

## k8s-learn.sh — 오브젝트 학습 (입문자용)

Kubernetes를 처음 배우는 사람을 위한 인터랙티브 학습 스크립트입니다.
각 오브젝트의 개념 설명 → YAML 미리보기 → 실제 생성 → 확인 명령 안내 순서로 진행됩니다.

### 실행

```bash
chmod +x k8s-learn.sh
./k8s-learn.sh
```

> kubectl이 설치되어 있고 클러스터에 연결된 환경에서 실행하세요.
> Master 노드 직접 실행 또는 로컬에서 `~/.kube/config` 설정 후 사용 가능합니다.

### 학습 주제 (12개)

| # | 오브젝트 | 핵심 개념 |
|---|---------|----------|
| 1 | **Namespace** | 클러스터 내 논리적 분리 공간 |
| 2 | **Pod** | 가장 작은 배포 단위, 생명주기 이해 |
| 3 | **Deployment** | replicas 유지, 롤링 업데이트, 롤백 |
| 4 | **Service** | ClusterIP / NodePort / LoadBalancer 선택 생성 |
| 5 | **ConfigMap** | 설정을 코드와 분리, Key-Value + 파일 형식 |
| 6 | **Secret** | 민감 정보 저장, Base64 인코딩 이해 |
| 7 | **PersistentVolumeClaim** | PV/PVC 3단계 구조, AccessMode |
| 8 | **StatefulSet** | 순서 보장, Pod별 독립 PVC, Headless Service |
| 9 | **DaemonSet** | 모든 노드에 1개씩 배포, 로그 수집 패턴 |
| 10 | **Job / CronJob** | 일회성 작업 / cron 스케줄 반복 작업 |
| 11 | **HorizontalPodAutoscaler** | CPU/메모리 기반 자동 스케일링 |
| 12 | **Ingress** | 도메인·경로 기반 HTTP 라우팅 |

### 학습 화면 예시

```
╔══════════════════════════════════════════════════════════════╗
║         Kubernetes 오브젝트 학습 — 인터랙티브 실습           ║
╚══════════════════════════════════════════════════════════════╝

  현재 Namespace: default
  생성 오브젝트:  3개

  ── 학습 주제 ────────────────────────────────────────
   1) Namespace          — 클러스터 내 가상 분리 공간
   2) Pod                — 가장 작은 배포 단위
   3) Deployment         — Pod 개수 유지 + 롤링 업데이트
  ...
```

### 기능

- **개념 설명**: 각 오브젝트마다 ASCII 다이어그램과 핵심 특징 설명
- **YAML 미리보기**: 생성 전 실제 적용될 YAML 확인
- **kubectl 팁**: 생성 후 활용 가능한 명령어 자동 안내
- **세션 추적**: 이번 세션에서 생성한 오브젝트 목록 관리
- **일괄 정리**: 학습 종료 시 생성된 리소스 한 번에 삭제 가능
- **클러스터 현황**: 현재 노드 상태 및 리소스 목록 즉시 확인

---

## k8s-addon.sh — 오픈소스 애드온 설치

Kubernetes 환경에서 자주 사용하는 오픈소스를 **Helm 3** 기반으로 인터랙티브하게 설치합니다.
각 애드온의 개념 설명과 함께 옵션을 입력받아 설치하며, 접속 방법과 활용 팁을 안내합니다.

### 실행

```bash
chmod +x k8s-addon.sh
./k8s-addon.sh
```

> **사전 요구사항**: `kubectl` + 클러스터 연결 필수. `helm`은 없으면 자동 설치를 제안합니다.

### 포함 애드온 (7종)

| # | 애드온 | 카테고리 | 설명 |
|---|--------|----------|------|
| 1 | **Prometheus + Grafana** | 모니터링 | kube-prometheus-stack — Prometheus Operator, AlertManager, node-exporter, kube-state-metrics 포함 |
| 2 | **Velero + MinIO** | 백업/복구 | 클러스터 리소스 & PV 백업, S3 호환 오브젝트 스토리지 |
| 3 | **Istio** | 서비스 메시 | 트래픽 관리, mTLS, 분산 추적, Kiali 시각화 |
| 4 | **Elasticsearch + Kibana** | 로그 분석 | ECK Operator 기반, 8.x 버전, 로그 저장·검색·시각화 |
| 5 | **Fluent Bit** | 로그 수집 | DaemonSet 으로 전 노드 로그 수집, ES 출력 설정 포함 |
| 6 | **Kyverno** | 정책 관리 | YAML 기반 K8s-Native 정책 엔진, 샘플 정책 포함 |
| 7 | **OPA Gatekeeper** | 정책 관리 | Rego 언어 기반 정책 엔진, ConstraintTemplate 샘플 포함 |

### 번들 설치

개별 애드온 외에 묶음 설치도 지원합니다.

| 번들 | 포함 애드온 |
|------|------------|
| **Observability Stack** | Prometheus + Grafana + Elasticsearch + Kibana + Fluent Bit |
| **Policy Stack** | Kyverno + OPA Gatekeeper |

### 애드온별 접속 방법 (port-forward)

```bash
# Grafana
kubectl port-forward svc/<release>-grafana 3000:80 -n monitoring
# → http://localhost:3000  (admin / 설정한 비밀번호)

# Prometheus
kubectl port-forward svc/<release>-kube-prom-prometheus 9090:9090 -n monitoring
# → http://localhost:9090

# Kibana
kubectl port-forward svc/kibana-kb-http 5601:5601 -n elastic-system
# → https://localhost:5601

# MinIO 콘솔
kubectl port-forward svc/minio 9001:9001 -n velero
# → http://localhost:9001
```

### 로그

실행 디렉터리에 타임스탬프가 포함된 로그 파일이 자동 생성됩니다.

```
k8s-addon-20240329-150000.log
```

---

## harbor-registry.sh — Harbor & Trivy 프라이빗 레지스트리 실습

Harbor(프라이빗 컨테이너 레지스트리)와 Trivy(취약점 스캐너)를 **Helm 3** 기반으로 인터랙티브하게 설치하고 실습합니다. Docker/Helm 명령어를 활용한 이미지·차트 관리까지 포함합니다.

### 실행

```bash
chmod +x harbor-registry.sh
./harbor-registry.sh
```

> **사전 요구사항**: `kubectl` + 클러스터 연결 필수. `helm`과 `docker`는 없으면 자동 설치를 제안합니다.

### 포함 메뉴 (7종)

| # | 메뉴 | 설명 |
|---|------|------|
| 1 | **Harbor 설치** | Helm 으로 Harbor 배포 (NodePort/Ingress/LB 선택, TLS, PVC 크기 설정) |
| 2 | **Harbor 프로젝트 관리** | 프로젝트 생성/조회, Public/Private 설정, 역할 기반 접근 제어 |
| 3 | **Docker Push/Pull 실습** | docker login → pull → tag → push → pull 전체 워크플로우 |
| 4 | **Trivy 취약점 스캔** | CLI 독립 스캔 또는 Harbor 통합 스캔, 심각도별 필터링 |
| 5 | **Helm 차트 관리** | OCI 기반 차트 생성 → 패키징 → push → pull 실습 |
| 6 | **이미지 보안 설정** | 자동 스캔 활성화, 취약 이미지 배포 차단, 보안 현황 조회 |
| 7 | **Harbor 삭제** | Helm Release, PVC, Namespace 완전 삭제 |

### 교육 자료

상세한 개념 설명과 명령어 레퍼런스는 [`harbor-registry.md`](harbor-registry.md)를 참고하세요.

| 주제 | 내용 |
|------|------|
| 컨테이너 레지스트리 개념 | 퍼블릭 vs 프라이빗, 이미지 주소 구조 |
| Harbor 아키텍처 | Core, Registry, Trivy, PostgreSQL, Redis, Job Service |
| Docker CLI 사용법 | login, tag, push, pull, imagePullSecrets |
| Helm 차트 관리 | OCI 방식 push/pull, ChartMuseum 비교 |
| Trivy 취약점 스캔 | CLI 스캔, Harbor 통합 스캔, 심각도 등급 |
| 보안 모범 사례 | 이미지 서명, RBAC, TLS, 네트워크 정책 |
| CI/CD 연동 | Jenkins, GitLab CI 파이프라인 예시 |
| 문제 해결 | 인증서 오류, Push 실패, 스캔 실패 대응 |

### 로그

```
harbor-registry-20240329-160000.log
```
