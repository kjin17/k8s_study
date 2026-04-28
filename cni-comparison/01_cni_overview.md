# 01. CNI 개요 및 동작 원리

## CNI(Container Network Interface)란?

CNCF가 정의한 표준 인터페이스로, 컨테이너의 네트워크 인터페이스를 설정/해제하는 플러그인 규격입니다.
Kubernetes는 CNI 플러그인에 네트워크 구성을 위임합니다.

---

## Kubernetes 네트워크 모델의 4대 요구사항

1. **Pod 간 NAT 없이 통신** — 모든 Pod는 고유 IP, 직접 통신
2. **노드-Pod 간 NAT 없이 통신** — 노드에서 Pod IP로 직접 접근
3. **Pod가 자신의 IP를 인식** — 내부/외부 IP 동일
4. **Service 추상화** — ClusterIP, NodePort, LoadBalancer 지원

CNI 플러그인이 이 요구사항을 구현합니다.

---

## CNI 동작 흐름

```
kubelet이 Pod 생성 요청
    │
    ▼
컨테이너 런타임 (containerd/CRI-O)
    │
    ▼
CNI 플러그인 호출 (/etc/cni/net.d/ 설정 참조)
    │
    ├── 네트워크 인터페이스 생성 (veth pair)
    ├── IP 주소 할당 (IPAM)
    ├── 라우팅 테이블 설정
    └── 네트워크 정책 적용
```

---

## CNI 플러그인 구성요소

```
/etc/cni/net.d/          ← CNI 설정 파일 (JSON)
/opt/cni/bin/            ← CNI 바이너리
```

```json
// 예시: /etc/cni/net.d/10-calico.conflist
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "calico",
      "ipam": { "type": "calico-ipam" }
    },
    { "type": "portmap" },
    { "type": "bandwidth" }
  ]
}
```

---

## IPAM(IP Address Management)

CNI 플러그인은 각자의 IPAM으로 Pod에 IP를 할당합니다.

| CNI | IPAM 방식 |
|-----|---------|
| Antrea | 자체 IPAM (antrea-ipam) |
| Calico | calico-ipam (IP Pool 기반) |
| Cilium | cilium-ipam (CiliumNode CRD) |

---

## 데이터 플레인 비교

| 방식 | 설명 | 사용 CNI |
|------|------|---------|
| **OVS** | Open vSwitch 기반 소프트웨어 스위치 | Antrea |
| **iptables** | 커널 netfilter 규칙 | Calico (기본) |
| **IPVS** | IP Virtual Server, iptables보다 확장성 좋음 | Calico (옵션) |
| **eBPF** | 커널 내 프로그래머블 패킷 처리 | Cilium, Calico (옵션) |

---

## NetworkPolicy 처리 방식

NetworkPolicy는 Pod 간 트래픽을 제어하는 Kubernetes 표준 리소스입니다.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 8080
```

각 CNI는 이를 자신의 방식으로 구현합니다:
- **Antrea** → OVS 플로우 규칙
- **Calico** → iptables/eBPF 규칙
- **Cilium** → eBPF 프로그램 (L3~L7)
