# 06. CSI 통합 실습

## 실습 개요

이 문서에서는 Kubernetes CSI 드라이버와 관련된 핵심 실습을 단계별로 진행합니다.
각 실습은 독립적으로 수행 가능하며, 모든 YAML 예제는 `kubectl apply -f` 로 적용 가능합니다.

**실습 목록:**
1. PVC 생성 및 Pod 연결
2. StatefulSet + CSI 스토리지 연동
3. VolumeSnapshot 생성 및 복원
4. 볼륨 클론 (DataSource)
5. 볼륨 리사이즈 (Resize)
6. ReadWriteMany (RWX) 공유 볼륨
7. Raw Block Volume
8. 토폴로지 인식 프로비저닝
9. StorageClass 성능 비교
10. 스냅샷 기반 재해 복구 시뮬레이션

---

## 실습 1. PVC 생성 및 Pod 연결

### 목표
StorageClass를 이용한 동적 프로비저닝 PVC 생성 후 Pod에 마운트

### YAML

```yaml
# 01-pvc-basic.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: basic-pvc
  namespace: default
  labels:
    app: csi-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: vsphere-sc-standard  # 환경에 맞게 변경 (ebs-sc-gp3 등)
```

```yaml
# 01-pod-with-pvc.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-pvc
  namespace: default
spec:
  containers:
    - name: app
      image: busybox:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          echo "CSI Volume Test" > /data/test.txt
          cat /data/test.txt
          df -h /data
          sleep 3600
      volumeMounts:
        - name: storage
          mountPath: /data
      resources:
        requests:
          cpu: "100m"
          memory: "64Mi"
        limits:
          cpu: "200m"
          memory: "128Mi"
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: basic-pvc
  restartPolicy: Never
```

### 적용 및 확인

```bash
# 리소스 생성
kubectl apply -f 01-pvc-basic.yaml
kubectl apply -f 01-pod-with-pvc.yaml

# PVC 상태 확인 (Bound 상태가 될 때까지 대기)
kubectl get pvc basic-pvc -w

# Pod 상태 확인
kubectl get pod pod-with-pvc

# Pod 로그에서 볼륨 마운트 확인
kubectl logs pod-with-pvc

# Pod에 접속하여 직접 확인
kubectl exec -it pod-with-pvc -- df -h /data
kubectl exec -it pod-with-pvc -- ls -la /data

# 정리
kubectl delete -f 01-pod-with-pvc.yaml
kubectl delete -f 01-pvc-basic.yaml
```

---

## 실습 2. StatefulSet + CSI 스토리지 연동

### 목표
StatefulSet의 volumeClaimTemplates를 이용하여 각 Pod에 독립적인 PVC 자동 생성

### YAML

```yaml
# 02-statefulset-demo.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web-statefulset
  namespace: default
spec:
  serviceName: web-headless
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
              name: http
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
            - name: config
              mountPath: /etc/nginx/conf.d
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 10
      initContainers:
        - name: init-content
          image: busybox:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              POD_NAME=$(hostname)
              echo "<h1>Hello from ${POD_NAME}</h1>" > /data/index.html
              echo "Pod started at: $(date)" >> /data/index.html
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
        annotations:
          storageclass.kubernetes.io/description: "StatefulSet data volume"
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 2Gi
        storageClassName: vsphere-sc-standard
    - metadata:
        name: config
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
        storageClassName: vsphere-sc-standard
---
# Headless Service (StatefulSet에 필요)
apiVersion: v1
kind: Service
metadata:
  name: web-headless
  namespace: default
spec:
  clusterIP: None
  selector:
    app: web
  ports:
    - port: 80
      name: http
---
# 일반 Service (외부 접근용)
apiVersion: v1
kind: Service
metadata:
  name: web-service
  namespace: default
spec:
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
  type: ClusterIP
```

### 적용 및 확인

