# 03. Calico

## 개요

Tigera가 개발한 가장 널리 사용되는 CNI 플러그인입니다.
**BGP 라우팅** 기반의 순수 L3 네트워크와 **iptables/eBPF** 데이터 플레인을 지원합니다.
온프레미스부터 클라우드까지 범용적으로 사용됩니다.

---

## 아키텍처

```
┌─────────────────────────────────────────┐
│              Control Plane              │
│  ┌───────────────┐  ┌───────────────┐   │
│  │  calico-kube- │  │   Typha       │   │
│  │  controllers  │  │ (대규모 클러  │   │
│  │               │  │  스터 캐시)   │   │
│  └───────────────┘  └───────────────┘   │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│           각 노드 (DaemonSet)            │
│  ┌──────────────────────────────────┐   │
│  │         calico-node              │   │
│  │  ┌────────┐  ┌────────────────┐  │   │
│  │  │  BIRD  │  │    Felix       │  │   │
│  │  │ (BGP   │  │ (정책 에이전트 │  │   │
│  │  │  데몬) │  │  iptables 관리)│  │   │
│  │  └────────┘  └────────────────┘  │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### 주요 컴포넌트

| 컴포넌트 | 역할 |
|---------|------|
| **Felix** | 각 노드의 정책 에이전트 — iptables/eBPF 규칙 관리 |
| **BIRD** | BGP 데몬 — 노드 간 라우팅 정보 교환 |
| **Typha** | Felix-datastore 간 캐시 프록시 (대규모 클러스터) |
| **calico-kube-controllers** | K8s API → Calico 자원 동기화 |
| **calicoctl** | Calico 관리 CLI |

---

## 네트워킹 모드

### 1. BGP (Direct/Native) — 권장
오버레이 없이 BGP로 Pod 라우팅 정보를 직접 교환합니다.

```
Node A (10.0.1.0/24)  ←──BGP──→  Node B (10.0.2.0/24)
Pod: 10.0.1.5                     Pod: 10.0.2.7
직접 라우팅 — 오버레이 없음 → 최고 성능
```

### 2. VXLAN 오버레이
BGP를 사용할 수 없는 환경(클라우드 VPC 등)에서 사용

### 3. IPinIP 터널
두 번째 IP 헤더로 캡슐화 — BGP 불가 환경 대안

---

## Calico NetworkPolicy

```yaml
apiVersion: projectcalico.org/v3
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  selector: app == 'backend'
  types:
    - Ingress
    - Egress
  ingress:
    - action: Allow
      source:
        selector: app == 'frontend'
      destination:
        ports: [8080]
  egress:
    - action: Allow
      destination:
        selector: app == 'database'
        ports: [5432]
    - action: Deny   # 나머지 Egress 차단
```

### GlobalNetworkPolicy — 클러스터 전체 정책

```yaml
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-all-egress-except-dns
spec:
  selector: all()
  order: 100
  egress:
    - action: Allow
      destination:
        ports: [53]
        selector: k8s-app == 'kube-dns'
    - action: Deny
```

---

## IP Pool 관리

```yaml
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: default-ipv4-pool
spec:
  cidr: 192.168.0.0/16
  ipipMode: Never           # IPinIP 비활성화
  vxlanMode: Never          # VXLAN 비활성화
  natOutgoing: true
  nodeSelector: all()
  blockSize: 26             # 노드당 /26 블록 (64 IP)
```

---

## eBPF 모드 (Calico eBPF)

iptables 대신 eBPF를 데이터 플레인으로 사용합니다.

```bash
# eBPF 모드 활성화
calicoctl patch felixconfiguration default \
  --patch='{"spec": {"bpfEnabled": true}}'

# kube-proxy 비활성화 (Calico eBPF가 대체)
kubectl patch ds -n kube-system kube-proxy \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico": "true"}}}}}'
```

---

## 주요 장점

- ✅ **범용성** — 온프레미스, AWS, GCP, Azure 모두 지원
- ✅ **BGP 네이티브 라우팅** — 오버레이 없이 최고 성능
- ✅ **성숙도** — 가장 오래된 CNI, 대규모 운영 검증
- ✅ **Calico Enterprise** — Tigera의 상용 버전으로 고급 보안 기능
- ✅ **eBPF 옵션** — 성능 향상 가능

## 주요 단점

- ❌ iptables 모드 — 대규모 환경에서 성능 저하
- ❌ BGP 설정 복잡성 — 네트워크 지식 필요
- ❌ L7 정책 — Cilium 대비 제한적

---

## 설치

```bash
# Calico Operator 설치
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# Installation 설정
kubectl create -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
        cidr: 192.168.0.0/16
        encapsulation: None   # BGP 모드
        natOutgoing: Enabled
EOF

# 상태 확인
kubectl get tigerastatus
kubectl get pods -n calico-system

# calicoctl 설치
curl -Lo calicoctl https://github.com/projectcalico/calico/releases/download/v3.27.0/calicoctl-linux-amd64
chmod +x calicoctl && sudo mv calicoctl /usr/local/bin/

calicoctl get nodes
calicoctl get ippool
```
