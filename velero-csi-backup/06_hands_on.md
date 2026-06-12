# 06. 실습: Velero + vSphere CSI Snapshot

## 실습 목표

- Velero로 Namespace와 리소스를 백업한다
- vSphere CSI Snapshot으로 PVC 데이터를 스냅샷한다
- 스냅샷으로 새 PVC를 복원한다
- restore 후 애플리케이션 정상 동작을 확인한다

---

## 1) VolumeSnapshotClass

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: vsphere-snapshot-class
driver: csi.vsphere.vmware.com
deletionPolicy: Delete
```

---

## 2) VolumeSnapshot

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: demo-snap
  namespace: prod
spec:
  volumeSnapshotClassName: vsphere-snapshot-class
  source:
    persistentVolumeClaimName: demo-pvc
```

---

## 3) 스냅샷 기반 PVC 복원

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc-restore
  namespace: prod
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: vsphere-sc-standard
  dataSource:
    name: demo-snap
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

---

## 4) Velero 백업

```bash
velero backup create prod-backup \
  --include-namespaces prod \
  --snapshot-volumes \
  --wait
```

확인:
```bash
velero backup get
velero backup describe prod-backup --details
```

---

## 5) Velero 복구

```bash
velero restore create prod-restore \
  --from-backup prod-backup \
  --wait
```

---

## 6) 검증 항목

- [ ] VolumeSnapshot이 `ReadyToUse=true` 인가
- [ ] PVC가 `Bound` 인가
- [ ] Pod가 `Running` 인가
- [ ] 로그 에러가 없는가
- [ ] 데이터가 기대값과 일치하는가

---

## 7) 확장 실습 아이디어

- DB Pod에 pre-backup hook 추가
- 주기 백업 CronJob 만들기
- 백업 실패 시 알림 연동
- 테스트 클러스터로 restore 자동화