```bash
# StatefulSet 배포
kubectl apply -f 02-statefulset-demo.yaml

# Pod 및 PVC 목록 확인 (각 Pod에 PVC가 자동 생성됨)
kubectl get pods -l app=web
kubectl get pvc -l app=web

# 예상 출력:
# NAME              STATUS   VOLUME        CAPACITY
# data-web-0        Bound    pvc-xxxx-0    2Gi
# data-web-1        Bound    pvc-xxxx-1    2Gi
# data-web-2        Bound    pvc-xxxx-2    2Gi
# config-web-0      Bound    pvc-xxxx-3    1Gi
# ...

# 각 Pod의 데이터 확인
for i in 0 1 2; do
  echo "=== web-statefulset-$i ===" 
  kubectl exec web-statefulset-$i -- cat /usr/share/nginx/html/index.html
done

# StatefulSet 스케일 다운 후 PVC 보존 확인
kubectl scale statefulset web-statefulset --replicas=1
kubectl get pvc  # PVC는 삭제되지 않음

# 다시 스케일 업 시 동일 PVC 재연결
kubectl scale statefulset web-statefulset --replicas=3

# 정리
kubectl delete -f 02-statefulset-demo.yaml
# PVC는 수동으로 삭제 (StatefulSet 삭제 시 PVC는 보존됨)
kubectl delete pvc -l app=web
```

---

## 실습 3. VolumeSnapshot 생성 및 복원

### 사전 요구사항

```bash
# VolumeSnapshot CRD 및 snapshot-controller 설치 확인
kubectl get crd volumesnapshots.snapshot.storage.k8s.io
kubectl get pods -n kube-system | grep snapshot-controller
```

### YAML

```yaml
# 03-snapshot-demo.yaml

# 1단계: 데이터가 있는 PVC 생성
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: source-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: vsphere-sc-standard
---
# 2단계: 데이터 기록용 Pod
apiVersion: v1
kind: Pod
metadata:
  name: data-writer
  namespace: default
spec:
  containers:
    - name: writer
      image: busybox:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          echo "Important data v1.0" > /data/important.txt
          echo "Created at: $(date)" >> /data/important.txt
          echo "Data written successfully"
          sleep 7200
      volumeMounts:
        - name: storage
          mountPath: /data
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: source-pvc
---
# 3단계: VolumeSnapshotClass (드라이버에 맞게 변경)
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: demo-snapclass
driver: csi.vsphere.vmware.com   # 드라이버 이름 변경 필요
deletionPolicy: Delete
---
# 4단계: 스냅샷 생성
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: source-snapshot
  namespace: default
spec:
  volumeSnapshotClassName: demo-snapclass
  source:
    persistentVolumeClaimName: source-pvc
---
# 5단계: 스냅샷에서 새 PVC 복원
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: vsphere-sc-standard
  dataSource:
    name: source-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
---
# 6단계: 복원된 데이터 확인용 Pod
apiVersion: v1
kind: Pod
metadata:
  name: data-reader
  namespace: default
spec:
  containers:
    - name: reader
      image: busybox:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          echo "=== Restored data ===" 
          cat /data/important.txt
          ls -la /data/
          sleep 3600
      volumeMounts:
        - name: storage
          mountPath: /data
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: restored-pvc
```

### 적용 및 확인

```bash
# 순서대로 적용
kubectl apply -f 03-snapshot-demo.yaml

# 스냅샷 상태 확인 (ReadyToUse: true 대기)
kubectl get volumesnapshot source-snapshot -w

# 복원된 데이터 확인
kubectl logs data-reader

# 정리
kubectl delete -f 03-snapshot-demo.yaml
kubectl delete pvc source-pvc restored-pvc
```

---

## 실습 4. 볼륨 클론 (DataSource PVC)

### YAML

```yaml
# 04-clone-demo.yaml

# 원본 PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: original-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: vsphere-sc-standard
---
# 클론 PVC (원본 PVC를 dataSource로 지정)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cloned-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi        # 원본과 동일하거나 크게 설정
  storageClassName: vsphere-sc-standard
  dataSource:
    name: original-pvc     # 원본 PVC 이름
    kind: PersistentVolumeClaim
    # apiGroup은 PVC의 경우 생략 가능
```

