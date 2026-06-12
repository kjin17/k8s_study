# 03. Kubernetes 모니터링 Best Practice

## 목표

모니터링의 목적은 "무언가 이상하다"를 빨리 발견하고, "어디가 문제인지" 범위를 좁히는 데 있습니다.

---

## 대표 도구

- **Prometheus**: 메트릭 수집 및 질의
- **Grafana**: 시각화 및 대시보드
- **kube-state-metrics**: Kubernetes 오브젝트 상태 메트릭
- **node-exporter**: 노드 자원 메트릭
- **cAdvisor**: 컨테이너 리소스 메트릭

---

## 모니터링 레이어

### 1) 클러스터 레벨
- Node Ready / NotReady
- Disk pressure / Memory pressure
- etcd 상태
- CoreDNS 상태
- kube-apiserver 지연

### 2) 워크로드 레벨
- Pod restart
- CrashLoopBackOff
- HPA 동작
- Deployment unavailable replicas
- PVC pending

### 3) 애플리케이션 레벨
- 요청 수
- 오류율
- 지연시간
- 큐 적체
- DB 연결 수

---

## Golden Signals / RED / USE

### Golden Signals
- Latency
- Traffic
- Errors
- Saturation

### RED
- Rate
- Errors
- Duration

### USE
- Utilization
- Saturation
- Errors

운영에서는 서비스 종류에 따라 하나를 골라 일관되게 쓰는 것이 좋습니다.

---

## Prometheus 설계 원칙

- 중요한 지표만 먼저 수집
- 너무 많은 label cardinality 피하기
- scrape interval을 서비스 중요도에 맞게 조정
- recording rule로 자주 쓰는 계산을 미리 준비

### 좋은 예
- `http_requests_total{service="payment"}`
- `http_request_duration_seconds_bucket{service="payment"}`

### 나쁜 예
- `user_id` 같은 고카디널리티 label을 무분별하게 추가
- 라벨에 UUID, 이메일, 주문번호를 넣는 것

---

## 대시보드 원칙

대시보드는 예쁘게 만드는 것보다 **즉시 판단 가능**해야 합니다.

필수 요소:
- 서비스명
- 환경(prod/stage/dev)
- 핵심 SLA/SLI
- 최근 장애 지표
- 링크(로그, 트레이스, 런북)

---

## Kubernetes 특화 지표

### Node
- CPU 사용률
- 메모리 사용률
- 디스크 사용량
- 네트워크 에러

### Pod
- restart count
- OOMKilled
- pending 시간
- image pull 실패

### Control Plane
- API server latency
- scheduler queue
- controller manager sync
- etcd health

---

## 운영 팁

- 대시보드는 팀 단위보다 서비스 단위가 유용한 경우가 많다
- 경보와 대시보드는 분리하되 서로 링크를 걸어둔다
- metric만 보고 원인을 추론하지 말고, 로그와 함께 본다
- 정기적으로 "이 지표가 실제로 조치를 유도하는가"를 점검한다
