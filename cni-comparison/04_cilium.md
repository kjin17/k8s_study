# 04. Cilium

## 개요

Isovalent(현 Cisco)가 개발한 차세대 CNI 플러그인입니다.
Linux 커널의 **eBPF(extended Berkeley Packet Filter)** 기술을 핵심으로 사용하며,
L3/L4뿐 아니라 **L7(HTTP, gRPC, Kafka)** 수준의 네트워크 정책을 지원합니다.
CNCF Graduated 프로젝트.

---

## 아키텍처

```
┌─────────────────────────────────────────┐
│              Control Plane              │
│  ┌──────────────────────────────────┐   │
│  │         cilium-operator          │   │
│  │  - CiliumNode 관리               │   │
│  │  - IPAM 조율                     │   │
│  │  - 인증서 관리                   │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│           각 노드 (DaemonSet)            │
│  ┌──────────────────────────────────┐   │
│  │         cilium-agent             │   │
│  │  - eBPF 프로그램 컴파일/로드     │   │
│  │  - CiliumNetworkPolicy 처리      │   │
│  │  - Envoy 프록시 관리 (L7)        │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │  eBPF 프로그램 (커널 내)         │   │
│  │  - XDP: 패킷 최조속 처리         │   │
│  │  - TC hook: 패킷 조작            │   │
│  │  - socket hook: 소켓 레벨        │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

---

## eBPF란?

커널 코드를 수정하지 않고 **커널 내에서 안전하게 프로그램을 실행**하는 기술입니다.

```
기존 방식 (iptables):
패킷 → netfilter hook → iptables 규칙 순차 탐색 → 처리
(규칙 10,000개 시 O(n) 선형 탐색)

eBPF 방식 (Cilium):
패킷 → eBPF 프로그램 (커널 내 JIT 컴파일) → 처리
(해시 맵 기반 O(1) 조회, kube-proxy 대체)
```

**주요 장점:**
- iptables 규칙 없음 → 대규모 환경에서 선형 성능 저하 없음
- XDP(eXpress Data Path): NIC 드라이버 수준에서 패킷 처리 (최고 성능)
- 소켓 레벨 단락(short-circuit): 같은 노드 Pod 간 통신 시 네트워크 스택 우회

---

## 핵심 기능

### 1. L7 NetworkPolicy (HTTP/gRPC/Kafka)

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-get-only
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
          rules:
            http:
              - method: GET            # GET만 허용
                path: /api/v1/.*       # 특정 경로만 허용
```

```yaml
# gRPC 정책
toPorts:
  - ports:
      - port: "50051"
        protocol: TCP
    rules:
      l7proto: grpc
      l7:
        - method: /mypackage.MyService/GetUser
```

### 2. CiliumNetworkPolicy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: db-access
spec:
  endpointSelector:
    matchLabels:
      app: database
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: backend
      toPorts:
        - ports:
            - port: "5432"
    - fromEntities:               # 외부 엔티티
        - cluster                 # 클러스터 내부만
  egress:
    - toFQDNs:                    # DNS 기반 정책
        - matchName: "db.example.com"
```

### 3. FQDN 기반 Egress 정책

```yaml
# 도메인명으로 외부 접근 제어
egress:
  - toFQDNs:
      - matchName: "api.github.com"
      - matchPattern: "*.amazonaws.com"
    toPorts:
      - ports:
          - port: "443"
```

### 4. Hubble — 네트워크 관찰 가능성

Cilium 내장 관찰 플랫폼. 모든 네트워크 흐름을 실시간으로 추적합니다.

```bash
# Hubble 활성화
cilium hubble enable --ui

# Hubble UI 접속
cilium hubble ui

# CLI로 실시간 플로우 확인
hubble observe --follow
hubble observe --namespace production --follow
hubble observe --pod frontend/frontend-xxx --follow

# 드롭된 패킷 확인
hubble observe --verdict DROPPED
```

### 5. kube-proxy 대체

```bash
# Cilium이 kube-proxy 완전 대체 (eBPF 기반 Service 처리)
cilium install --set kubeProxyReplacement=strict

# 확인
cilium status | grep KubeProxyReplacement
```

---

## 주요 장점

- ✅ **최고 성능** — eBPF로 iptables 완전 대체, 대규모 환경 선형 성능 유지
- ✅ **L7 정책** — HTTP method/path, gRPC method, Kafka topic 수준 제어
- ✅ **Hubble** — 내장 네트워크 관찰 플랫폼 (플로우, 토폴로지, 메트릭)
- ✅ **FQDN 정책** — 도메인 기반 Egress 제어
- ✅ **mTLS 내장** — Cilium Mutual Auth (Istio 없이 서비스 간 mTLS)
- ✅ **멀티클러스터** — Cluster Mesh 지원

## 주요 단점

- ❌ **커널 요구사항** — 최소 4.9, 전체 기능은 5.10+ 권장
- ❌ **복잡도** — eBPF 디버깅 난이도 높음
- ❌ **레거시 환경 제한** — 구형 OS에서 기능 제한

---

## 설치

```bash
# Cilium CLI 설치
curl -L --remote-name https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz && sudo mv cilium /usr/local/bin/

# Cilium 설치 (kube-proxy 대체 포함)
cilium install --version 1.15.0 \
  --set kubeProxyReplacement=strict

# 상태 확인
cilium status --wait
cilium connectivity test

# Hubble 활성화
cilium hubble enable --ui
hubble observe --follow
```
