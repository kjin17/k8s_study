# 06. 실습: Logging / Monitoring / Alerting

## 실습 목표

- 애플리케이션 로그를 구조화 로그로 바꾼다
- Prometheus로 핵심 메트릭을 수집한다
- Grafana에서 대시보드를 만든다
- Alertmanager 경보 규칙을 연결한다

---

## 1) 샘플 애플리케이션 로그

```python
import json
import time

log = {
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "level": "info",
    "service": "demo-api",
    "trace_id": "abc123",
    "message": "request completed",
    "duration_ms": 123,
}
print(json.dumps(log, ensure_ascii=False))
```

---

## 2) Prometheus Rule 예시

```yaml
groups:
- name: demo-api.rules
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "demo-api error rate is high"
      description: "5xx 비율이 5%를 초과했습니다."
      runbook_url: "https://example.com/runbooks/high-error-rate"
```

---

## 3) Grafana 대시보드 체크 항목

- 요청 수(Rate)
- 5xx 비율
- p95 latency
- CPU / memory
- Pod restart count
- HPA 상태

---

## 4) Alertmanager 경보 라우팅 예시

```yaml
route:
  group_by: ["alertname", "namespace", "service"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 2h
  receiver: "slack-default"

receivers:
- name: "slack-default"
  slack_configs:
  - channel: "#ops-alerts"
    send_resolved: true
```

---

## 5) 실습 체크리스트

- [ ] 로그가 JSON으로 출력되는가
- [ ] trace_id가 로그에 포함되는가
- [ ] Prometheus가 메트릭을 수집하는가
- [ ] Grafana에서 핵심 지표가 보이는가
- [ ] Alertmanager가 알림을 받아 라우팅하는가

---

## 6) 확장 실습 아이디어

- Loki를 붙여 로그 검색까지 연결
- OpenTelemetry를 추가해 trace까지 연결
- Namespace별 대시보드 템플릿 생성
- 장애 시나리오(예: 5xx 폭증) 재현 후 알림 확인
