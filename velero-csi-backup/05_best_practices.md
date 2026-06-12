# 05. Best Practice

## 1. Velero와 CSI Snapshot을 함께 쓴다

- Velero: Kubernetes 오브젝트 중심
- CSI Snapshot: 데이터 복구 중심
- 둘을 같이 써야 복구 범위가 넓어진다

---

## 2. 백업 정책과 보존 정책을 분리한다

- 짧은 보존: 빠른 롤백용
- 긴 보존: 감사/규정/재해 복구용

오래된 snapshot을 무작정 쌓아두면 스토리지 비용이 증가합니다.

---

## 3. 애플리케이션 일관성을 고려한다

특히 데이터베이스는 다음을 고려합니다.

- write flush
- replication 상태
- quiesce 가능 여부
- pre/post backup hook

---

## 4. 백업 성공보다 복구 성공을 검증한다

백업 파일이 존재하는 것만으로는 충분하지 않습니다.
정기적으로 restore 연습을 해야 합니다.

---

## 5. Secret 관리에 주의한다

- 백업에 Secret이 포함될 수 있음
- 저장소 암호화가 필요할 수 있음
- 접근 권한 최소화 필요

---

## 6. vSphere CSI 기준 주의사항

- snapshot 기능 지원 여부를 버전별로 확인
- 스토리지 정책과 datastore 여유공간을 점검
- Topology/Zone 구성 환경에서는 복원 위치를 고려

---

## 7. 라벨과 이름 규칙

백업/스냅샷 이름은 사람이 알아보기 쉽게 만듭니다.

예:
- `prod-weekly-20260613`
- `mysql-nightly-20260613`
- `finance-ns-backup`

---

## 8. 운영 표준

- 백업 주기
- 보존 주기
- 복구 테스트 주기
- 담당자
- 알림 경로

이 다섯 개를 문서로 고정해 두는 것이 좋습니다.
