# Kubernetes CNI 비교: Antrea vs Calico vs Cilium

> Kubernetes 환경에서 가장 많이 사용되는 CNI(Container Network Interface) 플러그인
> **Antrea**, **Calico**, **Cilium**의 아키텍처, 특징, 차이점을 학습합니다.

---

## 📚 목차

| 파일 | 내용 |
|------|------|
| `01_cni_overview.md` | CNI 개념 및 동작 원리 |
| `02_antrea.md` | Antrea 아키텍처 및 특징 |
| `03_calico.md` | Calico 아키텍처 및 특징 |
| `04_cilium.md` | Cilium 아키텍처 및 특징 (eBPF) |
| `05_comparison.md` | 3대 CNI 상세 비교표 및 선택 가이드 |
| `06_hands_on.md` | 실습 예제 (설치, NetworkPolicy, 모니터링) |

---

## 🎯 학습 목표

1. CNI가 Kubernetes 네트워크에서 하는 역할을 이해한다
2. Antrea(OVS 기반), Calico(BGP/iptables), Cilium(eBPF)의 핵심 차이를 파악한다
3. 각 CNI의 NetworkPolicy 구현 방식을 비교한다
4. 운영 환경 특성에 맞는 CNI 선택 기준을 갖는다

---

## 한눈에 보는 비교

| 항목 | Antrea | Calico | Cilium |
|------|--------|--------|--------|
| 데이터 플레인 | OVS (Open vSwitch) | iptables / eBPF | eBPF |
| 개발사 | VMware (Broadcom) | Tigera | Isovalent (Cisco) |
| 성능 | 중간 | 중간~높음 | 매우 높음 |
| 관찰 가능성 | 보통 | 보통 | 매우 뛰어남 |
| L7 정책 | 제한적 | 제한적 | ✅ 완전 지원 |
| vSphere 통합 | ✅ 최적 | △ | △ |
| 커널 요구사항 | 낮음 | 낮음 | 높음 (4.9+, 권장 5.10+) |
