# 02. Velero 백업과 복구

## Velero란?

Velero는 Kubernetes 클러스터의 **리소스 백업과 복구**를 위한 오픈소스 도구입니다.

주요 기능:
- Namespace 단위 백업
- 특정 리소스 백업
- 클러스터 마이그레이션
- PV 데이터 연동 백업
- 복구 시 리소스 재생성

---

## Velero 구성 요소

- **velero server**: 백업/복구 오케스트레이션
- **plugin**: 클라우드/스토리지 연동
- **backup storage location**: 백업 저장 위치(S3 호환)
- **volume snapshot location**: 스토리지 스냅샷 저장 위치

---

## 설치 개요

Velero는 보통 다음과 같이 설치합니다.

```bash
velero install \
  --provider aws \
  --bucket velero-backup \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=true \
  --backup-location-config region=minio \
  --snapshot-location-config region=minio
```

> vSphere 환경에서는 Velero 자체는 오브젝트 스토리지와 연동하고, 볼륨 스냅샷은 CSI Snapshot 경로를 같이 활용하는 방식이 일반적입니다.

---

## 백업 대상 지정

### Namespace 전체 백업

```bash
velero backup create prod-backup \
  --include-namespaces prod \
  --snapshot-volumes \
  --wait
```

### 특정 리소스만 백업

```bash
velero backup create app-backup \
  --include-namespaces prod \
  --include-resources deployments,services,configmaps,secrets,pvc \
  --wait
```

### 레이블 기반 백업

```bash
velero backup create team-backup \
  --selector team=platform \
  --wait
```

---

## 백업 결과 확인

```bash
velero backup get
velero backup describe prod-backup --details
velero backup logs prod-backup
```

체크 포인트:
- 상태가 `Completed` 인가
- 어떤 리소스가 포함되었는가
- PV snapshot이 생성되었는가
- 경고나 누락 리소스가 있는가

---

## 복구

### 전체 복구

```bash
velero restore create --from-backup prod-backup --wait
```

### 일부 리소스만 복구

```bash
velero restore create partial-restore \
  --from-backup prod-backup \
  --include-resources deployments,services,configmaps \
  --wait
```

---

## 복구 시 주의점

- 같은 이름의 리소스가 이미 존재하면 충돌 가능
- Namespace 자체를 먼저 생성해야 하는 경우가 있음
- Secret / ConfigMap에 의존하는 앱은 순서에 민감
- 복구 후 readiness/liveness 상태까지 확인해야 함

---

## Velero의 한계

- 데이터베이스 일관성은 보장하지 않음
- 스토리지 엔진별 quiesce가 없으면 crash-consistent 수준일 수 있음
- 외부 시스템 연동 정보는 백업 범위 밖일 수 있음

---

## 권장 운영 방식

- Velero로 리소스 복구 기반을 만든다
- 중요한 데이터는 CSI Snapshot을 같이 사용한다
- 백업 성공 여부보다 복구 성공 여부를 더 자주 검증한다