### 적용 및 확인

```bash
kubectl apply -f 04-clone-demo.yaml

# PVC 상태 확인
kubectl get pvc original-pvc cloned-pvc

# 클론된 PVC가 원본과 동일한 데이터를 가졌는지 확인
kubectl run clone-check --image=busybox --rm -it --restart=Never \
  --overrides='{"spec":{"volumes":[{"name":"v","persistentVolumeClaim":{"claimName":"cloned-pvc"}}],"containers":[{"name":"c","image":"busybox","command":["ls","-la","/data"],"volumeMounts":[{"name":"v","mountPath":"/data"}]}]}}'

# 정리
kubectl delete pvc original-pvc cloned-pvc
```

---

## 실습 5. 볼륨 리사이즈 (Resize)

### YAML

```yaml
# 05-resize-demo.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: resize-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi        # 초기 크기
  storageClassName: vsphere-sc-standard  # allowVolumeExpansion: true 필요
---
apiVersion: v1
kind: Pod
metadata:
  name: resize-pod
  namespace: default
spec:
  containers:
    - name: app
      image: busybox:latest
      command: ["/bin/sh", "-c", "while true; do df -h /data; sleep 60; done"]
      volumeMounts:
        - name: storage
          mountPath: /data
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: resize-pvc
```

### 적용 및 확인

```bash
kubectl apply -f 05-resize-demo.yaml

# 현재 크기 확인
kubectl get pvc resize-pvc

# PVC 크기 확장 (5Gi → 20Gi)
kubectl patch pvc resize-pvc -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 또는 kubectl edit으로 편집
# kubectl edit pvc resize-pvc

# 확장 상태 모니터링
kubectl get pvc resize-pvc -w

# Pod 내부에서 파일시스템 크기 확인 (온라인 확장)
kubectl exec resize-pod -- df -h /data

# 정리
kubectl delete -f 05-resize-demo.yaml
kubectl delete pvc resize-pvc
```

---

## 실습 6. ReadWriteMany (RWX) 공유 볼륨

### YAML

```yaml
# 06-rwx-demo.yaml
# NFS 또는 CephFS 기반 RWX StorageClass 필요

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany          # 여러 Pod 동시 마운트
  resources:
    requests:
      storage: 10Gi
  storageClassName: trident-sc-nas   # NFS 기반 StorageClass
---
# 여러 Pod이 동시에 같은 볼륨에 쓰기
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rwx-writers
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: rwx-writer
  template:
    metadata:
      labels:
        app: rwx-writer
    spec:
      containers:
        - name: writer
          image: busybox:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              while true; do
                echo "$(hostname): $(date)" >> /shared/log.txt
                sleep 5
              done
          volumeMounts:
            - name: shared-storage
              mountPath: /shared
      volumes:
        - name: shared-storage
          persistentVolumeClaim:
            claimName: shared-pvc
---
# 공유 볼륨의 내용을 읽는 Pod
apiVersion: v1
kind: Pod
metadata:
  name: rwx-reader
  namespace: default
spec:
  containers:
    - name: reader
      image: busybox:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          while true; do
            echo "=== $(date) ==="
            tail -20 /shared/log.txt
            sleep 10
          done
      volumeMounts:
        - name: shared-storage
          mountPath: /shared
  volumes:
    - name: shared-storage
      persistentVolumeClaim:
        claimName: shared-pvc
```

### 적용 및 확인

```bash
kubectl apply -f 06-rwx-demo.yaml

# 모든 Pod이 같은 PVC를 사용하는지 확인
kubectl get pods -l app=rwx-writer
kubectl describe pvc shared-pvc  # 여러 Pod에 마운트된 것 확인

# 리더 Pod 로그에서 여러 호스트의 로그 확인
kubectl logs rwx-reader -f

# 정리
kubectl delete -f 06-rwx-demo.yaml
kubectl delete pvc shared-pvc
```

