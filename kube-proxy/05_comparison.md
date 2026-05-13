# 05. 3대 모드 상세 비교 및 선택 가이드

## 종합 비교표

### 아키텍처 & 구현 방식

| 항목 | iptables | IPVS | nftables |
|------|----------|------|----------|
| 커널 구현 | netfilter 규칙 체인 | ip_vs 해시 테이블 | nf_tables Set/Map |
| 패킷 처리 | 규칙 순차 검사 | 해시 직접 매핑 | Set/Map 조회 |
| NAT 방식 | DNAT (conntrack) | DNAT (conntrack) | DNAT (conntrack) |
| 업데이트 방식 | 전체 재작성 | 개별 항목 수정 | 원자적 트랜잭션 |
| IPv6 지원 | ✅ | ✅ | ✅ |
| kube-proxy 기본값 | ✅ | ❌ | ❌ |

---

### 성능

| 항목 | iptables | IPVS | nftables |
|------|----------|------|----------|
| 서비스 조회 복잡도 | O(n) | O(1) | O(log n) ~ O(1) |
| 1,000 서비스 성능 | 중간 | 높음 | 높음 |
| 10,000 서비스 성능 | ❌ 저하 심각 | ✅ 유지 | ✅ 유지 |
| CPU 오버헤드 (대규모) | 높음 | 낮음 | 낮음 |
| 규칙 업데이트 비용 | 높음 (전체 재작성) | 낮음 | 낮음 |
| conntrack 부하 | 높음 | 중간 | 중간 |

---

### 로드밸런싱

| 항목 | iptables | IPVS | nftables |
|------|----------|------|----------|
| Round Robin | ✅ (확률 기반) | ✅ (rr) | ✅ (확률 기반) |
| Least Connection | ❌ | ✅ (lc) | ❌ |
| Weighted Round Robin | ❌ | ✅ (wrr) | ❌ |
| Source Hash (세션 어피니티) | △ (sessionAffinity) | ✅ (sh) | △ (sessionAffinity) |
| Destination Hash | ❌ | ✅ (dh) | ❌ |

---

### 운영 환경

| 항목 | iptables | IPVS | nftables |
|------|----------|------|----------|
| 커널 버전 요구 | 낮음 (3.x+) | 중간 (4.1+ 권장) | 높음 (5.13+ 권장) |
| 추가 커널 모듈 | 불필요 | ip_vs_* 모듈 필요 | 불필요 |
| 추가 도구 | 불필요 | ipvsadm, ipset | nft |
| kube-proxy 지원 상태 | 안정 (기본값) | 안정 | GA (v1.31+) |
| 구형 OS 지원 | ✅ | ✅ | △ |
| 디버깅 난이도 | 낮음 | 중간 | 중간 |

---

### 보안 및 안정성

| 항목 | iptables | IPVS | nftables |
|------|----------|------|----------|
| 원자적 규칙 업데이트 | ❌ (비원자적) | △ | ✅ |
| 규칙 업데이트 중 패킷 드롭 | 가능성 있음 | 낮음 | 없음 |
| 운영 이력 | 매우 많음 | 많음 | 적음 (신규) |
| 프로덕션 검증 | ✅ 광범위 | ✅ 대규모 환경 | △ 제한적 |

---

## 선택 가이드

### iptables를 선택해야 할 때

```
✅ 소~중간 규모 클러스터 (서비스 1,000개 미만)
✅ 구형 리눅스 배포판 환경 (CentOS 7, Ubuntu 18.04 등)
✅ 기존 iptables 운영 경험 및 디버깅 툴 체계가 갖춰진 경우
✅ 추가 커널 모듈 설치가 제한된 환경 (관리형 K8s 등)
✅ 안정성 최우선 — 가장 오랜 운영 이력
```

### IPVS를 선택해야 할 때

```
✅ 대규모 클러스터 (서비스 1,000개 이상, 노드 수백 개 이상)
✅ Least Connection, Weighted 등 고급 로드밸런싱 알고리즘이 필요한 경우
✅ 고빈도 트래픽 환경에서 CPU 오버헤드 최소화가 중요한 경우
✅ 커널 모듈 설치 가능한 환경 (베어메탈, 자체 관리 클러스터)
✅ 대량 Endpoint 변경이 빈번한 환경
```

### nftables를 선택해야 할 때

```
✅ 최신 리눅스 배포판 환경 (Ubuntu 22.04+, RHEL 9+, Debian 11+)
✅ Kubernetes v1.31 이상 사용 환경
✅ iptables deprecated 이후를 대비한 미래 지향적 설계
✅ 원자적 규칙 업데이트로 다운타임 없는 규칙 변경이 필요한 경우
✅ 이미 nftables 기반 방화벽 운영 환경과의 통합
```

---

## 마이그레이션 고려사항

```
iptables  →  IPVS     : 커널 모듈 사전 설치 필요, kube-proxy 재시작
iptables  →  nftables : K8s v1.31+ 필요, 최신 커널 확인
IPVS      →  nftables : K8s v1.31+ 필요, ipvsadm 규칙 정리 필요
```

**공통 주의사항:**
- 모드 전환 시 kube-proxy DaemonSet 재시작 필요
- 이전 모드에서 생성된 규칙이 자동으로 정리되는지 확인
- 프로덕션 전환 전 반드시 스테이징 환경에서 검증

```bash
# kube-proxy 모드 전환 후 이전 iptables 규칙 정리
kube-proxy --cleanup
# 또는 kube-proxy DaemonSet 재시작
kubectl rollout restart daemonset kube-proxy -n kube-system
```

---

## 버전별 지원 상태

| Kubernetes 버전 | iptables | IPVS | nftables |
|----------------|----------|------|----------|
| v1.0 ~ v1.1 | userspace (기본) | ❌ | ❌ |
| v1.2+ | ✅ GA (기본값) | ❌ | ❌ |
| v1.8+ | ✅ | ✅ beta | ❌ |
| v1.11+ | ✅ | ✅ GA | ❌ |
| v1.29 | ✅ | ✅ | alpha |
| v1.30 | ✅ | ✅ | beta |
| **v1.31+** | ✅ | ✅ | **✅ GA** |
