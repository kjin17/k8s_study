# 02. Kubernetes 로깅 Best Practice

## 핵심 원칙

Kubernetes에서는 애플리케이션이 **파일에 직접 로그를 쓰기보다 stdout/stderr로 출력**하는 것이 기본입니다.

이유:
- 컨테이너는 짧게 살고 자주 재시작될 수 있음
- 노드 로컬 파일에 의존하면 수집이 복잡해짐
- 로그 에이전트가 표준 스트림을 수집하기 쉬움

---

## 권장 로그 구조

### 1) 구조화 로그(JSON)

```json
{
  "timestamp": "2026-06-13T02:00:00+09:00",
  "level": "info",
  "service": "payment-api",
  "namespace": "prod",
  "pod": "payment-api-7d9f7c6f9b-x2k9q",
  "trace_id": "7c9a3f...",
  "request_id": "req-12345",
  "message": "payment completed",
  "duration_ms": 143
}
```

### 2) 공통 필드
- timestamp
- level
- service
- namespace
- pod / node
- trace_id / request_id
- user_id 또는 tenant_id(민감정보 주의)

---

## 좋은 로그의 조건

- 한 줄로 파싱 가능
- 검색 키가 명확함
- 에러 원인과 요청 맥락이 함께 있음
- 민감정보가 없음

### 피해야 할 것
- 비밀번호, 토큰, 인증 헤더 전체 출력
- 멀티라인 스택트레이스를 일반 로그와 섞어 파싱 불가하게 만드는 것
- 너무 긴 debug 로그를 운영 로그에 상시 남기는 것

---

## 로그 수집 아키텍처

```text
App stdout/stderr
      ↓
Node log collector (Fluent Bit / Vector / Filebeat)
      ↓
Central store (Loki / Elasticsearch / OpenSearch)
      ↓
Search / Alert / Dashboard
```

### Kubernetes에서 흔한 구성
- **Fluent Bit**: 가볍고 널리 사용됨
- **Loki**: 로그 라벨 기반 검색에 강함
- **Elasticsearch**: 고급 검색/분석에 강함

---

## 네임스페이스/Pod 라벨링

로그 검색을 쉽게 하려면 다음 메타데이터를 붙입니다.

- cluster
- namespace
- workload
- app
- version
- pod
- node

예:
- `app=payment-api`
- `env=prod`
- `team=platform`

---

## 로그 운영 팁

1. 로그 레벨은 `info`, `warn`, `error`를 중심으로 설계한다
2. debug는 일시적으로만 켠다
3. 예상 가능한 오류는 메시지를 표준화한다
4. 에러 로그에는 반드시 **무엇이 실패했는지**와 **왜 실패했는지**를 남긴다
5. 로그 retention 정책을 먼저 정한다

---

## 보안/개인정보 주의

- Authorization 헤더 출력 금지
- 쿠키 전문 출력 금지
- 카드번호, 주민번호, 계정비밀정보 마스킹
- 필요하면 필터/마스킹 레이어를 애플리케이션과 수집기 양쪽에 둔다

---

## 추천 패턴

- 요청 시작/종료 로그를 남긴다
- trace_id로 분산 추적과 연결한다
- 에러는 가능하면 **한 번만**, 그러나 충분한 문맥과 함께 남긴다
- 운영에서 중요한 이벤트는 이벤트 로그로 별도 구분한다