---

## 실습 7. Raw Block Volume

### YAML

```yaml
# 07-block-volume.yaml
# iSCSI, EBS, Ceph RBD 등 블록 스토리지 CSI에서 지원

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: block-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Block            # 파일시스템 없이 RAW 블록 디바이스로 노출
  resources:
    requests:
      storage: 10Gi
  storageClassName: trident-sc-san  # SAN(iSCSI) 기반 StorageClass
---
apiVersion: v1
kind: Pod
metadata:
  name: block-pod
  namespace: default
spec:
  containers:
    - name: app
      image: busybox:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          # RAW 블록 디바이스 정보 확인
          ls -la /dev/xvda
          blockdev --getsize64 /dev/xvda
          # dd로 직접 쓰기 (데이터베이스 엔진 방식)
          dd if=/dev/zero of=/dev/xvda bs=4096 count=100 2>&1
          echo "Block volume write test done"
          sleep 3600
      volumeDevices:           # volumeMounts 대신 volumeDevices 사용
        - name: block-storage
          devicePath: /dev/xvda
  volumes:
    - name: block-storage
      persistentVolumeClaim:
        claimName: block-pvc
```

---

## 실습 8. 토폴로지 인식 프로비저닝

### YAML

```yaml
# 08-topology-demo.yaml
# Zone 인식 StorageClass

apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: topology-aware-sc
provisioner: ebs.csi.aws.com   # 또는 csi.vsphere.vmware.com
volumeBindingMode: WaitForFirstConsumer  # Pod 스케줄링 이후 볼륨 생성 (Zone 결정)
allowedTopologies:
  - matchLabelExpressions:
      - key: topology.kubernetes.io/zone
        values:
          - ap-northeast-2a
          - ap-northeast-2c
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: topology-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: topology-aware-sc
---
apiVersion: v1
kind: Pod
metadata:
  name: topology-pod
  namespace: default
spec:
  # 특정 Zone에 Pod 스케줄링
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values:
                  - ap-northeast-2a
  containers:
    - name: app
      image: busybox:latest
      command: ["/bin/sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: storage
          mountPath: /data
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: topology-pvc
```

### 적용 및 확인

```bash
kubectl apply -f 08-topology-demo.yaml

# PVC가 Pod 스케줄링 후 생성되는지 확인
kubectl get pvc topology-pvc  # Pending 상태 (WaitForFirstConsumer)
kubectl get pod topology-pod  # Pod 스케줄링 후 PVC가 Bound됨

# PV의 Zone 레이블 확인
kubectl get pv -o jsonpath='{.items[*].metadata.labels}' | python3 -m json.tool

# 정리
kubectl delete -f 08-topology-demo.yaml
kubectl delete pvc topology-pvc
```

---

## 실습 9. 스냅샷 기반 재해 복구 시뮬레이션

### 시나리오
1. 데이터베이스 데이터가 있는 PVC 생성
2. 정기 스냅샷 생성 (cron 시뮬레이션)
3. 데이터 손상 시뮬레이션
4. 스냅샷에서 복원

### 스크립트

```bash
#!/bin/bash
# dr-simulation.sh

NAMESPACE="default"
PVC_NAME="db-pvc"
SC_NAME="vsphere-sc-standard"  # 환경에 맞게 변경
SNAP_CLASS="demo-snapclass"

echo "=== 재해 복구 시뮬레이션 ==="

# 1. PVC 생성
echo "1. PVC 생성..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
  storageClassName: $SC_NAME
EOF

# 2. 데이터 기록
echo "2. 데이터 기록..."
kubectl run db-init --image=busybox --rm --restart=Never \
  --overrides="{\"spec\":{\"volumes\":[{\"name\":\"v\",\"persistentVolumeClaim\":{\"claimName\":\"$PVC_NAME\"}}],\"containers\":[{\"name\":\"c\",\"image\":\"busybox\",\"command\":[\"/bin/sh\",\"-c\",\"echo 'IMPORTANT DB DATA' > /data/db.dat && echo 'version: 1.0' >> /data/db.dat\"],\"volumeMounts\":[{\"name\":\"v\",\"mountPath\":\"/data\"}]}]}}" \
  -- /bin/sh -c "echo done"

# 3. 스냅샷 생성
echo "3. 스냅샷 생성..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: db-backup-$(date +%Y%m%d%H%M%S)
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: $SNAP_CLASS
  source:
    persistentVolumeClaimName: $PVC_NAME
EOF

echo "최신 스냅샷 목록:"
kubectl get volumesnapshots -n $NAMESPACE

echo "=== 시뮬레이션 완료 ==="
```

