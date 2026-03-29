# Kubernetes Cluster Auto-Installer

리눅스 가상머신 3대에 SSH로 접속하여 **1 Master + 2 Worker** 구성의 Kubernetes 클러스터를 자동으로 설치하는 인터랙티브 쉘 스크립트입니다.

## 구성

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

## 지원 환경

### 운영 체제 (각 VM)
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

## 사전 요구사항

### 로컬 머신 (스크립트 실행 환경)

```bash
# macOS
brew install hudochenkov/sshpass/sshpass

# Ubuntu / Debian
sudo apt-get install -y sshpass openssh-client

# CentOS / RHEL
sudo yum install -y sshpass openssh-clients
```

### 각 VM

- 기본 OS만 설치된 상태 (패키지 추가 설치 불필요)
- SSH 접속 가능 (계정/비밀번호)
- `sudo` 권한 보유
- 인터넷 연결 가능

## 설치 방법

```bash
# 실행 권한 부여
chmod +x k8s-install.sh

# 스크립트 실행
./k8s-install.sh
```

## 인터랙티브 입력 항목

### 노드 정보 (3개 노드)

| 항목 | 설명 | 예시 |
|------|------|------|
| IP 주소 | 각 VM의 IP | `192.168.1.10` |
| SSH 사용자명 | SSH 계정 | `root` |
| SSH 비밀번호 | SSH 비밀번호 | |
| 호스트명 | K8s 노드명으로 사용 | `k8s-master` |

### Kubernetes 설정

| 항목 | 선택지 | 기본값 |
|------|--------|--------|
| K8s 버전 | 1.31 / 1.30 / 1.29 / 직접입력 | `1.31` |
| CNI 플러그인 | Antrea / Calico / Cilium | - |
| Pod CIDR | CNI별 자동 제안 | CNI 종류마다 상이 |
| Service CIDR | 직접 입력 | `10.96.0.0/12` |

### vSphere CSI Driver (선택)

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

## CNI 플러그인 비교

| CNI | 특징 | Pod CIDR 기본값 |
|-----|------|-----------------|
| **Antrea** | VMware 공식, NetworkPolicy 풍부, NSX 연동 가능 | `10.244.0.0/16` |
| **Calico** | BGP/IPIP 지원, 대규모 클러스터에 적합 | `192.168.0.0/16` |
| **Cilium** | eBPF 기반 고성능, 강력한 네트워크 보안 정책 | `10.0.0.0/8` |

## 설치 흐름

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

## 설치 후 확인

```bash
# Master 노드 접속
ssh <master-user>@<master-ip>

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
scp <master-user>@<master-ip>:~/.kube/config ~/.kube/config
kubectl get nodes
```

## 로그

스크립트 실행 디렉터리에 타임스탬프가 포함된 로그 파일이 생성됩니다.

```
k8s-install-20240329-143022.log
```

## 주의 사항

- 스크립트 실행 시 **각 노드의 기존 Kubernetes 설정이 초기화**됩니다.
- SSH 비밀번호는 메모리에만 저장되며 파일에 기록되지 않습니다.
- 설치 중 네트워크가 끊기면 일부 단계가 실패할 수 있습니다. 로그 파일을 확인하세요.
