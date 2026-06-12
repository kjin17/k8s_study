# Kubernetes Backup & Restore: Velero + vSphere CSI Snapshot

> Kubernetes에서 **백업/복구 전략**을 설계할 때 가장 많이 쓰는 조합인 **Velero**와 **CSI 스냅샷**을 함께 다룹니다.
>
> 특히 스토리지는 **vSphere CSI** 중심으로 설명하여, vSphere 환경에서 실무적으로 어떻게 백업과 복구를 구성하는지 익히는 것을 목표로 합니다.

---

## 📚 목차

| 파일 | 내용 |
|------|------|
| `01_backup_strategy_overview.md` | 백업/복구 전략 개요, Velero와 CSI 스냅샷의 역할 분리 |
| `02_velero_backup_restore.md` | Velero 설치, 백업/복구, Namespace/리소스/볼륨 백업 |
| `03_csi_snapshot_vsphere.md` | vSphere CSI 스냅샷 원리, VolumeSnapshot, SnapshotClass |
| `04_restore_scenarios.md` | 장애 시나리오별 복구 흐름 (앱/네임스페이스/PVC/PV) |
| `05_best_practices.md` | 운영 Best Practice, 주의사항, 성능/보존 정책 |
| `06_hands_on.md` | 실습: Velero 백업 + vSphere CSI 스냅샷 + 복구 검증 |

---

## 🎯 학습 목표

1. Velero가 무엇을 백업하고 무엇은 직접 백업하지 않는지 이해한다
2. CSI 스냅샷이 PV 레벨에서 어떤 역할을 하는지 이해한다
3. vSphere CSI를 기준으로 VolumeSnapshot, VolumeSnapshotClass를 구성한다
4. 애플리케이션 백업, 스토리지 백업, 복구 절차를 함께 설계한다
5. 실무에서 백업 실패 원인과 복구 검증 포인트를 파악한다

---

## 한눈에 보는 역할 분담

| 항목 | Velero | CSI Snapshot |
|------|--------|--------------|
| Kubernetes 리소스 백업 | ✅ | ❌ |
| Namespace 전체 백업 | ✅ | ❌ |
| PVC/PV 데이터 백업 | ✅(플러그인/노드 에이전트 활용) | ✅ |
| 스토리지 레벨 스냅샷 | ❌ | ✅ |
| 다른 클러스터로 복구 | ✅ | 제한적 |
| 빠른 롤백 | 부분적 | ✅ |

---

## 추천 학습 순서

1. `01_backup_strategy_overview.md`
2. `02_velero_backup_restore.md`
3. `03_csi_snapshot_vsphere.md`
4. `04_restore_scenarios.md`
5. `05_best_practices.md`
6. `06_hands_on.md`

---

## 기본 원칙

- **Velero**는 Kubernetes 오브젝트 백업과 복구의 중심
- **CSI Snapshot**은 스토리지 레벨의 빠른 포인트인타임 복구 수단
- **vSphere CSI**는 vSphere 환경에서 스냅샷/복구를 가장 자연스럽게 연결할 수 있는 기준 스토리지 드라이버
- 데이터가 중요한 서비스는 **리소스 백업 + 볼륨 백업 + 복구 검증**을 함께 설계해야 함

---

## 참고 기술 스택

- Velero
- vSphere CSI Driver
- VolumeSnapshot / VolumeSnapshotClass
- snapshot-controller
- Object Storage (S3 호환)
- Restic / Node Agent

---

## 운영 체크 포인트

- 백업은 성공보다 **복구 성공**이 중요
- 스냅샷은 빠르지만 만능이 아님
- 앱 일관성이 필요한 경우 pre/post hook 또는 quiesce 전략을 고려
- 백업 보존 주기와 용량 증가는 반드시 같이 관리