---

## 실습 10. 멀티 StorageClass 성능 비교

### YAML

```yaml
# 10-perf-test.yaml
# 서로 다른 StorageClass의 성능을 fio로 비교

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: perf-pvc-standard
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 20Gi
  storageClassName: vsphere-sc-standard
---
apiVersion: v1
kind: Pod
metadata:
  name: fio-standard
  namespace: default
spec:
  containers:
    - name: fio
      image: nixery.dev/fio
      command: ["/bin/sh", "-c"]
      args:
        - |
          fio --name=randwrite \
              --ioengine=libaio \
              --iodepth=16 \
              --rw=randwrite \
              --bs=4k \
              --direct=1 \
              --size=1G \
              --numjobs=4 \
              --runtime=60 \
              --group_reporting \
              --filename=/data/testfile
      volumeMounts:
        - name: storage
          mountPath: /data
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: perf-pvc-standard
  restartPolicy: Never
```

### 결과 확인

```bash
kubectl apply -f 10-perf-test.yaml

# fio 테스트 결과 확인
kubectl logs fio-standard -f

# 중요 지표:
# - IOPS (read/write)
# - BW (bandwidth MiB/s)
# - lat (latency nsec/usec)

# 정리
kubectl delete -f 10-perf-test.yaml
kubectl delete pvc perf-pvc-standard
```

---

## 실습 전체 정리 스크립트

```bash
#!/bin/bash
# cleanup-all.sh

echo "모든 실습 리소스 정리..."

# Deployments, Pods
kubectl delete deployment rwx-writers --ignore-not-found
kubectl delete pod pod-with-pvc data-writer data-reader clone-check \
  resize-pod rwx-reader block-pod topology-pod fio-standard --ignore-not-found

# StatefulSet
kubectl delete statefulset web-statefulset --ignore-not-found
kubectl delete service web-headless web-service --ignore-not-found

# PVCs
kubectl delete pvc basic-pvc source-pvc restored-pvc original-pvc \
  cloned-pvc resize-pvc shared-pvc block-pvc topology-pvc \
  perf-pvc-standard db-pvc \
  data-web-0 data-web-1 data-web-2 \
  config-web-0 config-web-1 config-web-2 --ignore-not-found

# VolumeSnapshots
kubectl delete volumesnapshot --all --ignore-not-found

# StorageClasses (실습용)
kubectl delete storageclass topology-aware-sc --ignore-not-found

echo "정리 완료!"
```

---

## 참고: 자주 쓰는 디버그 명령어

```bash
# PV/PVC 전체 목록 및 상태
kubectl get pv,pvc -A

# PVC가 Pending 상태일 때 원인 분석
kubectl describe pvc <pvc-name>
kubectl get events --field-selector reason=ProvisioningFailed

# VolumeAttachment 확인 (볼륨이 노드에 연결됐는지)
kubectl get volumeattachment

# CSI 드라이버 목록
kubectl get csidriver

# 노드별 CSI 정보
kubectl get csinode

# PV의 상세 정보 (Source, AccessModes, Status)
kubectl describe pv <pv-name>

# 스냅샷 상태 확인
kubectl get volumesnapshot,volumesnapshotcontent -A

# 볼륨 관련 이벤트 모니터링
kubectl get events -w --field-selector involvedObject.kind=PersistentVolumeClaim
```
