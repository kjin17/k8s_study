# 01. kube-proxy 개요 및 동작 원리

## kube-proxy란?

Kubernetes 클러스터의 모든 노드에서 실행되는 네트워크 프록시 컴포넌트입니다.
Service 오브젝트의 가상 IP(ClusterIP)를 실제 Pod IP로 연결하는 NAT 규칙을 노드에 설정합니다.

---

## kube-proxy의 역할

```
Client Pod
    │
    ▼
ClusterIP:Port  (가상 IP — 실제 존재하지 않음)
    │
    ▼
kube-proxy가 생성한 규칙 (iptables / IPVS / nftables)
    │
    ├── Endpoint A (Pod 10.0.0.1:8080)
    ├── Endpoint B (Pod 10.0.0.2:8080)
    └── Endpoint C (Pod 10.0.0.3:8080)
```

- **Service 감시**: kube-apiserver에서 Service/Endpoints 변경 이벤트를 감시
- **규칙 동기화**: 변경 감지 시 해당 노드의 네트워크 규칙을 즉시 업데이트
- **트래픽 분산**: 들어오는 트래픽을 정상 Endpoint로 로드밸런싱

---

## kube-proxy 동작 흐름

```
Service 생성/변경
    │
    ▼
kube-apiserver 이벤트 발생
    │
    ▼
kube-proxy (각 노드에서 감시 중)
    │
    ▼
선택된 모드로 규칙 생성/업데이트
    ├── iptables 모드 → netfilter 규칙 체인 갱신
    ├── IPVS 모드    → ipvs 가상서버/실제서버 테이블 갱신
    └── nftables 모드 → nf_tables Set/Map 갱신
    │
    ▼
패킷이 ClusterIP에 도달하면 규칙에 따라 DNAT 처리
```

---

## 지원 모드 개요

| 모드 | 커널 기술 | 주요 도구 | 기본값 여부 |
|------|----------|----------|------------|
| **iptables** | netfilter (iptables) | iptables, conntrack | ✅ 기본값 (v1.2+) |
| **IPVS** | ip_vs (LVS) | ipvsadm, ipset | 수동 설정 필요 |
| **nftables** | nf_tables | nft | GA (v1.31+) |
| ~~userspace~~ | 사용자공간 프록시 | - | ❌ Deprecated |

---

## kube-proxy 설정 방법

```yaml
# kube-proxy ConfigMap 예시
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-proxy
  namespace: kube-system
data:
  config.conf: |
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    kind: KubeProxyConfiguration
    mode: "ipvs"          # iptables | ipvs | nftables
    ipvs:
      scheduler: "rr"     # IPVS 모드일 때 스케줄러
```

---

## Service 타입별 kube-proxy 처리

| Service 타입 | kube-proxy 역할 |
|-------------|----------------|
| **ClusterIP** | DNAT 규칙으로 ClusterIP → Pod IP 변환 |
| **NodePort** | ClusterIP 규칙 + 노드 포트 수신 규칙 추가 |
| **LoadBalancer** | NodePort 규칙 + 외부 LB 연동 (클라우드 컨트롤러) |
| **ExternalName** | DNS CNAME 처리 (kube-dns/CoreDNS) |

---

## kube-proxy 없이 운영하는 경우

일부 CNI는 kube-proxy를 완전히 대체할 수 있습니다.

| CNI | kube-proxy 대체 | 방식 |
|-----|----------------|------|
| Cilium | ✅ | eBPF 기반 서비스 처리 |
| Calico | ✅ (eBPF 모드) | eBPF 기반 서비스 처리 |
| Antrea | ❌ | kube-proxy 병행 필요 |
