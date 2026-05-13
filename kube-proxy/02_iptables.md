# 02. iptables 모드

## 개요

kube-proxy의 **기본 모드**로, 리눅스 커널의 netfilter(iptables) 프레임워크를 사용해
Service 트래픽을 처리합니다. kube-proxy가 각 Service/Endpoint마다 iptables 체인과 규칙을 생성하여
DNAT(Destination NAT)로 트래픽을 실제 Pod IP로 전달합니다.

---

## 아키텍처

```
패킷 수신 (ClusterIP:Port 목적지)
    │
    ▼
netfilter PREROUTING chain
    │
    ▼
KUBE-SERVICES chain
    │
    ├── KUBE-SVC-XXXX (Service A 체인)
    │       ├── KUBE-SEP-YYYY  → Pod 1 (33% 확률)
    │       ├── KUBE-SEP-YYYY  → Pod 2 (50% 확률)
    │       └── KUBE-SEP-YYYY  → Pod 3 (나머지)
    │
    └── KUBE-SVC-ZZZZ (Service B 체인)
            └── ...

각 KUBE-SEP-* 체인에서 DNAT 수행:
  목적지 변경: ClusterIP:Port → PodIP:Port
```

---

## 규칙 생성 방식

Service 1개 + Endpoint 3개 예시:

```bash
# kube-proxy가 자동 생성하는 규칙 (개념적 예시)
-A KUBE-SERVICES -d 10.96.0.1/32 -p tcp --dport 80 -j KUBE-SVC-ABCD

# 33% 확률로 Pod 1 선택
-A KUBE-SVC-ABCD -m statistic --mode random --probability 0.33 -j KUBE-SEP-POD1
# 50% 확률로 Pod 2 선택 (나머지 중 50%)
-A KUBE-SVC-ABCD -m statistic --mode random --probability 0.50 -j KUBE-SEP-POD2
# 나머지는 Pod 3
-A KUBE-SVC-ABCD -j KUBE-SEP-POD3

# 각 SEP 체인에서 DNAT
-A KUBE-SEP-POD1 -p tcp -j DNAT --to-destination 10.0.0.1:8080
-A KUBE-SEP-POD2 -p tcp -j DNAT --to-destination 10.0.0.2:8080
-A KUBE-SEP-POD3 -p tcp -j DNAT --to-destination 10.0.0.3:8080
```

---

## 장점

- **높은 호환성**: 대부분의 리눅스 배포판 기본 제공, 추가 커널 모듈 불필요
- **낮은 진입장벽**: `iptables -L`, `iptables-save` 등으로 규칙 직접 확인 가능
- **검증된 안정성**: 오랜 운영 이력, 다양한 환경에서 검증
- **conntrack 연동**: 연결 추적(conntrack)으로 세션 기반 NAT 유지
- **디버깅 용이**: iptables 명령어로 즉시 규칙 확인/수정 가능

---

## 단점

- **확장성 한계**: Service/Endpoint 수가 늘면 규칙 수 급증
  - 10,000 서비스 × 평균 5 Endpoint = 50,000+ 규칙
  - 패킷마다 규칙을 순차 검사 → CPU 오버헤드 증가
- **규칙 업데이트 비용**: Endpoint 1개 변경 시 전체 체인 재작성 필요
- **로드밸런싱 제한**: 확률적 Random 방식만 지원 (Least Connection 등 불가)
- **conntrack 테이블 압박**: 대량 연결 시 conntrack 테이블 고갈 가능성

---

## 성능 특성

| 항목 | 내용 |
|------|------|
| 서비스 조회 복잡도 | O(n) — 규칙 수에 선형 비례 |
| 규칙 업데이트 방식 | 전체 재작성 (iptables-restore) |
| 적합한 클러스터 규모 | 소~중간 (서비스 1,000개 미만 권장) |
| 로드밸런싱 방식 | Random (확률 기반) |

---

## 운영 확인 명령어

```bash
# kube-proxy 모드 확인
kubectl get configmap kube-proxy -n kube-system -o yaml | grep mode

# 생성된 KUBE-SERVICES 규칙 확인
iptables -t nat -L KUBE-SERVICES -n --line-numbers

# 특정 Service 체인 확인
iptables -t nat -L KUBE-SVC-XXXXXXXXXXXX -n

# 전체 규칙 수 확인
iptables -t nat -L | grep -c "^KUBE"

# conntrack 테이블 현황
conntrack -L | wc -l
conntrack -S
```

---

## 주의 사항

- 대규모 클러스터에서 Endpoint 변경이 잦으면 iptables-restore 호출이 빈번해져 CPU 스파이크 발생 가능
- `--masquerade-all` 옵션은 모든 트래픽에 SNAT 적용 — 불필요한 conntrack 항목 증가 유발
- kube-proxy가 iptables 규칙을 관리하므로 수동으로 KUBE-* 체인을 수정하면 충돌 발생
