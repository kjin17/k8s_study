# Kubernetes 주요 컴포넌트 & kubectl 치트시트

> 작성일: 2026-05-06  
> 대상: CKA/CKAD 준비 및 실무 참고용

---

## 📦 목차

1. [핵심 컴포넌트 개요](#핵심-컴포넌트-개요)
2. [Pod](#1-pod)
3. [Deployment](#2-deployment)
4. [ReplicaSet](#3-replicaset)
5. [Service](#4-service)
6. [ConfigMap / Secret](#5-configmap--secret)
7. [Namespace](#6-namespace)
8. [PersistentVolume / PVC](#7-persistentvolume--pvc)
9. [StatefulSet](#8-statefulset)
10. [DaemonSet](#9-daemonset)
11. [Job / CronJob](#10-job--cronjob)
12. [HPA (HorizontalPodAutoscaler)](#11-hpa)
13. [Ingress](#12-ingress)
14. [RBAC](#13-rbac)
15. [자주 쓰는 kubectl 패턴](#자주-쓰는-kubectl-패턴)

---

## 핵심 컴포넌트 개요

```
클러스터
├── Control Plane (마스터)
│   ├── kube-apiserver      ← 모든 요청의 진입점 (REST API)
│   ├── etcd                ← 클러스터 상태 저장소 (Key-Value)
│   ├── kube-scheduler      ← Pod를 어느 노드에 배치할지 결정
│   ├── kube-controller-manager ← 상태 조정 (Deployment, Node 등)
│   └── cloud-controller-manager ← 클라우드 공급자 연동
│
└── Worker Node
    ├── kubelet             ← 노드에서 Pod 실행/감시
    ├── kube-proxy          ← 네트워크 규칙 관리 (iptables/IPVS)
    └── Container Runtime   ← containerd / CRI-O
```

---

## 1. Pod

> 쿠버네티스에서 **배포 가능한 가장 작은 단위**. 1개 이상의 컨테이너 묶음.

### 특징
- 같은 Pod 내 컨테이너는 **localhost**로 통신
- **ephemeral(일시적)** — 죽으면 재생성되지 않음
- IP는 Pod마다 하나, 재생성 시 변경됨

### YAML 예시

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: default
  labels:
    app: my-app
spec:
  containers:
  - name: main
    image: nginx:latest
    ports:
    - containerPort: 80
    resources:
      requests:
        cpu: "100m"
        memory: "64Mi"
      limits:
        cpu: "500m"
        memory: "128Mi"
    env:
    - name: ENV_VAR
      value: "hello"
  restartPolicy: Always   # Always | OnFailure | Never
```

### kubectl 명령어

```bash
# 생성 / 조회
kubectl run my-pod --image=nginx                        # 즉시 실행
kubectl apply -f pod.yaml                               # YAML로 생성
kubectl get pods                                        # 목록
kubectl get pods -o wide                                # IP, 노드 포함
kubectl get pods --all-namespaces                       # 전체 NS

# 상태 확인
kubectl describe pod my-pod                             # 상세 이벤트
kubectl logs my-pod                                     # 로그
kubectl logs my-pod -c sidecar-container                # 멀티컨테이너 특정 컨테이너
kubectl logs my-pod --previous                          # 이전 컨테이너 로그

# 접속 / 실행
kubectl exec -it my-pod -- /bin/bash                    # 컨테이너 접속
kubectl exec my-pod -- env                              # 명령 실행

# 디버그
kubectl debug my-pod --image=busybox --target=main      # 디버그 컨테이너 주입
kubectl port-forward pod/my-pod 8080:80                 # 로컬 포트포워딩

# 삭제
kubectl delete pod my-pod
kubectl delete pod my-pod --grace-period=0 --force      # 강제 즉시 삭제
```

---

## 2. Deployment

> **Stateless 앱**의 표준 배포 방식. ReplicaSet을 관리하며 **롤링 업데이트** / **롤백** 지원.

### 특징
- 원하는 Pod 수 유지 (자가 치유)
- 무중단 배포 (Rolling Update)
- `maxSurge` / `maxUnavailable` 으로 배포 속도 조절

### YAML 예시

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deploy
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1           # 최대 초과 Pod 수
      maxUnavailable: 0     # 업데이트 중 최소 가용 보장
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: app
        image: nginx:1.25
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
```

### kubectl 명령어

```bash
# 생성 / 조회
kubectl create deployment my-deploy --image=nginx --replicas=3
kubectl apply -f deployment.yaml
kubectl get deployments
kubectl get deploy my-deploy -o yaml

# 스케일링
kubectl scale deployment my-deploy --replicas=5

# 업데이트
kubectl set image deployment/my-deploy app=nginx:1.26   # 이미지 변경
kubectl rollout status deployment/my-deploy             # 롤아웃 진행 확인
kubectl rollout history deployment/my-deploy            # 변경 이력
kubectl rollout history deployment/my-deploy --revision=2

# 롤백
kubectl rollout undo deployment/my-deploy               # 직전 버전으로
kubectl rollout undo deployment/my-deploy --to-revision=2

# 일시 중지 / 재개
kubectl rollout pause deployment/my-deploy
kubectl rollout resume deployment/my-deploy

# 재시작
kubectl rollout restart deployment/my-deploy
```

---

## 3. ReplicaSet

> **Pod 복제본 수**를 항상 유지. 보통 Deployment가 자동 관리하므로 직접 사용은 드묾.

```bash
kubectl get replicasets
kubectl describe rs my-deploy-7d6b9f5c4
```

---

## 4. Service

> Pod의 **안정적인 네트워크 엔드포인트**. Pod IP가 바뀌어도 Service IP(ClusterIP)는 고정.

### 타입

| 타입 | 접근 범위 | 용도 |
|------|------|------|
| `ClusterIP` | 클러스터 내부만 | 내부 서비스 간 통신 (기본값) |
| `NodePort` | 노드 IP:포트 | 외부 → 노드:30000-32767 |
| `LoadBalancer` | 외부 LB IP | 클라우드 환경 외부 노출 |
| `ExternalName` | DNS CNAME | 외부 도메인 매핑 |

### YAML 예시

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-svc
spec:
  type: ClusterIP          # ClusterIP | NodePort | LoadBalancer
  selector:
    app: my-app            # 이 레이블을 가진 Pod에 트래픽 전달
  ports:
  - protocol: TCP
    port: 80               # Service 포트
    targetPort: 8080       # Pod 컨테이너 포트
    # nodePort: 30080      # NodePort 타입일 때만 (30000-32767)
```

### kubectl 명령어

```bash
kubectl get services
kubectl get svc -o wide
kubectl describe svc my-svc
kubectl expose deployment my-deploy --port=80 --type=ClusterIP  # Deployment 노출
kubectl expose pod my-pod --port=80 --name=my-pod-svc           # Pod 직접 노출

# DNS 테스트 (클러스터 내부)
# <서비스명>.<네임스페이스>.svc.cluster.local
kubectl exec -it my-pod -- curl http://my-svc.default.svc.cluster.local
```

---

## 5. ConfigMap / Secret

> 설정값(ConfigMap)과 민감 데이터(Secret)를 코드와 분리.

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
data:
  APP_ENV: "production"
  APP_PORT: "8080"
  config.yaml: |
    log:
      level: INFO
    db:
      host: db-service
```

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
type: Opaque
data:
  DB_PASSWORD: cGFzc3dvcmQ=   # base64 인코딩 (echo -n 'password' | base64)
  API_KEY: c2VjcmV0a2V5
```

### Pod에서 사용

```yaml
# 환경변수로 주입
env:
- name: APP_ENV
  valueFrom:
    configMapKeyRef:
      name: my-config
      key: APP_ENV
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: my-secret
      key: DB_PASSWORD

# 전체를 환경변수로
envFrom:
- configMapRef:
    name: my-config
- secretRef:
    name: my-secret

# 파일로 마운트
volumes:
- name: config-vol
  configMap:
    name: my-config
containers:
- volumeMounts:
  - name: config-vol
    mountPath: /etc/config
```

### kubectl 명령어

```bash
# ConfigMap
kubectl create configmap my-config --from-literal=KEY=VALUE
kubectl create configmap my-config --from-file=config.yaml
kubectl get configmap my-config -o yaml
kubectl describe configmap my-config

# Secret
kubectl create secret generic my-secret --from-literal=PASSWORD=pass123
kubectl create secret docker-registry regcred \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass
kubectl get secrets
kubectl describe secret my-secret
echo $(kubectl get secret my-secret -o jsonpath='{.data.PASSWORD}') | base64 -d
```

---

## 6. Namespace

> 클러스터를 **논리적으로 분리**하는 가상 공간. 팀/환경/프로젝트별 격리.

```bash
# 기본 네임스페이스
# default, kube-system, kube-public, kube-node-lease

kubectl get namespaces
kubectl create namespace dev
kubectl delete namespace dev

# 네임스페이스 지정
kubectl get pods -n kube-system
kubectl get all -n dev

# 기본 네임스페이스 변경
kubectl config set-context --current --namespace=dev
kubectl config view --minify | grep namespace
```

---

## 7. PersistentVolume / PVC

> Pod가 재시작되어도 **데이터를 보존**하는 스토리지 추상화.

```
PersistentVolume (PV)   ← 관리자가 프로비저닝한 실제 스토리지
        ↕ 바인딩
PersistentVolumeClaim (PVC) ← 사용자가 요청하는 스토리지
        ↕ 마운트
Pod
```

### PVC 예시

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
  - ReadWriteOnce         # RWO | ROX(ReadOnlyMany) | RWX(ReadWriteMany)
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard
```

### Pod에서 PVC 마운트

```yaml
volumes:
- name: data-vol
  persistentVolumeClaim:
    claimName: my-pvc
containers:
- volumeMounts:
  - name: data-vol
    mountPath: /data
```

```bash
kubectl get pv
kubectl get pvc
kubectl describe pvc my-pvc
```

---

## 8. StatefulSet

> **순서 보장 + 안정적인 네트워크 ID + 영구 스토리지**가 필요한 Stateful 앱(DB 등).

### Deployment와 차이

| 항목 | Deployment | StatefulSet |
|------|------|------|
| Pod 이름 | 랜덤 suffix | `이름-0`, `이름-1` (순서 고정) |
| 스케일링 | 동시 | 순서대로 (0→1→2) |
| 스토리지 | 공유 가능 | 각 Pod마다 전용 PVC |
| DNS | 변동 | `pod-0.svc.ns.svc.cluster.local` 고정 |

```bash
kubectl get statefulsets
kubectl scale statefulset my-sts --replicas=3
kubectl rollout status statefulset/my-sts
```

---

## 9. DaemonSet

> **모든 (또는 특정) 노드**에 정확히 1개의 Pod를 배포. 로그 수집, 모니터링 에이전트 등.

```bash
kubectl get daemonsets
kubectl get daemonsets -n kube-system   # fluentd, node-exporter 등
kubectl describe daemonset my-ds
```

---

## 10. Job / CronJob

### Job — 일회성 작업

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: my-job
spec:
  completions: 1          # 성공해야 할 총 횟수
  parallelism: 1          # 동시 실행 수
  backoffLimit: 3         # 실패 시 재시도 횟수
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: worker
        image: busybox
        command: ["sh", "-c", "echo done && exit 0"]
```

### CronJob — 주기적 작업

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: my-cron
spec:
  schedule: "0 9 * * 1-5"   # cron 표현식 (평일 오전 9시)
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: job
            image: busybox
            command: ["sh", "-c", "date"]
```

```bash
kubectl get jobs
kubectl get cronjobs
kubectl logs job/my-job
kubectl create job my-job --from=cronjob/my-cron   # CronJob에서 즉시 실행
```

---

## 11. HPA

> CPU/메모리 사용률에 따라 **Pod 수를 자동으로 조절**.

```bash
# HPA 생성
kubectl autoscale deployment my-deploy \
  --cpu-percent=70 \
  --min=2 \
  --max=10

kubectl get hpa
kubectl describe hpa my-deploy
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-deploy
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

> ⚠️ HPA 동작을 위해 **metrics-server** 설치 필요

---

## 12. Ingress

> **HTTP/HTTPS 트래픽 라우팅** 규칙. 하나의 IP로 여러 서비스에 경로 기반 분기.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-svc
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
  tls:
  - hosts:
    - myapp.example.com
    secretName: tls-secret
```

```bash
kubectl get ingress
kubectl describe ingress my-ingress
```

---

## 13. RBAC

> **누가** **어떤 리소스에** **무엇을** 할 수 있는지 제어.

```
ServiceAccount / User / Group
        ↓ RoleBinding / ClusterRoleBinding
Role (네임스페이스 한정) / ClusterRole (클러스터 전체)
        ↓ rules
리소스(pods, deployments ...) × verbs(get, list, create, delete ...)
```

```bash
# 권한 확인
kubectl auth can-i create pods
kubectl auth can-i create pods --as=system:serviceaccount:default:my-sa
kubectl auth can-i '*' '*' --all-namespaces   # 관리자 확인

# Role / RoleBinding 조회
kubectl get roles,rolebindings -n default
kubectl get clusterroles,clusterrolebindings
```

---

## 자주 쓰는 kubectl 패턴

### 공통 옵션

```bash
kubectl [command] [TYPE] [NAME] [flags]

-n, --namespace=     # 네임스페이스 지정
-o yaml/json/wide    # 출력 형식
--all-namespaces     # 전체 네임스페이스
-l key=value         # 레이블 셀렉터
--field-selector     # 필드 셀렉터
--dry-run=client     # 실제 적용 없이 검증
-f                   # 파일 지정
```

### 빠른 YAML 생성 (--dry-run)

```bash
# YAML 뼈대 생성
kubectl create deployment my-deploy --image=nginx --dry-run=client -o yaml > deploy.yaml
kubectl run my-pod --image=nginx --dry-run=client -o yaml > pod.yaml
kubectl create service clusterip my-svc --tcp=80:8080 --dry-run=client -o yaml > svc.yaml
kubectl create configmap my-cm --from-literal=KEY=VAL --dry-run=client -o yaml > cm.yaml
kubectl create secret generic my-sec --from-literal=PW=pass --dry-run=client -o yaml > sec.yaml
```

### 리소스 편집 / 패치

```bash
kubectl edit deployment my-deploy                         # 에디터로 직접 수정
kubectl patch deployment my-deploy -p '{"spec":{"replicas":5}}'
kubectl label pod my-pod env=prod                         # 레이블 추가
kubectl annotate pod my-pod description="my note"         # 어노테이션 추가
```

### 상태 / 이벤트 확인

```bash
kubectl get events --sort-by=.lastTimestamp               # 이벤트 시간순
kubectl get events -n default --field-selector reason=BackOff
kubectl top nodes                                          # 노드 리소스 사용량
kubectl top pods                                           # Pod 리소스 사용량
kubectl get pods --watch                                   # 실시간 상태 모니터링
```

### 컨텍스트 / 클러스터 전환

```bash
kubectl config get-contexts                                # 컨텍스트 목록
kubectl config current-context                             # 현재 컨텍스트
kubectl config use-context my-cluster                      # 클러스터 전환
kubectl config set-context --current --namespace=dev       # 기본 NS 변경
```

### JSONPath / 커스텀 출력

```bash
# Pod IP 목록
kubectl get pods -o jsonpath='{.items[*].status.podIP}'

# 컨테이너 이미지 확인
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].image}'

# 커스텀 컬럼
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,IP:.status.podIP

# 레이블 포함 출력
kubectl get pods --show-labels
```

### 즉시 디버깅용 임시 Pod

```bash
# 일반 디버그
kubectl run debug --image=busybox --restart=Never --rm -it -- sh

# 네트워크 디버그
kubectl run debug --image=nicolaka/netshoot --restart=Never --rm -it -- bash

# 특정 노드에서 실행
kubectl run debug --image=busybox --restart=Never --rm -it \
  --overrides='{"spec":{"nodeName":"worker-1"}}' -- sh
```

---

## 빠른 참조 카드

```
오브젝트 단축어
  po   = pods
  deploy = deployments
  svc  = services
  cm   = configmaps
  ns   = namespaces
  pv   = persistentvolumes
  pvc  = persistentvolumeclaims
  sts  = statefulsets
  ds   = daemonsets
  rs   = replicasets
  ing  = ingresses
  hpa  = horizontalpodautoscalers
  sa   = serviceaccounts
  rb   = rolebindings
  crb  = clusterrolebindings
  cj   = cronjobs

자주 쓰는 조합
  kubectl get po -A -o wide          # 전체 Pod 상태 한눈에
  kubectl get all -n <ns>            # NS 내 모든 리소스
  kubectl describe po <pod> | grep -A5 Events:   # 이벤트만
  kubectl logs -f <pod> --tail=100   # 실시간 로그 100줄
  kubectl delete po <pod> --grace-period=0 --force  # 즉시 삭제
```
