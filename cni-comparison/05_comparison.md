# 05. 3대 CNI 상세 비교 및 선택 가이드

## 종합 비교표

### 아키텍처 & 데이터 플레인

| 항목 | Antrea | Calico | Cilium |
|------|--------|--------|--------|
| 데이터 플레인 | OVS | iptables / eBPF(옵션) | eBPF |
| 오버레이 | VXLAN, Geneve, GRE | IPinIP, VXLAN | VXLAN, Geneve |
| 언더레이(BGP) | ❌ | ✅ (핵심 기능) | ✅ (BGP Control Plane) |
| kube-proxy 대체 | ❌ | ✅ (eBPF 모드) | ✅ (기본 지원) |
| IPv6 지원 | ✅ | ✅ | ✅ |
| 듀얼스택 | ✅ | ✅ | ✅ |

---

### 네트워크 정책

| 항목 | Antrea | Calico | Cilium |
|------|--------|--------|--------|
| K8s NetworkPolicy | ✅ | ✅ | ✅ |
| 고급 CNI 정책 | ANP, ACNP | GlobalNetworkPolicy | CiliumNetworkPolicy |
| L3/L4 정책 | ✅ | ✅ | ✅ |
| L7 HTTP 정책 | ❌ | ❌ | ✅ |
| L7 gRPC 정책 | ❌ | ❌ | ✅ |
| FQDN 기반 정책 | △ | ✅ | ✅ |
| 정책 우선순위(Tier) | ✅ | ✅ | ✅ |
| 명시적 Deny | ✅ | ✅ | ✅ |
| 클러스터 전체 정책 | ✅ (ACNP) | ✅ (GNP) | ✅ (CCNP) |

---

### 성능

| 항목 | Antrea | Calico (iptables) | Calico (eBPF) | Cilium |
|------|--------|------------------|---------------|--------|
| 처리량 | 중간 | 중간 | 높음 | 매우 높음 |
| 지연 시간 | 중간 | 중간 | 낮음 | 매우 낮음 |
| 대규모 확장성 | 중간 | 낮음~중간 | 높음 | 매우 높음 |
| 10,000 서비스 이상 | △ | ❌ (iptables 한계) | ✅ | ✅ |
| 노드 간 암호화 | WireGuard | WireGuard | WireGuard | WireGuard / IPSec |

---

### 관찰 가능성

| 항목 | Antrea | Calico | Cilium |
|------|--------|--------|--------|
| 플로우 로깅 | ✅ (Antrea Flow Exporter) | ✅ (Felix 로그) | ✅✅ (Hubble) |
| 토폴로지 시각화 | ✅ (Antrea UI) | ✅ (Calico Enterprise) | ✅✅ (Hubble UI) |
| Prometheus 메트릭 | ✅ | ✅ | ✅ |
| 분산 추적 연동 | △ | △ | ✅ (Hubble → Jaeger) |
| 실시간 패킷 드롭 분석 | △ | △ | ✅ |

---

### 보안

| 항목 | Antrea | Calico | Cilium |
|------|--------|--------|--------|
| mTLS | △ (WireGuard 노드간) | △ (WireGuard 노드간) | ✅ (Cilium Mutual Auth) |
| 암호화 | WireGuard | WireGuard | WireGuard / IPSec |
| ID 기반 정책 | Label 기반 | Label 기반 | Label + 암호화 ID |

---

### 운영 환경 지원

| 항목 | Antrea | Calico | Cilium |
|------|--------|--------|--------|
| vSphere / Tanzu | ✅ 최적 | △ | △ |
| AWS EKS | ✅ | ✅ | ✅ |
| GKE | △ | ✅ | ✅ |
| AKS (Azure) | △ | ✅ | ✅ |
| 온프레미스 | ✅ | ✅ | ✅ |
| 멀티클러스터 | ✅ | ✅ (Federation) | ✅ (Cluster Mesh) |
| 커널 요구사항 | 낮음 (3.x+) | 낮음 (3.x+) | 높음 (5.10+ 권장) |

---

## 선택 가이드

### Antrea를 선택해야 할 때

```
✅ VMware vSphere / Tanzu / NSX-T 환경
✅ 정책 계층(Tier) 구조가 필요한 엔터프라이즈 환경
✅ 레거시 Linux 커널 환경 (eBPF 불가)
✅ OVS 기반 SDN에 익숙한 팀
```

### Calico를 선택해야 할 때

```
✅ BGP 라우팅 환경 (베어메탈, 전용 네트워크)
✅ 오버레이 없는 최고 성능의 순수 L3 라우팅 필요
✅ 이미 Calico를 운영 중인 레거시 클러스터
✅ 다양한 클라우드/온프레미스 혼합 환경
✅ 안정성과 성숙도 우선 (가장 오랜 운영 이력)
```

### Cilium을 선택해야 할 때

```
✅ 대규모 클러스터 (노드 수백~수천 개)
✅ L7 수준 네트워크 정책 필요 (HTTP/gRPC/Kafka)
✅ 서비스 메시 없이 mTLS 구현 필요
✅ 네트워크 관찰 가능성이 중요한 환경
✅ 최신 Linux 커널 환경 (5.10+)
✅ 마이크로서비스 보안 강화 필요
```

---

## 마이그레이션 고려사항

```
Flannel/Weave → Calico   : 비교적 쉬움 (iptables 기반 유지)
Calico       → Cilium    : 주의 필요 (커널 요구사항, eBPF 전환)
Calico       → Antrea    : VMware 환경 전환 시
```

**주의:** 운영 클러스터의 CNI 변경은 노드 롤링 재시작 또는 클러스터 재구축이 필요합니다.
