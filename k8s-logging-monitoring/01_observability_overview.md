# 01. Observability 개요

## Observability란?

관측성(Observability)은 시스템 내부 상태를 외부 출력만으로 추론할 수 있게 하는 능력입니다.

Kubernetes에서는 다음 세 축이 핵심입니다.

- **Logging**: 무슨 일이 일어났는가?
- **Metrics**: 얼마나 자주/많이 일어나는가?
- **Tracing**: 요청이 어디를 거쳤는가?

---

## 3 Pillars of Observability

```text
              ┌───────────────┐
              │   Tracing     │  요청 경로 추적
              └──────┬────────┘
                     │
┌───────────────┐    │    ┌───────────────┐
│   Logging     │────┼────│   Metrics     │
│ 이벤트 상세    │    │    │ 숫자/추세     │
└───────────────┘         └───────────────┘
```

### Logging
- 이벤트 단위 상세 정보
- 에러 원인 분석에 강함
- 너무 많으면 검색 비용이 커짐

### Metrics
- 시계열 숫자 데이터
- 경향 파악, 경보에 강함
- 원인 세부정보는 부족함

### Tracing
- 요청 단위의 경로 추적
- 분산 시스템 병목 파악에 강함
- 샘플링 설계가 중요함

---

## SLI / SLO / SLA

| 용어 | 의미 | 예시 |
|------|------|------|
| SLI | 품질을 측정하는 지표 | 성공률, p95 latency, error rate |
| SLO | 목표 수준 | 99.9% 성공률 |
| SLA | 고객과의 계약 | 월 99.5% 미만이면 크레딧 제공 |

### 실무 포인트
- 알림은 SLI 자체보다 **SLO 위반 가능성**을 기준으로 설계하는 것이 좋습니다.
- 사용자 경험에 직접 영향을 주는 지표를 우선 선택합니다.

---

## Good Metrics의 조건

좋은 메트릭은 다음 조건을 만족합니다.

1. 사용자 경험과 연결된다
2. 행동으로 옮길 수 있다
3. 추세를 보기에 적합하다
4. 비용이 과도하지 않다

예:
- `http_requests_total`
- `http_request_duration_seconds_bucket`
- `container_cpu_usage_seconds_total`
- `node_memory_MemAvailable_bytes`

---

## Kubernetes에서 자주 보는 관측 대상

- Pod restart count
- CPU / memory usage
- OOMKilled 여부
- Node NotReady 상태
- PVC pending
- 이미지 pull 실패
- 네트워크 정책 차단
- HPA scale out / in 이벤트

---

## 권장 원칙

- 숫자는 메트릭, 문맥은 로그, 경로는 트레이스로 분리
- 동일한 요청을 로그/메트릭/트레이스로 연결할 수 있게 correlation id를 심는다
- 운영은 “데이터를 더 많이”가 아니라 “필요한 신호를 더 잘” 보는 방향으로 간다
