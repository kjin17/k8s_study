# 04. nftables 모드

## 개요

**nftables**는 iptables의 차세대 대체 프레임워크로, 리눅스 커널 3.13에 도입되었습니다.
단일 통합 프레임워크에서 IPv4/IPv6/ARP/Bridge를 관리하며, 표현식 기반의 유연한 규칙 작성과
Set/Map을 활용한 효율적인 패킷 처리를 제공합니다.
kube-proxy의 nftables 모드는 **Kubernetes v1.31에서 GA(정식 지원)**로 승격되었습니다.

---

## 아키텍처

```
패킷 수신 (ClusterIP:Port 목적지)
    │
    ▼
nf_tables hook (PREROUTING)
    │
    ▼
kube-proxy nftables 테이블 (kube-proxy)
    │
    ▼
Set 조회 (O(log n) ~ O(1))
    │
    ├── kube_service_ips (Set: ClusterIP 목록)
    │       └── vmap 조회 → 해당 Service chain
    │               ├── kube_endpoints (Map: EndpointIP 목록)
    │               └── DNAT 수행
    │
    └── kube_nodeport_tcp (Set: NodePort 번호 목록)
```

nftables는 Set과 Map 자료구조를 활용하여 많은 수의 Service IP를
하나의 오브젝트로 관리합니다. 규칙 갱신 시 원자적 트랜잭션(atomic commit)으로 처리됩니다.

---

## iptables와 nftables 규칙 비교

```bash
# iptables 방식 — Service IP별로 규칙 반복
-A KUBE-SERVICES -d 10.96.0.1/32 -p tcp --dport 80 -j KUBE-SVC-AAAA
-A KUBE-SERVICES -d 10.96.0.2/32 -p tcp --dport 80 -j KUBE-SVC-BBBB
-A KUBE-SERVICES -d 10.96.0.3/32 -p tcp --dport 80 -j KUBE-SVC-CCCC
# ... (서비스 수만큼 반복)

# nftables 방식 — Set으로 일괄 관리
table ip kube-proxy {
  set kube_service_ips {
    type ipv4_addr . inet_proto . inet_service
    elements = {
      10.96.0.1 . tcp . 80 : goto svc_aaaa,
      10.96.0.2 . tcp . 80 : goto svc_bbbb,
      10.96.0.3 . tcp . 80 : goto svc_cccc,
    }
  }

  chain prerouting {
    type nat hook prerouting priority -100
    ip daddr . meta l4proto . th dport vmap @kube_service_ips
  }
}
```

---

## 장점

- **원자적 규칙 업데이트**: 트랜잭션 기반 업데이트로 규칙 변경 중 패킷 드롭 없음
- **Set/Map 활용**: 많은 수의 Service를 단일 오브젝트로 관리 → 규칙 수 감소
- **통합 프레임워크**: IPv4/IPv6/ARP를 하나의 nft 명령어로 관리
- **표현식 기반**: 복잡한 조건을 간결하게 표현, 가독성 향상
- **효율적인 업데이트**: 변경된 항목만 Set에 추가/삭제 (전체 재작성 불필요)
- **미래 지향적**: 주요 리눅스 배포판에서 iptables 대체 진행 중

---

## 단점

- **커널 버전 요구**: nftables 전체 기능 활용에는 커널 5.13+ 권장 (3.13에 도입, 버전별 기능 차이 있음)
- **운영자 학습 비용**: iptables에 익숙한 운영자에게 새로운 문법·구조 학습 필요
- **도구 변경**: `iptables` 대신 `nft` 명령어 사용, 기존 스크립트 수정 필요
- **kube-proxy 지원 역사 짧음**: v1.29 alpha → v1.31 GA, iptables/IPVS 대비 운영 이력 적음
- **일부 배포판 제약**: 구형 OS(CentOS 7, Ubuntu 18.04 등) 기본 커널에서 제한 가능

---

## 성능 특성

| 항목 | 내용 |
|------|------|
| 서비스 조회 복잡도 | O(log n) ~ O(1) — Set/Map 자료구조 |
| 규칙 업데이트 방식 | 원자적 트랜잭션 (개별 Set 항목 수정) |
| 적합한 클러스터 규모 | 중간~대규모 |
| 로드밸런싱 방식 | Random (확률 기반, numgen 활용) |

---

## kube-proxy nftables 모드 설정

```yaml
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "nftables"
nftables:
  masqueradeAll: false
  masqueradeBit: 14
  minSyncPeriod: "1s"
  syncPeriod: "30s"
```

> **참고**: Kubernetes v1.31 이상에서 GA 지원
> v1.29~v1.30은 alpha/beta 상태이므로 프로덕션 사용 시 버전 확인 필요

---

## 운영 확인 명령어

```bash
# nft 설치 확인
nft --version

# kube-proxy가 생성한 테이블 확인
nft list table ip kube-proxy

# 모든 Set 확인
nft list sets table ip kube-proxy

# 특정 Set 내용 확인 (Service IP 목록)
nft list set ip kube-proxy kube_service_ips

# Chain 확인
nft list chain ip kube-proxy prerouting

# 규칙 전체 덤프
nft list ruleset | grep -A 20 kube-proxy
```

---

## 주의 사항

- nftables 모드로 전환 시 기존 iptables 규칙과 충돌 방지를 위해 iptables-legacy/nft 버전 확인 필요
- `iptables-nft`(iptables의 nftables 백엔드)와 혼용 시 주의
- 일부 배포판에서 `iptables`가 내부적으로 nftables를 사용(iptables-nft)하는 경우 있음
  ```bash
  # 현재 iptables 백엔드 확인
  update-alternatives --display iptables  # Debian/Ubuntu
  ```
- 프로덕션 전환 전 반드시 스테이징 환경에서 검증 권장
