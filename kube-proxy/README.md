# kube-proxy 모드 비교: iptables vs IPVS vs nftables

> Kubernetes 서비스 트래픽을 처리하는 핵심 컴포넌트 **kube-proxy**의
> 세 가지 동작 모드 **iptables**, **IPVS**, **nftables**의 아키텍처, 특징, 차이점을 학습합니다.

---

## 📚 목차

| 파일 | 내용 |
|------|------|
| `01_kube_proxy_overview.md` | kube-proxy 개념 및 동작 원리 |
| `02_iptables.md` | iptables 모드 아키텍처 및 특징 |
| `03_ipvs.md` | IPVS 모드 아키텍처 및 특징 |
| `04_nftables.md` | nftables 모드 아키텍처 및 특징 |
| `05_comparison.md` | 3대 모드 상세 비교표 및 선택 가이드 |

---

## 🎯 학습 목표

1. kube-proxy가 Kubernetes 서비스에서 하는 역할을 이해한다
2. iptables(netfilter), IPVS(ip_vs), nftables(nf_tables)의 핵심 차이를 파악한다
3. 각 모드의 성능 특성과 운영 환경 적합성을 비교한다
4. 클러스터 규모와 요구사항에 맞는 모드 선택 기준을 갖는다

---

## 한눈에 보는 비교

| 항목 | iptables | IPVS | nftables |
|------|----------|------|----------|
| 커널 구현 | netfilter 규칙 | ip_vs 해시 테이블 | nf_tables 프레임워크 |
| 패킷 처리 방식 | 규칙 순차 검사 | 해시 기반 직접 매핑 | 표현식 + Set/Map |
| 확장성 | 낮음 (규칙 수 비례) | 높음 (O(1) 조회) | 중간~높음 |
| 로드밸런싱 알고리즘 | Random (확률적) | RR / LC / WLC 등 | Random |
| 커널 요구사항 | 낮음 (3.x+) | 중간 (모듈 필요) | 높음 (5.13+ 권장) |
| 디버깅 난이도 | 낮음 | 중간 | 중간 |
| kube-proxy 지원 상태 | 안정 (기본값) | 안정 | GA (v1.31+) |
