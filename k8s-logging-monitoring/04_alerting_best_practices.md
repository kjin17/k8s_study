# 04. Alerting Best Practice

## 경보의 목적

경보는 "눈에 띄는 알람"이 아니라, **사람이 지금 행동해야 할 신호**여야 합니다.

---

## 좋은 알림의 조건

1. 사용자가 영향을 받는다
2. 즉시 조치 가능하다
3. 중복이 적다
4. 원인 추정이 아니라 행동을 유도한다

---

## Alertmanager 기본 역할

- 알림 그룹화
- 억제(silence) / 라우팅
- 중복 제거
- 수신처 분기(Slack, Email, PagerDuty 등)

```text
Prometheus Rule
      ↓
Alertmanager
  ├── Critical → Pager / 전화
  ├── Warning  → Slack
  └── Info     → 대시보드/채널 공지
```

---

## 심각도 기준 예시

| Severity | 의미 | 예시 |
|----------|------|------|
| critical | 즉시 장애 | 서비스 전체 5xx 급증 |
| warning | 조치 필요 | 디스크 80% 이상 |
| info | 참고용 | HPA scale up |

---

## 알림 규칙 작성 팁

- 증상 기반으로 쓴다
- 원인 추정형 규칙은 피한다
- 너무 세분화하지 말고 묶을 수 있는 것끼리 묶는다
- `for:`를 적절히 사용해 순간 스파이크를 걸러낸다

### 예시
- `HTTP 5xx rate > 5% for 5m`
- `Pod restart increase > threshold for 10m`
- `Node NotReady for 5m`

---

## 알림 피로 줄이기

### 발생 원인
- 중복 알림
- 순간적인 스파이크
- 너무 낮은 임계치
- 원인 하나에 알림 여러 개

### 대응
- group_by 사용
- inhibit rules 사용
- `for:` 추가
- 동일 증상은 하나의 알림으로 통합

---

## 런북(Runbook)

알림에는 반드시 행동 가이드를 연결합니다.

예:
- 어떤 서비스가 영향받는가
- 먼저 볼 대시보드
- 확인할 로그 경로
- 롤백/재기동/스케일업 기준
- 에스컬레이션 조건

---

## 운영 기준

- Critical은 사람이 깨야 하는 알림만
- Warning은 업무 시간 내 조치 가능한 수준
- Info는 통계/추세 확인용
- 알림을 켜기 전에 끄는 기준도 미리 정한다
