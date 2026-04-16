# Kubernetes 10주 교육 커리큘럼

> 본 저장소의 교육 자료와 인터랙티브 스크립트를 기반으로 구성한
> **10주(주당 6시간 기준, 총 60시간)** 짜리 Kubernetes 실무 입문 ~ 중급 커리큘럼입니다.
> 컨테이너 기초부터 GitOps 기반 CI/CD까지, 매주 **이론 → 실습 → 과제 → 토론** 순서로 진행됩니다.

---

## 목차

- [커리큘럼 개요](#커리큘럼-개요)
- [선수 지식 및 준비물](#선수-지식-및-준비물)
- [전체 일정 한눈에 보기](#전체-일정-한눈에-보기)
- [Week 1 — 컨테이너 기초와 Git/GitHub](#week-1--컨테이너-기초와-gitgithub)
- [Week 2 — Kubernetes 아키텍처와 Master Node](#week-2--kubernetes-아키텍처와-master-node)
- [Week 3 — Worker Node와 핵심 오브젝트](#week-3--worker-node와-핵심-오브젝트)
- [Week 4 — 네트워킹 (Service, Ingress, CNI)](#week-4--네트워킹-service-ingress-cni)
- [Week 5 — 스토리지 (PV/PVC, CSI, StatefulSet)](#week-5--스토리지-pvpvc-csi-statefulset)
- [Week 6 — 보안과 RBAC](#week-6--보안과-rbac)
- [Week 7 — CRD, Operator, Cluster API](#week-7--crd-operator-cluster-api)
- [Week 8 — 프라이빗 레지스트리 (Harbor + Trivy)](#week-8--프라이빗-레지스트리-harbor--trivy)
- [Week 9 — CI 자동화 (Jenkins)](#week-9--ci-자동화-jenkins)
- [Week 10 — GitOps (ArgoCD/FluxCD) + 종합 프로젝트](#week-10--gitops-argocdfluxcd--종합-프로젝트)
- [최종 평가 기준](#최종-평가-기준)
- [추천 학습 경로 (이수 후)](#추천-학습-경로-이수-후)

---

## 커리큘럼 개요

### 학습 목표

본 과정을 마치면 학습자는 다음을 할 수 있게 됩니다:

- Kubernetes 클러스터의 **아키텍처를 이해하고 직접 구축**할 수 있다
- **Pod / Deployment / Service / Ingress** 등 핵심 오브젝트를 자유롭게 다룰 수 있다
- **PV/PVC + CSI**로 영속 스토리지를 설계하고, **StatefulSet**으로 상태 기반 앱을 배포할 수 있다
- **RBAC**으로 사용자/SA의 권한을 세밀하게 통제할 수 있다
- **CRD/Operator** 패턴을 이해하고 vSphere VKS 같은 실제 사례를 분석할 수 있다
- **Harbor + Trivy**로 사내 레지스트리와 이미지 보안을 운영할 수 있다
- **Jenkins(CI) + ArgoCD/FluxCD(CD)**로 GitOps 기반 배포 파이프라인을 구축할 수 있다

### 커리큘럼 구성 원칙

```
┌─────────────────────────────────────────────────────────────┐
│                  매 주차 학습 사이클                            │
│                                                             │
│   ① 개념 학습 (1~1.5h)   교육 자료 MD 정독                     │
│             ↓                                               │
│   ② 라이브 실습 (2~2.5h) 인터랙티브 스크립트 따라하기            │
│             ↓                                               │
│   ③ 과제 수행 (1.5~2h)  주어진 시나리오 직접 해결               │
│             ↓                                               │
│   ④ 토론/회고 (1h)      퀴즈 + 트러블슈팅 공유                  │
│                                                             │
│   주간 총 학습량: 약 6시간                                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 학습 자료 매핑

| 주차 | 교육 자료(MD) | 실습 스크립트 |
|------|---------------|----------------|
| 1주 | `container-basics.md`, `git-basics.md` | — |
| 2주 | `k8s-master-components.md` | `k8s-install.sh` |
| 3주 | `k8s-worker-components.md` | `k8s-learn.sh` (1~6) |
| 4주 | `k8s-networking.md` | `k8s-learn.sh` (4, 12), `k8s-addon.sh` |
| 5주 | `k8s-storage.md` | `k8s-learn.sh` (7, 8) |
| 6주 | `k8s-rbac.md` | `k8s-rbac.sh` |
| 7주 | `k8s-crd-clusterapi.md` | `k8s-addon.sh` (Operator) |
| 8주 | `harbor-registry.md` | `harbor-registry.sh` |
| 9주 | `k8s-cicd.md` (1~5장) | `k8s-addon.sh` (Jenkins) |
| 10주 | `k8s-cicd.md` (6~13장) | 종합 프로젝트 |

---

## 선수 지식 및 준비물

### 선수 지식

| 영역 | 수준 |
|------|------|
| Linux 기본 명령어 | 필수 (cd, ls, grep, vi 등) |
| 네트워크 기초 | 권장 (TCP/IP, HTTP, DNS) |
| YAML / JSON 문법 | 권장 |
| Git 기본 사용 | Week 1에서 학습 |
| Docker 사용 경험 | Week 1에서 학습 |
| 프로그래밍 경험 | 권장 (언어 무관) |

### 환경 준비물

```
┌─────────────────────────────────────────────────────────────┐
│              개인 학습 환경 (최소 사양)                         │
│                                                             │
│  로컬 머신:                                                  │
│  ├── CPU: 4코어 이상                                          │
│  ├── 메모리: 16GB 이상                                        │
│  ├── 디스크: 100GB 이상 여유                                   │
│  └── OS: macOS / Linux / Windows + WSL2                      │
│                                                             │
│  실습용 가상머신 3대 (또는 클라우드 VM):                        │
│  ├── 각 VM: CPU 2코어, RAM 2GB, 디스크 20GB                    │
│  ├── OS: Ubuntu 22.04 또는 Rocky Linux 9                     │
│  └── SSH 접속 가능 + sudo 권한                                 │
│                                                             │
│  필수 도구:                                                  │
│  ├── git, curl, ssh, sshpass                                 │
│  ├── kubectl 1.31+                                           │
│  ├── docker 또는 podman                                       │
│  ├── helm 3.x                                                │
│  └── (선택) Lens/k9s, openssl, jq, yq                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 클라우드 대안

물리 VM이 없는 경우 다음 옵션 활용:
- **GCP/AWS/Azure 무료 크레딧**: e2-medium 3대로 1주~2개월 사용 가능
- **로컬 KIND/Minikube**: 학습용 단일 노드 클러스터 (네트워킹/스토리지 일부 제약)
- **VMware Workstation/Fusion**: 노트북에서 VM 3대 구동

---

## 전체 일정 한눈에 보기

```
┌────────────────────────────────────────────────────────────────┐
│                      10주 커리큘럼 로드맵                        │
│                                                                │
│  [기초 다지기]                                                  │
│   Week 1  컨테이너 + Git              ← "왜 K8s 인가?"           │
│   Week 2  K8s 아키텍처 + 클러스터 설치   ← 직접 구축 시작          │
│                                                                │
│  [핵심 오브젝트]                                                │
│   Week 3  Worker Node + Pod/Deploy   ← 워크로드 배포             │
│   Week 4  네트워킹 (Svc/Ingress/CNI)  ← 서비스 노출              │
│   Week 5  스토리지 (PV/CSI/STS)       ← 영속 데이터               │
│                                                                │
│  [운영과 확장]                                                  │
│   Week 6  RBAC 보안                  ← 권한 관리                │
│   Week 7  CRD + Operator + Cluster API ← K8s 확장               │
│                                                                │
│  [DevOps 통합]                                                  │
│   Week 8  Harbor 레지스트리          ← 이미지 관리                │
│   Week 9  Jenkins CI                 ← 빌드 자동화               │
│   Week 10 ArgoCD/FluxCD GitOps       ← 종합 프로젝트             │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

| 주차 | 주제 | 핵심 산출물 |
|------|------|-------------|
| 1 | 컨테이너 기초 + Git/GitHub | 첫 Dockerfile + GitHub PR |
| 2 | K8s 아키텍처 + 클러스터 설치 | 1 Master + 2 Worker 클러스터 |
| 3 | Worker Node + Pod/Deployment | 3-tier 앱(Frontend/Backend/Cache) 배포 |
| 4 | 네트워킹 (Service, Ingress) | 도메인 기반 라우팅 구현 |
| 5 | 스토리지 (PV/PVC, StatefulSet) | MySQL StatefulSet + 백업 |
| 6 | RBAC 보안 | 팀별 권한 분리 + ServiceAccount |
| 7 | CRD + Operator + Cluster API | 첫 Operator 배포 (Prometheus 등) |
| 8 | Harbor + Trivy | 사내 레지스트리 + 이미지 스캔 |
| 9 | Jenkins CI | Jenkinsfile 기반 자동 빌드 |
| 10 | GitOps + 최종 프로젝트 | Jenkins + ArgoCD 통합 파이프라인 |

---

## Week 1 — 컨테이너 기초와 Git/GitHub

### 학습 목표

- 컨테이너의 **본질(namespace + cgroup)** 을 이해한다
- Docker로 **이미지를 만들고 실행**할 수 있다
- Git의 **3-Stage 모델(Working/Staging/Repository)** 을 이해한다
- GitHub로 **Pull Request 워크플로우**를 경험한다

### 학습 자료

- 📘 [`container-basics.md`](container-basics.md) — 전체
- 📘 [`git-basics.md`](git-basics.md) — 전체

### 라이브 실습

```bash
# 실습 1: 첫 컨테이너 실행
docker run -d -p 8080:80 --name web nginx
curl http://localhost:8080
docker exec -it web bash
docker logs web
docker stop web && docker rm web

# 실습 2: 첫 이미지 빌드
mkdir myapp && cd myapp
cat > index.html <<EOF
<h1>Hello from my container!</h1>
EOF
cat > Dockerfile <<EOF
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
EOF
docker build -t myapp:v1 .
docker run -d -p 8080:80 myapp:v1

# 실습 3: Git 워크플로우
git init
git add . && git commit -m "feat: initial commit"
git remote add origin https://github.com/<user>/myapp.git
git push -u origin main
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | Python Flask "Hello World" 앱을 작성하고 Dockerfile 작성 → DockerHub에 push |
| **과제 2** | 본인 이름의 GitHub 저장소 생성 → 새 브랜치 → PR 생성 → 본인이 PR 리뷰/머지 |
| **과제 3** | `.gitignore`, `README.md`, `Dockerfile` 3개 파일을 PR 1개로 통합 등록 |

### 토론 주제

- 컨테이너와 가상머신의 차이는 무엇이며 왜 컨테이너가 빠른가?
- 컨테이너 이미지의 레이어 구조가 빌드/배포 효율에 어떻게 기여하는가?
- Git의 분산 버전 관리가 SVN 같은 중앙형과 어떻게 다른가?

### 체크리스트

- [ ] `docker run` / `docker build` / `docker push`를 활용할 수 있다
- [ ] Dockerfile의 `FROM`, `COPY`, `RUN`, `CMD`, `EXPOSE`를 설명할 수 있다
- [ ] `git add` → `git commit` → `git push`의 의미를 안다
- [ ] PR(Pull Request)을 생성하고 머지할 수 있다

---

## Week 2 — Kubernetes 아키텍처와 Master Node

### 학습 목표

- Kubernetes의 **선언적(Declarative) 모델**을 이해한다
- **Master(Control Plane) 5대 컴포넌트**의 역할과 상호작용을 설명할 수 있다
- 직접 **1 Master + 2 Worker 클러스터를 구축**한다
- `kubectl`의 기본 명령어를 익힌다

### 학습 자료

- 📘 [`k8s-master-components.md`](k8s-master-components.md) — 전체
- (참고) [`k8s-install.sh`](k8s-install.sh) — 스크립트 내부 설치 흐름 분석

### 라이브 실습

```bash
# 실습 1: 클러스터 자동 설치
chmod +x k8s-install.sh
./k8s-install.sh
# → 인터랙티브 입력으로 1 Master + 2 Worker 구축
# → CNI는 Antrea 또는 Calico 선택

# 실습 2: 클러스터 상태 검증
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl cluster-info
kubectl version

# 실습 3: Control Plane 컴포넌트 직접 확인
ssh <master-ip>
ls /etc/kubernetes/manifests/      # Static Pod manifests
sudo crictl ps | grep -E 'apiserver|etcd|scheduler|controller'
sudo journalctl -u kubelet -n 100
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | etcd에 직접 접근하여 `/registry/pods/default` 키 조회 (`etcdctl` 사용) |
| **과제 2** | API Server를 1분간 재시작하고 그 동안 클러스터 동작 변화 관찰/기록 |
| **과제 3** | kube-scheduler가 Pod를 노드에 배치하는 과정을 `--v=4` 로그로 추적 |

### 토론 주제

- API Server가 클러스터의 "유일한 Single Source of Truth"인 이유는?
- etcd가 죽으면 왜 클러스터가 즉시 멈추지 않을까? (kubelet의 동작)
- Scheduler와 Controller Manager의 책임이 어떻게 분리되는가?

### 체크리스트

- [ ] kube-apiserver / etcd / scheduler / controller-manager / cloud-controller-manager의 역할을 안다
- [ ] kubeadm으로 클러스터를 생성하고 노드를 join할 수 있다
- [ ] kubectl context와 kubeconfig 구조를 이해한다
- [ ] `kubectl describe`로 객체 상태를 분석할 수 있다

---

## Week 3 — Worker Node와 핵심 오브젝트

### 학습 목표

- **kubelet, kube-proxy, container runtime(containerd)** 의 역할을 이해한다
- **Pod의 생명주기**와 재시작 정책, Probe(Liveness/Readiness)를 설명할 수 있다
- **Deployment의 롤링 업데이트와 롤백**을 활용할 수 있다
- `crictl`로 워커 노드에서 직접 트러블슈팅한다

### 학습 자료

- 📘 [`k8s-worker-components.md`](k8s-worker-components.md) — 전체

### 라이브 실습

```bash
# 실습 1: 인터랙티브 학습 스크립트 (1~6번 메뉴)
./k8s-learn.sh
# → Namespace → Pod → Deployment → Service → ConfigMap → Secret 순으로 학습

# 실습 2: Worker Node에서 직접 트러블슈팅
ssh <worker-ip>
sudo crictl ps                            # 컨테이너 목록
sudo crictl logs <container-id>           # 컨테이너 로그
sudo crictl pods                          # Pod 목록
sudo crictl inspect <container-id>        # 컨테이너 상세
sudo systemctl status kubelet
sudo journalctl -u kubelet -f

# 실습 3: 롤링 업데이트 + 롤백
kubectl create deployment nginx --image=nginx:1.24 --replicas=3
kubectl set image deployment/nginx nginx=nginx:1.25
kubectl rollout status deployment/nginx
kubectl rollout history deployment/nginx
kubectl rollout undo deployment/nginx

# 실습 4: Probe 시나리오
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: probe-demo
spec:
  containers:
  - name: app
    image: nginx
    livenessProbe:
      httpGet: {path: /, port: 80}
      initialDelaySeconds: 5
      periodSeconds: 5
    readinessProbe:
      tcpSocket: {port: 80}
      initialDelaySeconds: 3
EOF
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | 3-tier 애플리케이션(Frontend Nginx + Backend Node.js + Redis Cache) 을 Deployment 3개로 배포 |
| **과제 2** | Liveness Probe가 실패하도록 일부러 잘못 설정 → 재시작 횟수 관찰 → 분석 보고 |
| **과제 3** | ConfigMap을 환경변수로 + Secret을 볼륨 마운트로 같은 Pod에 사용해보기 |

### 토론 주제

- kubelet이 죽으면 그 노드의 Pod는 어떻게 되는가?
- containerd와 Docker의 관계는? CRI는 왜 도입되었나?
- Liveness vs Readiness Probe의 차이가 트래픽 라우팅에 어떤 영향을 주는가?

### 체크리스트

- [ ] kubelet, kube-proxy, container runtime의 역할을 설명할 수 있다
- [ ] Pod의 5가지 상태(Pending/Running/Succeeded/Failed/Unknown)를 안다
- [ ] crictl로 컨테이너 로그/상태를 확인할 수 있다
- [ ] Deployment 롤백을 실행할 수 있다

---

## Week 4 — 네트워킹 (Service, Ingress, CNI)

### 학습 목표

- **Pod 네트워크 모델(평면 IP)** 을 이해한다
- **Service 4가지 타입(ClusterIP/NodePort/LoadBalancer/ExternalName)** 을 구분한다
- **kube-proxy**의 iptables/IPVS 모드 동작을 안다
- **Ingress Controller** 로 도메인 기반 HTTP 라우팅을 구현한다
- **CNI(Antrea/Calico/Cilium)** 의 역할과 차이를 설명한다

### 학습 자료

- 📘 [`k8s-networking.md`](k8s-networking.md) — 전체

### 라이브 실습

```bash
# 실습 1: Service 타입별 동작 비교 (k8s-learn.sh 4번 메뉴)
./k8s-learn.sh
# ClusterIP → NodePort → LoadBalancer 순으로 생성하며 차이 관찰

# 실습 2: Ingress Controller 설치
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  --set controller.service.type=NodePort

# 실습 3: 호스트/경로 기반 라우팅
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-host
spec:
  ingressClassName: nginx
  rules:
  - host: api.example.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: {service: {name: api, port: {number: 80}}}
  - host: web.example.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: {service: {name: web, port: {number: 80}}}
EOF

# 실습 4: CoreDNS 동작 관찰
kubectl run dnsutils --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 --rm -it -- bash
# 안에서:
nslookup kubernetes.default
nslookup my-svc.my-namespace.svc.cluster.local
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | NetworkPolicy로 dev 네임스페이스의 Pod가 prod 네임스페이스에 접근하지 못하도록 차단 |
| **과제 2** | LoadBalancer 타입 Service를 MetalLB로 구현 (베어메탈 환경) |
| **과제 3** | TLS 인증서를 Secret으로 등록 → Ingress에 HTTPS 적용 (cert-manager 활용 가능) |

### 토론 주제

- ClusterIP가 실제 인터페이스에는 존재하지 않는데 어떻게 통신이 되는가?
- Pod IP가 사라지는데 Service가 어떻게 안정적인 연결점을 제공하는가?
- Ingress vs LoadBalancer Service의 비용·복잡도 트레이드오프?

### 체크리스트

- [ ] CNI가 무엇이고 왜 필요한지 설명할 수 있다
- [ ] kube-proxy의 iptables/IPVS 모드 차이를 안다
- [ ] CoreDNS의 service discovery 동작 원리를 안다
- [ ] Ingress와 NodePort/LoadBalancer의 차이를 비교할 수 있다

---

## Week 5 — 스토리지 (PV/PVC, CSI, StatefulSet)

### 학습 목표

- **PV/PVC의 분리**가 왜 필요한지 설명할 수 있다
- **StorageClass + Dynamic Provisioning**으로 자동 PV 생성을 구현한다
- **CSI Driver 아키텍처**를 이해하고 vSphere CSI를 활용한다
- **StatefulSet**으로 안정적 ID와 영속 스토리지가 필요한 워크로드를 배포한다

### 학습 자료

- 📘 [`k8s-storage.md`](k8s-storage.md) — 전체

### 라이브 실습

```bash
# 실습 1: 정적 PV/PVC (k8s-learn.sh 7번 메뉴)
./k8s-learn.sh

# 실습 2: StorageClass + Dynamic Provisioning
kubectl get storageclass
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: <default-sc>
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pv,pvc

# 실습 3: StatefulSet — MySQL Master/Replica
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless
  replicas: 3
  selector:
    matchLabels: {app: mysql}
  template:
    metadata:
      labels: {app: mysql}
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env: [{name: MYSQL_ROOT_PASSWORD, value: changeme}]
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:
  - metadata: {name: data}
    spec:
      accessModes: [ReadWriteOnce]
      resources: {requests: {storage: 5Gi}}
EOF

# 실습 4: vSphere CSI 활용 (vSphere 환경 시)
kubectl get csidriver
kubectl get pods -n vmware-system-csi
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | StatefulSet으로 PostgreSQL을 배포하고 Pod 삭제 후 재생성 시 데이터가 유지됨을 검증 |
| **과제 2** | VolumeSnapshot CRD로 PVC 스냅샷 생성 → 새 PVC로 복원 |
| **과제 3** | Storage Quota를 ResourceQuota로 적용 → 제한 초과 시 PVC 생성 실패 확인 |

### 토론 주제

- PV의 ReclaimPolicy(Retain/Delete/Recycle) 선택 기준은?
- StatefulSet과 Deployment의 근본적 차이는 무엇이고 언제 어떤 것을 쓰는가?
- CSI가 등장하기 전 In-Tree 드라이버의 문제점은?

### 체크리스트

- [ ] PV/PVC/StorageClass의 3단계 추상화를 그림으로 그릴 수 있다
- [ ] AccessMode(RWO/ROX/RWX/RWOP)를 구분할 수 있다
- [ ] StatefulSet의 안정적 ID(`pod-0`, `pod-1`)와 Headless Service의 관계를 안다
- [ ] CSI Driver의 Provisioner/Attacher/NodePlugin 역할을 안다

---

## Week 6 — 보안과 RBAC

### 학습 목표

- **인증(Authentication)과 인가(Authorization)** 의 차이를 안다
- **RBAC 4대 리소스(Role/ClusterRole/RoleBinding/ClusterRoleBinding)** 를 자유롭게 작성한다
- **ServiceAccount**로 Pod 워크로드의 권한을 분리한다
- **X.509 / OIDC** 사용자 인증 흐름을 이해하고 직접 사용자를 만들어본다

### 학습 자료

- 📘 [`k8s-rbac.md`](k8s-rbac.md) — 전체

### 라이브 실습

```bash
# 실습 1: 인터랙티브 RBAC 스크립트 (1~10번 메뉴 모두)
./k8s-rbac.sh
# → SA 생성 → Role/Binding → 권한 테스트 → X.509 사용자 생성 → Forbidden 시나리오

# 실습 2: alice 사용자 만들기 + dev NS view 권한
# (스크립트 메뉴 8번으로 자동화 가능)

# 실습 3: 권한 영향 범위 검증
kubectl auth can-i --list -n dev --as=alice
kubectl auth can-i create deployments -n prod --as=alice  # no
kubectl auth can-i create deployments -n dev --as=alice   # yes
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | 가상의 회사 시나리오: dev팀(dev/test NS edit), ops팀(전체 view), security팀(audit 전용)의 RBAC 설계서 + 적용 |
| **과제 2** | Jenkins SA가 `ci` NS에서만 동작하고 `prod` NS는 read-only인 RoleBinding 작성 |
| **과제 3** | Forbidden 에러 메시지를 분석하여 정확한 권한만 추가하는 워크플로우 문서화 |

### 토론 주제

- `system:masters` 그룹이 왜 위험한가? cluster-admin과 어떻게 다른가?
- ServiceAccount Token이 K8s 1.24부터 어떻게 변경되었고 왜 변경되었나?
- ClusterRole + RoleBinding 패턴이 같은 권한을 여러 Role로 만드는 것보다 좋은 이유는?

### 체크리스트

- [ ] kubectl auth can-i / whoami / impersonation을 활용할 수 있다
- [ ] Role/ClusterRole/RoleBinding/ClusterRoleBinding 4가지 조합을 그릴 수 있다
- [ ] X.509 CSR로 사용자를 만들고 kubeconfig를 발급할 수 있다
- [ ] Pod에 ServiceAccount를 할당하고 token을 검증할 수 있다

---

## Week 7 — CRD, Operator, Cluster API

### 학습 목표

- **CRD(Custom Resource Definition)** 의 동작 원리를 이해한다
- **Operator 패턴**(Watch + Reconcile)을 이해하고 기존 Operator를 활용한다
- **Cluster API**가 클러스터 자체를 CRD로 관리하는 방식을 학습한다
- **VKS(VCF 9.0)** 같은 실무 사례를 분석할 수 있다

### 학습 자료

- 📘 [`k8s-crd-clusterapi.md`](k8s-crd-clusterapi.md) — 전체

### 라이브 실습

```bash
# 실습 1: 첫 CRD 만들어보기
kubectl apply -f - <<EOF
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.demo.example.com
spec:
  group: demo.example.com
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              schedule: {type: string}
              storage: {type: string}
EOF

# CR 인스턴스 생성
kubectl apply -f - <<EOF
apiVersion: demo.example.com/v1
kind: Backup
metadata:
  name: nightly
spec:
  schedule: "0 2 * * *"
  storage: s3://my-backup
EOF

kubectl get backups
kubectl explain backup.spec

# 실습 2: 기존 Operator 활용 (Prometheus Operator)
./k8s-addon.sh
# → 메뉴에서 "Prometheus + Grafana" 선택

# kube-prometheus-stack 설치 후 Operator가 만든 CRD 확인
kubectl get crd | grep monitoring.coreos.com

# Operator의 Reconcile 로그 관찰
kubectl logs -n monitoring -l app.kubernetes.io/name=kube-prometheus-stack-operator -f

# 실습 3: Cluster API 컨셉 이해 (실제 배포는 선택)
# - vSphere 환경이면 VKS의 Cluster CRD 직접 조회 가능
kubectl get crd | grep cluster.x-k8s.io
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | 본인이 정의한 CRD(예: `WebApp`) 스키마 작성 + validation 규칙 추가 |
| **과제 2** | Cert-Manager Operator를 설치하고 CRD(`Issuer`, `Certificate`) 동작 분석 |
| **과제 3** | Operator vs Helm Chart의 차이점을 5가지 비교 표로 정리 |

### 토론 주제

- 일반 Controller와 Operator의 차이는?
- CRD가 Kubernetes API를 확장하는 것이 왜 강력한가?
- Cluster API가 멀티 클러스터 관리에 어떤 가치를 주는가?

### 체크리스트

- [ ] CRD의 group/version/kind/scope를 이해한다
- [ ] Operator가 Reconcile loop로 동작함을 안다
- [ ] kubectl로 CRD 인스턴스를 생성하고 status를 관찰할 수 있다
- [ ] Cluster API의 Management/Workload Cluster 개념을 안다

---

## Week 8 — 프라이빗 레지스트리 (Harbor + Trivy)

### 학습 목표

- **컨테이너 레지스트리**의 필요성과 Harbor의 역할을 안다
- Harbor에 **이미지를 push/pull**할 수 있다
- **Trivy로 이미지 취약점 스캔**을 수행하고 결과를 해석한다
- **imagePullSecret**으로 K8s에서 사설 레지스트리를 사용한다

### 학습 자료

- 📘 [`harbor-registry.md`](harbor-registry.md) — 전체

### 라이브 실습

```bash
# 실습 1: 인터랙티브 Harbor 설치 + 실습 스크립트
chmod +x harbor-registry.sh
./harbor-registry.sh
# → 메뉴 1: Harbor 설치
# → 메뉴 2: Project 생성
# → 메뉴 3: Docker push/pull
# → 메뉴 4: Trivy 스캔
# → 메뉴 5: Helm Chart push
# → 메뉴 6: 보안 정책 (자동 스캔, 차단)

# 실습 2: K8s에서 사설 레지스트리 사용
kubectl create secret docker-registry harbor-cred \
  --docker-server=harbor.example.com \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  -n default

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: from-harbor
spec:
  imagePullSecrets:
  - name: harbor-cred
  containers:
  - name: app
    image: harbor.example.com/myproject/myapp:v1
EOF

# 실습 3: Trivy CLI 직접 사용
trivy image nginx:1.24
trivy image --severity HIGH,CRITICAL nginx:1.24
trivy image --format json nginx:1.24 > scan.json
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | Week 1 과제의 Flask 앱 이미지를 Harbor에 push → CVE 1개 이상 발견 → Dockerfile 개선 후 재스캔 |
| **과제 2** | Harbor의 Webhook을 Slack/Discord에 연동 → push 이벤트 알림 |
| **과제 3** | Robot Account를 만들어 CI 도구용 토큰 발급 + 권한 최소화 검증 |

### 토론 주제

- DockerHub 같은 퍼블릭 레지스트리만 쓸 때의 보안/속도/비용 문제는?
- Image Signing(Cosign/Notary)은 왜 필요한가?
- Trivy의 SBOM(Software Bill of Materials) 이 공급망 보안에 어떻게 기여하는가?

### 체크리스트

- [ ] Harbor의 Project / Robot Account / Webhook을 활용할 수 있다
- [ ] docker tag → push → pull의 전체 흐름을 안다
- [ ] imagePullSecret을 K8s에서 사용할 수 있다
- [ ] Trivy로 CVE를 식별하고 우선순위를 정할 수 있다

---

## Week 9 — CI 자동화 (Jenkins)

### 학습 목표

- **CI와 CD의 차이**를 명확히 구분한다
- **Jenkins Master/Agent** 구조를 이해하고 K8s 기반 동적 Agent를 활용한다
- **Jenkinsfile (Declarative Pipeline)** 을 작성한다
- 빌드 → 테스트 → 이미지 push → 배포 전 단계를 자동화한다

### 학습 자료

- 📘 [`k8s-cicd.md`](k8s-cicd.md) — **1~5장**

### 라이브 실습

```bash
# 실습 1: Jenkins 설치 (Helm + kubernetes plugin)
helm repo add jenkins https://charts.jenkins.io
helm install jenkins jenkins/jenkins -n jenkins --create-namespace \
  --set controller.serviceType=NodePort \
  --set controller.adminUser=admin \
  --set controller.adminPassword=admin1234 \
  --set agent.enabled=true

# 실습 2: 첫 Jenkinsfile (App Repo)
cat > Jenkinsfile <<'EOF'
pipeline {
    agent {
        kubernetes {
            yaml '''
              apiVersion: v1
              kind: Pod
              spec:
                containers:
                - name: docker
                  image: docker:24-dind
                  securityContext: {privileged: true}
            '''
        }
    }
    stages {
        stage('Checkout') { steps { checkout scm } }
        stage('Build') {
            steps {
                container('docker') {
                    sh 'docker build -t harbor.example.com/myproject/myapp:${BUILD_NUMBER} .'
                }
            }
        }
        stage('Push') {
            steps {
                container('docker') {
                    withCredentials([usernamePassword(credentialsId: 'harbor', usernameVariable: 'U', passwordVariable: 'P')]) {
                        sh 'docker login harbor.example.com -u $U -p $P'
                        sh 'docker push harbor.example.com/myproject/myapp:${BUILD_NUMBER}'
                    }
                }
            }
        }
    }
}
EOF

# 실습 3: GitHub Webhook → Jenkins 자동 트리거
# Jenkins UI: Multibranch Pipeline → GitHub URL 입력 → 토큰 등록
# GitHub: Settings → Webhooks → Add webhook → http://<jenkins-ip>/github-webhook/
```

### 과제

| 과제 | 산출물 |
|------|--------|
| **과제 1** | Week 1 Flask 앱 저장소에 Jenkinsfile 추가 → push → 자동 빌드 + Harbor push 검증 |
| **과제 2** | 단위 테스트 단계 추가 → 실패 시 빌드 실패 처리 |
| **과제 3** | Slack 통보 단계 추가 (성공/실패 시 메시지) |

### 토론 주제

- Push 방식 CI/CD(Jenkins)가 멀티 클러스터 환경에서 어떤 문제를 가지는가?
- Pipeline as Code의 장점은? Job UI 클릭 방식과 비교하면?
- Jenkins Agent를 K8s Pod로 만드는 것의 자원/격리 측면 이점은?

### 체크리스트

- [ ] Declarative vs Scripted Pipeline의 차이를 안다
- [ ] Jenkinsfile에 stages, steps, environment, post를 작성할 수 있다
- [ ] Credentials Plugin으로 비밀 정보를 안전하게 사용할 수 있다
- [ ] GitHub Webhook 트리거를 설정할 수 있다

---

## Week 10 — GitOps (ArgoCD/FluxCD) + 종합 프로젝트

### 학습 목표

- **GitOps 4대 원칙**을 이해하고 Push 방식과의 차이를 명확히 안다
- **ArgoCD**로 Git 저장소를 클러스터에 동기화한다
- **FluxCD**의 GitOps Toolkit을 활용한다
- Jenkins(CI) + ArgoCD(CD) **하이브리드 파이프라인**을 종합 프로젝트로 구축한다

### 학습 자료

- 📘 [`k8s-cicd.md`](k8s-cicd.md) — **6~13장**

### 라이브 실습

```bash
# 실습 1: ArgoCD 설치
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30443}]}}'

# 초기 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# 실습 2: 첫 ArgoCD Application
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated: {prune: true, selfHeal: true}
    syncOptions: [CreateNamespace=true]
EOF

# 실습 3: FluxCD 부트스트랩
brew install fluxcd/tap/flux   # macOS
flux check --pre
export GITHUB_TOKEN=ghp_xxx
flux bootstrap github \
  --owner=<user> --repository=fleet-infra \
  --branch=main --path=./clusters/lab --personal
```

### 종합 프로젝트 — Final Capstone

```
┌─────────────────────────────────────────────────────────────┐
│              종합 프로젝트: GitOps 파이프라인 구축              │
│                                                             │
│  요구사항:                                                   │
│  ├── GitHub: App Repo + Manifest Repo 분리                  │
│  ├── Jenkins(CI): 빌드 + Trivy 스캔 + Harbor push +          │
│  │                Manifest Repo 업데이트(image tag commit)    │
│  ├── ArgoCD(CD): Manifest Repo watch → 자동 sync             │
│  ├── 환경 분리: dev / stage 두 NS로 ApplicationSet 구성        │
│  └── RBAC: 개발자는 dev NS만 접근, ArgoCD는 dev+stage 둘 다   │
│                                                             │
│  산출물:                                                     │
│  ① 두 GitHub 저장소 (코드 commit + manifest commit 이력)      │
│  ② Jenkins 빌드 로그 (성공한 BUILD_NUMBER 3개 이상)           │
│  ③ ArgoCD UI 스크린샷 (Synced/Healthy 상태)                  │
│  ④ Harbor의 image 목록 (tag별로 3개 이상)                     │
│  ⑤ git revert로 롤백 데모 영상 또는 스크린샷                   │
│  ⑥ 5분 발표 자료(슬라이드 10장 이내)                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 토론 주제

- ArgoCD vs FluxCD: 본인 회사/팀에는 어떤 것이 더 적합한가? 왜?
- App Repo와 Manifest Repo를 분리하는 이유와 단일 저장소(monorepo) 전략의 trade-off?
- Jenkins(CI) + ArgoCD(CD) 분리 패턴이 단일 도구(GitLab Auto DevOps 등)보다 좋은 점/나쁜 점?

### 체크리스트

- [ ] GitOps 4대 원칙을 설명할 수 있다
- [ ] Application CRD의 source/destination/syncPolicy를 작성할 수 있다
- [ ] flux bootstrap으로 새 클러스터에 GitOps를 시작할 수 있다
- [ ] git revert로 운영 롤백을 시연할 수 있다

---

## 최종 평가 기준

```
┌─────────────────────────────────────────────────────────────┐
│                      이수 평가 (100점)                        │
│                                                             │
│  주차별 과제 (50점)                                          │
│   ├── 매주 3개 과제 × 10주 = 30개 과제                        │
│   └── 각 과제 평균 1.66점 (제출 + 동작 + 문서화)               │
│                                                             │
│  주차별 체크리스트 (20점)                                     │
│   └── 학습 목표 달성 여부 자가 평가 + 동료 검증                 │
│                                                             │
│  종합 프로젝트 (30점)                                        │
│   ├── 기능 완성도        — 15점                               │
│   ├── 문서/발표 품질      — 10점                               │
│   └── 코드/매니페스트 품질  —  5점                              │
│                                                             │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│  이수 기준: 70점 이상                                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 평가 등급

| 등급 | 점수 | 설명 |
|------|------|------|
| A+ | 95~100 | 모든 영역 우수, 종합 프로젝트 창의적 |
| A | 90~94 | 모든 영역 충실 |
| B+ | 85~89 | 대부분의 과제 완수 |
| B | 80~84 | 핵심 학습 목표 달성 |
| C+ | 75~79 | 일부 과제 미흡 |
| C | 70~74 | 최소 이수 기준 |
| F | 70 미만 | 재이수 권고 |

---

## 추천 학습 경로 (이수 후)

```
┌─────────────────────────────────────────────────────────────┐
│              본 과정 이수 후 추천 학습 경로                       │
│                                                             │
│  ━━ 운영/SRE 트랙 ━━                                          │
│  ├── Observability  : Prometheus + Grafana + Loki 심화        │
│  ├── 멀티 클러스터    : Cluster API 직접 운영                    │
│  ├── Service Mesh   : Istio / Linkerd                         │
│  ├── 인증/보안       : OIDC + Dex, OPA Gatekeeper / Kyverno    │
│  └── 자격증          : CKA (Certified K8s Administrator)        │
│                                                             │
│  ━━ 개발/플랫폼 트랙 ━━                                       │
│  ├── Operator 개발  : Operator SDK / Kubebuilder              │
│  ├── 점진적 배포     : Argo Rollouts / Flagger (Canary, B/G)    │
│  ├── K8s API 활용    : client-go / controller-runtime         │
│  ├── 개발자 포털     : Backstage                                │
│  └── 자격증          : CKAD (Certified K8s App Developer)       │
│                                                             │
│  ━━ 보안 트랙 ━━                                              │
│  ├── 정책 엔진       : Kyverno / OPA Gatekeeper 심화           │
│  ├── 런타임 보안     : Falco / Tetragon                        │
│  ├── 공급망 보안     : Cosign, SBOM, SLSA                      │
│  ├── Secret 관리     : HashiCorp Vault + CSI Secret Store      │
│  └── 자격증          : CKS (Certified K8s Security Specialist)  │
│                                                             │
│  ━━ 인프라 트랙 ━━                                             │
│  ├── IaC 통합        : Terraform + Crossplane                  │
│  ├── 베어메탈/엣지    : K3s, MicroK8s, Talos Linux              │
│  ├── 가상화 통합     : KubeVirt (VM on K8s)                    │
│  └── 데이터 플랫폼    : Strimzi (Kafka), CloudNativePG           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 자격증 시험 준비

| 자격증 | 적합한 트랙 | 권장 추가 학습 시간 |
|--------|-------------|-----------------------|
| **CKA** (Administrator) | 운영/SRE | 4~6주 |
| **CKAD** (App Developer) | 개발/플랫폼 | 3~4주 |
| **CKS** (Security) | 보안 | 6~8주 (CKA 선행 필수) |
| **KCNA** (Associate) | 입문 통합 | 2~3주 |

### 커뮤니티 / 실무 자료

- [Kubernetes 공식 문서](https://kubernetes.io/docs/)
- [CNCF Landscape](https://landscape.cncf.io)
- [Kubernetes Slack](https://kubernetes.slack.com)
- [한국 쿠버네티스 사용자 그룹 (KCD Korea)](https://www.kubernetes.kr)
- [Killer.sh](https://killer.sh) — CKA/CKAD/CKS 모의시험

---

> **마지막 한마디**:
> Kubernetes는 **혼자 책으로 배우기보다 동료와 함께 부수면서 배우는** 기술입니다.
> 매주 토론 시간을 통해 본인이 마주친 에러와 해결 과정을 공유하세요.
> 가장 빠른 성장은 **본인의 실패를 남에게 설명하는 순간**에 일어납니다. 화이팅!
