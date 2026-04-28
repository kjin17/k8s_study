# 02. Antrea

## 개요

VMware(현 Broadcom)가 개발한 Kubernetes CNI 플러그인으로,
**Open vSwitch(OVS)**를 데이터 플레인으로 사용합니다.
특히 **VMware vSphere / Tanzu** 환경에 최적화되어 있습니다.

---

## 아키텍처

```
┌─────────────────────────────────────────┐
│              Control Plane              │
│  ┌──────────────────────────────────┐   │
│  │       antrea-controller          │   │
│  │  - NetworkPolicy 계산            │   │
│  │  - OVS 플로우 규칙 생성          │   │
│  │  - IPAM 관리                     │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
              │ gRPC (Antrea API)
              ▼
┌─────────────────────────────────────────┐
│           각 노드 (DaemonSet)            │
│  ┌──────────────────────────────────┐   │
│  │         antrea-agent             │   │
│  │  - OVS 플로우 규칙 적용          │   │
│  │  - Pod 네트워크 설정             │   │
│  │  - IPAM 실행                     │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │    Open vSwitch (OVS)            │   │
│  │  - 패킷 포워딩                   │   │
│  │  - VXLAN/Geneve 터널링           │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

---

## 핵심 특징

### 1. OVS 기반 데이터 플레인
- 모든 패킷 처리를 OVS 파이프라인으로 수행
- 플로우 테이블 기반 → 정책 변경 시 빠른 적용
- VXLAN, Geneve, GRE, WireGuard 터널링 지원

### 2. Antrea NetworkPolicy (ANP)
Kubernetes 표준 NetworkPolicy를 확장한 고급 정책 CRD 제공

```yaml
apiVersion: crd.antrea.io/v1alpha1
kind: NetworkPolicy
metadata:
  name: allow-web-to-db
spec:
  priority: 5
  tier: application          # 정책 계층(tier) 지원
  appliedTo:
    - podSelector:
        matchLabels:
          app: db
  ingress:
    - action: Allow
      from:
        - podSelector:
            matchLabels:
              app: web
      ports:
        - protocol: TCP
          port: 5432
    - action: Drop            # 명시적 Drop 지원
      from:
        - namespaceSelector: {}
```

### 3. ClusterNetworkPolicy (ACNP)
클러스터 전체에 적용되는 관리자 수준 정책

```yaml
apiVersion: crd.antrea.io/v1alpha1
kind: ClusterNetworkPolicy
metadata:
  name: strict-namespace-isolation
spec:
  priority: 1
  tier: securityops
  appliedTo:
    - namespaceSelector: {}
  ingress:
    - action: Drop
      from:
        - namespaceSelector:
            matchExpressions:
              - key: kubernetes.io/metadata.name
                operator: NotIn
                values: ["kube-system"]
```

### 4. Tier(계층) 시스템
정책 우선순위를 계층으로 관리 (높을수록 먼저 평가)

| Tier | 우선순위 | 용도 |
|------|---------|------|
| emergency | 50 | 긴급 차단 |
| securityops | 100 | 보안팀 정책 |
| networkops | 150 | 네트워크팀 정책 |
| platform | 200 | 플랫폼 정책 |
| application | 250 | 앱 정책 |
| baseline | 253 | 기본 정책 |

---

## 주요 장점

- ✅ **vSphere/Tanzu 통합** — NSX-T와 연동, VMware 환경 최적
- ✅ **Antrea UI** — 내장 웹 UI로 플로우 시각화
- ✅ **멀티클러스터** — Antrea Multi-cluster 지원
- ✅ **WireGuard 암호화** — 노드 간 트래픽 암호화
- ✅ **낮은 커널 요구사항** — 레거시 환경에서도 동작

## 주요 단점

- ❌ OVS 복잡도 — 디버깅 난이도 높음
- ❌ eBPF 미지원 (기본) — 성능 한계
- ❌ L7 정책 제한적

---

## 설치

```bash
# Antrea 설치
kubectl apply -f https://github.com/antrea-io/antrea/releases/download/v1.15.0/antrea.yml

# antrea-agent 상태 확인
kubectl get pods -n kube-system -l app=antrea

# antctl CLI 설치
curl -Lo antctl https://github.com/antrea-io/antrea/releases/download/v1.15.0/antctl-linux-x86_64
chmod +x antctl && sudo mv antctl /usr/local/bin/

# 상태 확인
antctl get featuregates
antctl get networkpolicy -A
```
