# Kubernetes Logging & Monitoring Best Practices

> Kubernetes 환경에서 **로그 수집**, **메트릭 관측**, **알림 체계**, **운영 표준**을 함께 익히는 실무형 교육 자료입니다.
>
> 목표는 단순히 도구를 나열하는 것이 아니라, **애플리케이션 로그 / 클러스터 메트릭 / 경보 / 대시보드 / 트러블슈팅**이 어떻게 연결되는지 이해하는 것입니다.

---

## 📚 목차

| 파일 | 내용 |
|------|------|
| `01_observability_overview.md` | Observability 개요, SLI/SLO/SLI, 3 Pillars |
| `02_logging_best_practices.md` | Kubernetes 로깅 구조와 Best Practice |
| `03_monitoring_best_practices.md` | Prometheus/Grafana 중심 모니터링 설계 |
| `04_alerting_best_practices.md` | Alertmanager 기반 경보 설계 및 운영 |
| `05_k8s_observability_best_practices.md` | K8s 운영 관점의 관측성 Best Practice |
| `06_hands_on.md` | 실습: 로그/메트릭/알림/대시보드 구성 예제 |

---

## 🎯 학습 목표

1. Kubernetes에서 로그와 메트릭이 어디에 쌓이고 어떻게 흐르는지 이해한다
2. 앱 로그는 stdout/stderr, 구조화 로그, 추적 ID 중심으로 설계한다
3. Prometheus, Grafana, Alertmanager의 역할을 구분하고 함께 운영한다
4. 노이즈가 적고 조치 가능한 알림 체계를 설계한다
5. 운영에서 자주 겪는 장애를 빠르게 진단할 수 있는 관측성 표준을 만든다

---

## 한눈에 보는 구성

| 영역 | 권장 원칙 | 대표 도구 |
|------|-----------|-----------|
| Logging | stdout/stderr, JSON 구조화, correlation id | Fluent Bit, Vector, Loki, Elasticsearch |
| Metrics | RED/USE, SLI/SLO, alertable metrics | Prometheus, kube-state-metrics, node-exporter |
| Alerting | symptom-based, action-oriented, dedup | Alertmanager, Grafana Alerting |
| Visualization | 서비스별 대시보드, golden signals | Grafana |
| Tracing | 요청 단위 추적, 샘플링, baggage 최소화 | OpenTelemetry, Jaeger, Tempo |

---

## 추천 학습 순서

1. `01_observability_overview.md`
2. `02_logging_best_practices.md`
3. `03_monitoring_best_practices.md`
4. `04_alerting_best_practices.md`
5. `05_k8s_observability_best_practices.md`
6. `06_hands_on.md`

---

## 실무에서 특히 중요한 기준

- 로그는 **사람이 읽는 문장**보다 **기계가 파싱하기 쉬운 구조**가 우선
- 경보는 **원인 추정**보다 **즉시 행동 가능 여부**가 우선
- 모니터링은 **노드 상태**보다 **사용자 영향 지표**가 우선
- 대시보드는 예쁘기보다 **장애 시 30초 안에 원인 범주를 좁힐 수 있어야** 함

---

## 참고 기술 스택

- Prometheus
- Grafana
- Alertmanager
- kube-state-metrics
- node-exporter
- Fluent Bit
- Loki
- OpenTelemetry

---

## 실습 시나리오

- 애플리케이션 로그를 JSON으로 바꾸고 공통 필드를 추가
- Prometheus가 수집할 핵심 메트릭 선정
- Grafana 대시보드에서 서비스 상태를 한눈에 보기
- Alertmanager로 장애 알림을 그룹화하고 중복을 줄이기

---

## 운영 팁

- 로그 보관 정책은 메트릭보다 먼저 정한다
- 알림은 적을수록 좋지만, 놓치면 안 되는 신호는 반드시 잡는다
- 모든 대시보드에는 **서비스명 / 환경 / 시간 범위 / 담당자 링크**를 넣는다
- 장애가 났을 때 확인할 순서를 문서로 고정해 둔다
