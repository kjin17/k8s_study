# 04. 복구 시나리오

## 시나리오 1. 애플리케이션 리소스만 삭제됨

### 상황
- Deployment, Service, ConfigMap이 삭제됨
- PVC/PV 데이터는 살아 있음

### 복구
- Velero로 리소스 복구
- 동일 Namespace에 재적용

---

## 시나리오 2. PVC 데이터가 손상됨

### 상황
- MySQL 데이터 디렉터리가 깨짐
- 애플리케이션은 실행되지만 데이터가 손상됨

### 복구
- 최신 CSI Snapshot으로 새 PVC 생성
- 복구 PVC를 새 Pod에 마운트해 검증
- 필요 시 기존 PVC 교체

---

## 시나리오 3. 네임스페이스 전체 장애

### 상황
- 잘못된 배포로 Namespace 전체를 삭제

### 복구
- Velero로 Namespace 전체 restore
- 관련 PVC가 snapshot 기반으로 복구되었는지 확인

---

## 시나리오 4. 클러스터 마이그레이션

### 상황
- 기존 클러스터를 유지보수로 내리고 새 클러스터로 이전

### 복구
- Velero 백업을 새 클러스터에 restore
- 필요한 PV는 CSI snapshot 또는 파일 백업과 함께 복원

---

## 복구 순서 권장

1. Namespace / RBAC / ConfigMap / Secret 복원
2. Service / Ingress / Deployment 복원
3. PVC 복원
4. Pod readiness 확인
5. 애플리케이션 데이터 검증

---

## 복구 검증 체크리스트

- Pod가 Running 인가
- PVC가 Bound 인가
- 애플리케이션 로그 에러가 없는가
- 데이터 개수가 기대치와 맞는가
- 외부 접근이 정상인가

---

## 운영 팁

복구는 "되돌리는 것"이 아니라 **비즈니스가 다시 정상 동작하는지 증명하는 과정**입니다.
따라서 restore 후에는 반드시 기능 검증까지 포함해야 합니다.
