# Kubernetes CI/CD 교육 — Jenkins, ArgoCD, FluxCD

> 현대 소프트웨어 개발의 핵심인 **CI/CD(Continuous Integration / Continuous Delivery)**의 개념과,
> 가장 널리 사용되는 세 가지 도구인 **Jenkins**, **ArgoCD**, **FluxCD**를 다룹니다.
> 전통적인 Push 방식의 CI/CD와 Kubernetes 시대의 표준이 된 **GitOps(Pull 방식)** 패러다임을 비교 학습하며,
> 실제 Kubernetes 환경에서 어떻게 적용하는지 실습 예시까지 함께 살펴봅니다.

---

## 목차

1. [CI/CD 개요](#1-cicd-개요)
2. [CI와 CD의 차이](#2-ci와-cd의-차이)
3. [전통적 CI/CD (Push) vs GitOps (Pull)](#3-전통적-cicd-push-vs-gitops-pull)
4. [Jenkins 개요](#4-jenkins-개요)
5. [Jenkins Pipeline 실습](#5-jenkins-pipeline-실습)
6. [GitOps 개요](#6-gitops-개요)
7. [ArgoCD 개요](#7-argocd-개요)
8. [ArgoCD 실습](#8-argocd-실습)
9. [FluxCD 개요](#9-fluxcd-개요)
10. [FluxCD 실습](#10-fluxcd-실습)
11. [ArgoCD vs FluxCD 비교](#11-argocd-vs-fluxcd-비교)
12. [통합 시나리오 — Jenkins + ArgoCD](#12-통합-시나리오--jenkins--argocd)
13. [정리 및 핵심 요약](#13-정리-및-핵심-요약)

---

## 1. CI/CD 개요

### 한 문장 정의

> **CI/CD**는 코드 변경부터 운영 환경 배포까지의 과정을 **자동화**하여,
> 개발자가 작성한 코드를 **빠르고**, **안전하게**, **반복 가능하게** 사용자에게 전달하는 일련의 관행입니다.

### 왜 CI/CD가 필요한가?

```
┌─────────────────────────────────────────────────────────────┐
│              CI/CD 없이 배포한다면?                           │
│                                                             │
│  개발자 A: 내 PC에서는 잘 됐는데...                            │
│  개발자 B: 내가 머지한 코드랑 충돌이 나네                       │
│  운영자  : 어제 배포한 거 어떻게 롤백하지?                      │
│  QA     : 어떤 버전을 테스트한 건지 모르겠어                    │
│                                                             │
│  → 빌드 실패 발견이 늦음                                       │
│  → 머지 충돌이 누적되어 통합 비용 폭증                          │
│  → 사람의 실수로 인한 운영 사고                                │
│  → 추적 불가능한 변경 이력                                     │
│                                                             │
│  ─────────────────────────────────────────────               │
│                                                             │
│  CI/CD 도입 후:                                               │
│                                                             │
│  ✅ 매 커밋마다 자동 빌드/테스트 (조기 결함 발견)              │
│  ✅ 머지 전 자동 검증 (안정적인 통합)                           │
│  ✅ 클릭 한 번 또는 자동으로 배포 (빠른 릴리스)                 │
│  ✅ Git 이력 = 모든 변경의 단일 진실 공급원                     │
│  ✅ 실패 시 자동 롤백 / 빠른 복구                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### CI/CD의 효과 (DORA Metrics)

DevOps 성숙도를 측정하는 **DORA(DevOps Research and Assessment) 4대 지표**:

| 지표 | 의미 | Elite Performer |
|------|------|------------------|
| **Deployment Frequency** | 얼마나 자주 배포하는가 | 하루에 여러 번 |
| **Lead Time for Changes** | 커밋부터 배포까지 시간 | 1시간 이내 |
| **Change Failure Rate** | 배포 실패 비율 | 0–15% |
| **MTTR (Mean Time to Recover)** | 장애 복구까지 시간 | 1시간 이내 |

> CI/CD는 위 4가지 지표를 모두 개선하는 **근간 기술**입니다.

---

## 2. CI와 CD의 차이

```
┌─────────────────────────────────────────────────────────────┐
│            CI / CD 파이프라인 전체 흐름                         │
│                                                             │
│   [개발자 PC] ─push─→ [Git Repo]                              │
│                          │                                  │
│           ┌──────────────┴──────────────┐                   │
│           │                             │                   │
│           ▼ CI (Continuous Integration) │                   │
│   ┌───────────────────┐                  │                  │
│   │ 1. 소스 체크아웃    │                  │                  │
│   │ 2. 빌드 (compile) │                  │                  │
│   │ 3. 단위 테스트     │                  │                  │
│   │ 4. 정적 분석       │                  │                  │
│   │ 5. 컨테이너 이미지 │                  │                  │
│   │    빌드 + Push    │                  │                  │
│   └─────────┬─────────┘                  │                  │
│             │                            │                  │
│             ▼ CD (Continuous Delivery)   │                  │
│   ┌───────────────────┐                  │                  │
│   │ 6. Dev 자동 배포  │                  │                  │
│   │ 7. 통합 테스트    │                  │                  │
│   │ 8. Stage 배포     │                  │                  │
│   │ 9. 승인 대기      │ ← (Delivery)     │                  │
│   │10. Prod 배포      │ ← (Deployment)   │                  │
│   └───────────────────┘                  │                  │
│                                          │                  │
└─────────────────────────────────────────────────────────────┘
```

### CI (Continuous Integration) — 지속적 통합

| 항목 | 내용 |
|------|------|
| **목적** | 모든 개발자의 코드를 자주(하루에도 여러 번) 통합하여 충돌과 버그를 조기에 발견 |
| **트리거** | Git push, Pull Request 생성 |
| **수행 작업** | 빌드 → 테스트 → 정적 분석 → 컨테이너 이미지 빌드 |
| **결과물** | 검증된 컨테이너 이미지 (예: `myapp:v1.2.3`) → 레지스트리에 push |

### CD (Continuous Delivery / Deployment) — 지속적 배포

```
┌─────────────────────────────────────────────────────────────┐
│        Continuous Delivery vs Continuous Deployment         │
│                                                             │
│  Continuous Delivery (지속적 전달):                            │
│   ├── 자동으로 Stage 환경까지 배포                             │
│   ├── Prod 배포는 사람의 승인(클릭) 필요                        │
│   └── "언제든 배포 가능한 상태"를 유지                          │
│                                                             │
│  Continuous Deployment (지속적 배포):                          │
│   ├── 검증을 통과하면 Prod까지 자동 배포                        │
│   ├── 사람의 개입 없음                                         │
│   └── 진정한 의미의 자동화                                     │
│                                                             │
│   둘 다 약자 "CD" → 문맥으로 구분                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 전통적 CI/CD (Push) vs GitOps (Pull)

Kubernetes 시대에는 배포 방식이 크게 두 가지로 나뉩니다.

```
┌─────────────────────────────────────────────────────────────┐
│           Push vs Pull 방식 비교                              │
│                                                             │
│  ━━ Push 방식 (Jenkins, GitLab CI 등 전통적 CI/CD) ━━        │
│                                                             │
│   [Jenkins] ──kubectl apply──→ [K8s Cluster]                │
│       │                                                     │
│       └── CI/CD 도구가 클러스터에 직접 변경 적용                │
│                                                             │
│   특징:                                                      │
│   ├── 외부 도구가 클러스터 자격증명을 보유 (보안 위험)          │
│   ├── 클러스터 상태 = Git 상태가 아닐 수 있음 (Drift)          │
│   └── 멀티 클러스터 관리 시 자격증명/네트워크 복잡              │
│                                                             │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                             │
│  ━━ Pull 방식 (ArgoCD, FluxCD — GitOps) ━━                  │
│                                                             │
│   [Git Repo (소스 of Truth)]                                 │
│           ▲                                                 │
│           │ watch                                           │
│   [ArgoCD/Flux 컨트롤러] (클러스터 내부 실행)                  │
│           │                                                 │
│           └─→ 클러스터에 변경 적용                             │
│                                                             │
│   특징:                                                      │
│   ├── 컨트롤러가 클러스터 내부에서 Git을 Pull                   │
│   ├── Git = 단일 진실 공급원 (선언적)                          │
│   ├── 자동 Drift 감지 및 복원                                  │
│   ├── 외부에 자격증명 노출 불필요                              │
│   └── 멀티 클러스터 GitOps 가능                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 비교표

| 항목 | Push (Jenkins) | Pull (ArgoCD/Flux) |
|------|----------------|---------------------|
| 변경 적용 주체 | 외부 CI 도구 | 클러스터 내 컨트롤러 |
| 자격증명 위치 | 외부(Jenkins) | 내부(K8s Service Account) |
| Drift 감지 | 없음 | 자동 감지 + 복원 |
| 다중 클러스터 | 자격증명 모두 보유 필요 | 각 클러스터에 컨트롤러 배포 |
| 롤백 | Jenkins 재실행 | `git revert` |
| 감사(Audit) | Jenkins 로그 | Git 커밋 이력 |
| 적합한 단계 | **CI**(빌드/테스트) | **CD**(배포/동기화) |

> **현대 모범 사례**: Jenkins(또는 GitHub Actions)로 **CI**를 수행하고,
> ArgoCD/FluxCD로 **CD**(GitOps)를 수행하는 **하이브리드 방식**이 일반적입니다.

---

## 4. Jenkins 개요

### 한 문장 정의

> **Jenkins**는 자바 기반의 **오픈소스 자동화 서버**로,
> 빌드·테스트·배포 등 거의 모든 개발 워크플로우를 **플러그인**으로 확장할 수 있는 가장 오래되고 널리 쓰이는 CI/CD 도구입니다.

### 왜 Jenkins인가?

```
┌─────────────────────────────────────────────────────────────┐
│                Jenkins의 강점                                 │
│                                                             │
│  ✅ 거대한 생태계: 1,800+ 플러그인                             │
│     (Git, Docker, K8s, Slack, JIRA, AWS, vSphere 등)         │
│                                                             │
│  ✅ Pipeline as Code: Jenkinsfile로 파이프라인을              │
│     코드로 관리 (Groovy DSL)                                  │
│                                                             │
│  ✅ 분산 빌드: Master + Agent 구조로 수평 확장 가능             │
│                                                             │
│  ✅ 어디서나 동작: VM, 베어메탈, K8s 등 환경 무관               │
│                                                             │
│  ✅ Self-hosted: 완전한 제어, 데이터 주권                       │
│                                                             │
│  단점:                                                        │
│  ❌ 운영 부담: 마스터/플러그인 업데이트, 보안 패치              │
│  ❌ 복잡한 UI/UX                                              │
│  ❌ 정적 자원: K8s 네이티브 도구 대비 동적 확장 약함            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Jenkins 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                 Jenkins Master + Agent                      │
│                                                             │
│   ┌────────────────────────┐                                │
│   │   Jenkins Controller   │  (Master)                      │
│   │   (구 Master)           │                                │
│   │                        │                                │
│   │  ├── Job 정의 / 스케줄  │                                │
│   │  ├── 사용자 / 권한      │                                │
│   │  ├── UI / API           │                                │
│   │  └── 빌드 결과 저장      │                                │
│   └───────────┬────────────┘                                │
│               │ 작업 분배 (JNLP / SSH)                       │
│       ┌───────┼───────┬───────┐                              │
│       ▼       ▼       ▼       ▼                              │
│   ┌──────┐┌──────┐┌──────┐┌──────┐                          │
│   │Agent ││Agent ││Agent ││Agent │                          │
│   │Linux ││Linux ││MacOS ││K8s   │                          │
│   │      ││      ││      ││Pod   │                          │
│   └──────┘└──────┘└──────┘└──────┘                          │
│                                  ↑                          │
│              (kubernetes plugin로 Pod를 동적으로 생성)        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Jenkins on Kubernetes

K8s 환경에서는 **kubernetes plugin** 을 사용하여 Agent를 **Pod로 동적 생성**합니다.

| 장점 | 설명 |
|------|------|
| 자원 효율 | 빌드가 시작될 때만 Pod 생성, 종료 시 삭제 |
| 격리성 | 각 빌드가 독립된 Pod에서 실행 |
| 확장성 | 빌드 큐가 늘면 Pod도 자동으로 늘어남 |
| 멀티 환경 | 빌드별로 다른 이미지(Java, Python, Node 등) 사용 가능 |

---

## 5. Jenkins Pipeline 실습

### Helm으로 Jenkins 설치

```bash
# Helm 저장소 추가
helm repo add jenkins https://charts.jenkins.io
helm repo update

# 네임스페이스 생성
kubectl create namespace jenkins

# values.yaml 작성
cat > jenkins-values.yaml <<EOF
controller:
  adminUser: "admin"
  adminPassword: "admin1234"
  serviceType: NodePort
  nodePort: 32000
  installPlugins:
    - kubernetes:latest
    - workflow-aggregator:latest
    - git:latest
    - configuration-as-code:latest
    - blueocean:latest
    - docker-workflow:latest
persistence:
  enabled: true
  size: 8Gi
agent:
  enabled: true
EOF

# 설치
helm install jenkins jenkins/jenkins \
  -n jenkins \
  -f jenkins-values.yaml

# 접속
echo "URL: http://<NodeIP>:32000"
echo "ID: admin / PW: admin1234"
```

### Jenkinsfile (Declarative Pipeline)

`Jenkinsfile`을 Git 저장소 루트에 두면 Jenkins가 이 파일을 읽어 파이프라인을 실행합니다.

```groovy
// Jenkinsfile — 컨테이너 이미지 빌드 + Harbor Push + K8s 배포
pipeline {
    // K8s Pod를 Agent로 사용
    agent {
        kubernetes {
            yaml '''
              apiVersion: v1
              kind: Pod
              spec:
                containers:
                - name: docker
                  image: docker:24-dind
                  securityContext:
                    privileged: true
                - name: kubectl
                  image: bitnami/kubectl:1.31
                  command: ['cat']
                  tty: true
            '''
        }
    }

    environment {
        REGISTRY = "harbor.example.com"
        IMAGE    = "myproject/myapp"
        TAG      = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Unit Test') {
            steps {
                container('docker') {
                    sh 'docker run --rm -v $PWD:/app -w /app node:20 npm test'
                }
            }
        }

        stage('Build & Push Image') {
            steps {
                container('docker') {
                    withCredentials([usernamePassword(
                        credentialsId: 'harbor-cred',
                        usernameVariable: 'USER',
                        passwordVariable: 'PASS')]) {
                        sh """
                          docker login ${REGISTRY} -u $USER -p $PASS
                          docker build -t ${REGISTRY}/${IMAGE}:${TAG} .
                          docker push ${REGISTRY}/${IMAGE}:${TAG}
                        """
                    }
                }
            }
        }

        stage('Deploy to Dev') {
            steps {
                container('kubectl') {
                    sh """
                      kubectl set image deployment/myapp \
                        myapp=${REGISTRY}/${IMAGE}:${TAG} \
                        -n dev
                      kubectl rollout status deployment/myapp -n dev
                    """
                }
            }
        }

        stage('Approval for Prod') {
            steps {
                input message: 'Deploy to Production?', ok: 'Deploy'
            }
        }

        stage('Deploy to Prod') {
            steps {
                container('kubectl') {
                    sh """
                      kubectl set image deployment/myapp \
                        myapp=${REGISTRY}/${IMAGE}:${TAG} \
                        -n prod
                      kubectl rollout status deployment/myapp -n prod
                    """
                }
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline succeeded: ${REGISTRY}/${IMAGE}:${TAG}"
        }
        failure {
            echo "❌ Pipeline failed"
        }
    }
}
```

### Pipeline 단계별 의미

```
┌─────────────────────────────────────────────────────────────┐
│           Jenkins Pipeline Stage Flow                       │
│                                                             │
│  [Git Push]                                                 │
│       │                                                     │
│       ▼                                                     │
│  Webhook → Jenkins                                          │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────────────────────┐                    │
│  │ Stage 1: Checkout                   │ ─ git clone        │
│  ├─────────────────────────────────────┤                    │
│  │ Stage 2: Unit Test                  │ ─ npm test         │
│  ├─────────────────────────────────────┤                    │
│  │ Stage 3: Build & Push Image         │ ─ docker build/push│
│  ├─────────────────────────────────────┤                    │
│  │ Stage 4: Deploy to Dev              │ ─ kubectl set image│
│  ├─────────────────────────────────────┤                    │
│  │ Stage 5: Approval (사람 개입)        │ ─ Wait for click   │
│  ├─────────────────────────────────────┤                    │
│  │ Stage 6: Deploy to Prod             │ ─ kubectl set image│
│  └─────────────────────────────────────┘                    │
│       │                                                     │
│       ▼                                                     │
│  Slack/Email 알림                                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Jenkins의 한계 — 왜 GitOps가 필요한가?

위 파이프라인은 잘 동작하지만, 다음과 같은 문제가 있습니다:

```
❌ kubectl set image 의 결과가 Git에 반영되지 않음
   → 클러스터 상태와 Git 상태가 불일치 (Drift)
   → "지금 운영에 떠 있는 게 정확히 어떤 버전인가?" 추적 어려움

❌ Jenkins가 클러스터 자격증명을 보유
   → 멀티 클러스터 시 자격증명 관리 복잡
   → Jenkins가 침해당하면 클러스터 전체 위험

❌ 누가 직접 kubectl edit으로 변경하면?
   → Jenkins는 알 수 없음
   → 다음 배포 시 덮어써지거나 충돌

✅ 해결책: GitOps (ArgoCD / FluxCD)
```

---

## 6. GitOps 개요

### 한 문장 정의

> **GitOps**는 Kubernetes 클러스터의 **모든 상태(Desired State)를 Git 저장소에 선언적으로 정의**하고,
> 클러스터 내부의 컨트롤러가 **Git을 지속적으로 동기화(Reconcile)**하여 실제 상태를 일치시키는 운영 패러다임입니다.

### GitOps 4대 원칙 (CNCF 정의)

```
┌─────────────────────────────────────────────────────────────┐
│              GitOps Principles                              │
│                                                             │
│  1. Declarative (선언적)                                     │
│     시스템의 원하는 상태를 선언적으로 표현                       │
│     → YAML, Helm, Kustomize                                  │
│                                                             │
│  2. Versioned and Immutable (버전 관리 + 불변)               │
│     원하는 상태는 Git에 저장 → 모든 변경이 추적됨              │
│                                                             │
│  3. Pulled Automatically (자동으로 Pull)                     │
│     소프트웨어 에이전트가 자동으로 원하는 상태를 가져옴          │
│                                                             │
│  4. Continuously Reconciled (지속적 동기화)                   │
│     실제 상태가 원하는 상태와 다르면 자동으로 일치시킴           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### GitOps 워크플로우

```
┌─────────────────────────────────────────────────────────────┐
│              GitOps End-to-End Flow                         │
│                                                             │
│   [개발자]                                                   │
│      │ 1. 코드 변경                                          │
│      ▼                                                      │
│   [App Repo: src/]                                          │
│      │ 2. push                                              │
│      ▼                                                      │
│   [CI: Jenkins / GitHub Actions]                            │
│      │ 3. 빌드 + 이미지 push                                 │
│      ▼                                                      │
│   [Container Registry: Harbor]                              │
│      │ 4. 이미지 태그 업데이트                                │
│      ▼                                                      │
│   [Manifest Repo: deploy/]                                  │
│      │   (image: myapp:v1.2.3 으로 변경 + git push)          │
│      │                                                      │
│      │ 5. ArgoCD/Flux가 변경 감지                            │
│      ▼                                                      │
│   [ArgoCD/Flux Controller (in K8s)]                         │
│      │ 6. kubectl apply (자동)                               │
│      ▼                                                      │
│   [Kubernetes Cluster]                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 저장소 분리 패턴 — App Repo vs Manifest Repo

```
[App Repo]                   [Manifest Repo]
src/                          k8s/
├── Dockerfile                ├── deployment.yaml
├── code/                     ├── service.yaml
└── Jenkinsfile (CI만)        └── kustomization.yaml
                              (or Helm chart)

→ App Repo  : 개발자 작업 (코드)
→ Manifest Repo: 운영 작업 (배포 정의)
→ ArgoCD/Flux는 Manifest Repo만 watch
```

> **장점**: 코드 변경과 배포 변경의 이력이 분리되어 감사가 쉬움.
> 단일 저장소(Mono-repo) 방식도 가능하지만, 이력이 섞이는 단점이 있습니다.

---

## 7. ArgoCD 개요

### 한 문장 정의

> **ArgoCD**는 **Argo Project(CNCF Graduated)**가 만든 **Kubernetes 전용 GitOps CD 도구**로,
> Git 저장소의 매니페스트를 클러스터에 동기화하고 **시각적인 UI**를 통해 애플리케이션 상태를 관리합니다.

### ArgoCD 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    ArgoCD Architecture                      │
│                                                             │
│   [Web UI / CLI / API]                                      │
│           │                                                 │
│           ▼                                                 │
│   ┌─────────────────────┐                                   │
│   │  argocd-server       │  ── REST/gRPC API + UI           │
│   └──────────┬──────────┘                                   │
│              │                                              │
│   ┌──────────┴──────────┐                                   │
│   │ argocd-repo-server  │  ── Git Pull, Manifest 생성       │
│   │  (Helm/Kustomize)   │                                   │
│   └──────────┬──────────┘                                   │
│              │                                              │
│   ┌──────────┴────────────┐                                 │
│   │ argocd-application-   │  ── 동기화 컨트롤러                │
│   │ controller            │     (kubectl apply / 비교)        │
│   └──────────┬────────────┘                                 │
│              │                                              │
│              ▼                                              │
│   ┌─────────────────────┐                                   │
│   │  Kubernetes API     │                                   │
│   └─────────────────────┘                                   │
│                                                             │
│   추가 컴포넌트:                                              │
│   ├── argocd-dex-server  (SSO/OIDC)                          │
│   ├── argocd-redis       (캐시)                              │
│   └── argocd-notifications-controller (Slack/Email)          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### ArgoCD 핵심 개념

| 개념 | 설명 |
|------|------|
| **Application** | 배포 단위. Git 저장소 경로 + 대상 클러스터/네임스페이스를 정의한 CRD |
| **Project** | Application들을 그룹화하는 논리 단위. 권한/저장소/배포 대상 제한 |
| **Sync** | Git의 매니페스트를 클러스터에 적용 (Manual / Auto) |
| **Sync Wave** | 리소스 적용 순서 제어 (CRD → Deployment → Ingress 순서 등) |
| **Health Status** | Deployment Ready, Pod Running 등 상태 평가 |
| **Sync Status** | Synced(일치) / OutOfSync(불일치) |
| **App of Apps** | 하나의 Application이 다른 Application 여러 개를 관리하는 패턴 |
| **ApplicationSet** | 여러 클러스터/환경에 같은 앱을 자동 배포하는 CRD |

### Application의 동작 원리

```
┌─────────────────────────────────────────────────────────────┐
│       ArgoCD Application Reconciliation Loop                │
│                                                             │
│  1. Repository Server: Git pull → Manifest 렌더링            │
│         (Helm template, Kustomize build 등)                 │
│              │                                              │
│              ▼                                              │
│  2. Application Controller: Live State 조회                  │
│         (kubectl get all -n <namespace>)                    │
│              │                                              │
│              ▼                                              │
│  3. Diff: Desired vs Live 비교                               │
│              │                                              │
│              ▼                                              │
│  4. Sync 결정:                                               │
│     ├── Manual: UI에서 "Sync" 버튼 클릭 대기                  │
│     ├── Auto: 자동으로 kubectl apply                          │
│     └── Self-Heal: 누가 직접 수정해도 Git 상태로 복원           │
│              │                                              │
│              ▼                                              │
│  5. Health Check: Pod Ready, Endpoints 등 평가               │
│              │                                              │
│              ▼                                              │
│  6. 결과를 Application status에 반영 → UI/Webhook 알림       │
│                                                             │
│  주기: 기본 3분마다 (또는 webhook 트리거 시 즉시)             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. ArgoCD 실습

### 설치

```bash
# 네임스페이스 생성
kubectl create namespace argocd

# ArgoCD 설치 (공식 매니페스트)
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 또는 Helm으로 설치
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd

# 모든 Pod가 Running이 될 때까지 대기
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s
```

### 접속

```bash
# Service 타입을 NodePort로 변경 (또는 LoadBalancer/Ingress)
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"nodePort":30443}]}}'

# 초기 admin 비밀번호 조회
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# 브라우저: https://<NodeIP>:30443
# ID: admin / PW: 위에서 조회한 값
```

### CLI 설치

```bash
# argocd CLI 설치 (macOS)
brew install argocd

# 로그인
argocd login <NodeIP>:30443 --username admin --password <PW> --insecure
```

### Application 생성 — YAML 방식

```yaml
# my-app-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # 삭제 시 K8s 리소스도 정리
spec:
  project: default

  # Git 저장소 정보 (manifest repo)
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook                            # 디렉터리 경로

  # 배포 대상
  destination:
    server: https://kubernetes.default.svc     # In-cluster
    namespace: guestbook

  # 동기화 정책
  syncPolicy:
    automated:
      prune: true                              # Git에서 삭제된 리소스도 삭제
      selfHeal: true                           # Drift 발생 시 자동 복원
    syncOptions:
      - CreateNamespace=true                   # namespace 자동 생성
    retry:
      limit: 5
      backoff:
        duration: 5s
        maxDuration: 3m
        factor: 2
```

```bash
# 적용
kubectl apply -f my-app-application.yaml

# 확인
argocd app list
argocd app get guestbook

# 수동 동기화 (자동 모드 아닐 때)
argocd app sync guestbook
```

### Helm Chart 기반 Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: 18.1.0
    helm:
      releaseName: nginx
      values: |
        replicaCount: 3
        service:
          type: NodePort
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### App of Apps 패턴

```yaml
# root-app.yaml — 다른 Application들을 관리하는 메타 Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/argocd-apps.git
    targetRevision: HEAD
    path: applications/                      # 이 디렉터리에 여러 Application YAML
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```
applications/
├── monitoring.yaml      ← Prometheus + Grafana Application
├── logging.yaml         ← Loki Application
├── ingress.yaml         ← Nginx Ingress Application
└── apps/
    ├── frontend.yaml    ← Frontend Application
    └── backend.yaml     ← Backend Application

→ root Application 1개만 만들면, 나머지가 줄줄이 자동 생성/관리됨
```

### ApplicationSet — 멀티 클러스터/환경 자동화

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: dev
            url: https://kubernetes.default.svc
          - cluster: stage
            url: https://stage.example.com
          - cluster: prod
            url: https://prod.example.com
  template:
    metadata:
      name: 'guestbook-{{cluster}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/manifests.git
        targetRevision: HEAD
        path: 'envs/{{cluster}}'
      destination:
        server: '{{url}}'
        namespace: guestbook
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

> 위 예시는 **하나의 ApplicationSet으로 dev/stage/prod 3개 클러스터에 자동 배포**합니다.

### Image Updater — 이미지 자동 업데이트

ArgoCD Image Updater는 컨테이너 레지스트리를 모니터링하다가 새 이미지가 푸시되면 **Manifest Repo의 image 태그를 자동으로 업데이트**합니다.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: myapp=harbor.example.com/myproject/myapp
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver
    argocd-image-updater.argoproj.io/write-back-method: git
spec:
  ...
```

→ Jenkins가 이미지 빌드/Push까지만 하고, 그 이후는 ArgoCD가 자동으로 처리.

---

## 9. FluxCD 개요

### 한 문장 정의

> **FluxCD**는 **Weaveworks**가 만들고 **CNCF Graduated** 상태인 GitOps 도구로,
> ArgoCD보다 **더 가볍고 K8s-Native**하며 여러 컨트롤러로 구성된 **모듈러 아키텍처**가 특징입니다.

### FluxCD v2 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│            Flux v2 (GitOps Toolkit) Components              │
│                                                             │
│   ┌────────────────────┐                                    │
│   │  source-controller │ ─ Git/Helm/OCI 저장소를 watch        │
│   │  (소스 가져오기)     │   GitRepository, HelmRepository CRD │
│   └─────────┬──────────┘                                    │
│             │                                               │
│             ▼                                               │
│   ┌────────────────────┐                                    │
│   │ kustomize-         │ ─ Kustomize 매니페스트 적용          │
│   │ controller         │   Kustomization CRD                │
│   └─────────┬──────────┘                                    │
│             │                                               │
│             ▼                                               │
│   ┌────────────────────┐                                    │
│   │ helm-controller    │ ─ Helm 차트 설치                     │
│   │                    │   HelmRelease CRD                  │
│   └─────────┬──────────┘                                    │
│             │                                               │
│             ▼                                               │
│   ┌────────────────────┐                                    │
│   │ notification-      │ ─ Slack/Discord/Webhook 알림        │
│   │ controller         │   Provider, Alert CRD              │
│   └────────────────────┘                                    │
│                                                             │
│   ┌────────────────────┐                                    │
│   │ image-reflector-   │ ─ 컨테이너 레지스트리 watch          │
│   │ controller         │                                    │
│   └─────────┬──────────┘                                    │
│             ▼                                               │
│   ┌────────────────────┐                                    │
│   │ image-automation-  │ ─ 새 이미지 발견 시 Git에 자동 commit │
│   │ controller         │                                    │
│   └────────────────────┘                                    │
│                                                             │
│   특징:                                                      │
│   ├── 각 컨트롤러는 독립적이고 단일 책임                       │
│   ├── UI는 기본 제공 X (Weave GitOps / Capacitor 별도 설치)    │
│   └── kubectl-style CLI (flux)                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### FluxCD 핵심 CRD

| CRD | 용도 |
|-----|------|
| **GitRepository** | Git 저장소 정의 (URL, 브랜치, 인증) |
| **HelmRepository** | Helm Chart 저장소 정의 |
| **OCIRepository** | OCI 형식 매니페스트/차트 저장소 |
| **Kustomization** | Kustomize 빌드 + apply 정의 |
| **HelmRelease** | Helm Chart 설치 + values 정의 |
| **ImageRepository** | 컨테이너 레지스트리 모니터링 |
| **ImagePolicy** | 이미지 태그 선택 정책 (semver, regex) |
| **ImageUpdateAutomation** | 새 이미지 발견 시 Git에 자동 commit |
| **Alert / Provider** | 알림 채널 정의 |

---

## 10. FluxCD 실습

### Flux CLI 설치

```bash
# macOS
brew install fluxcd/tap/flux

# Linux
curl -s https://fluxcd.io/install.sh | sudo bash
```

### 사전 점검 (Bootstrap 전)

```bash
# 클러스터 호환성 검사
flux check --pre

# 기대 출력:
# ✔ Kubernetes 1.31.0 >=1.28.0
# ✔ prerequisites checks passed
```

### Bootstrap — Flux를 클러스터에 설치 + Git 연동

```bash
# GitHub 토큰 export (repo 권한 필요)
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
export GITHUB_USER=myusername

# Bootstrap 실행
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=fleet-infra \
  --branch=main \
  --path=./clusters/my-cluster \
  --personal

# 위 명령은 다음을 자동 수행:
# 1. fleet-infra 라는 Git 저장소 생성 (없으면)
# 2. flux-system 네임스페이스에 컨트롤러 설치
# 3. 클러스터에 GitRepository(flux-system) 생성하여 자기 자신을 watch
# 4. clusters/my-cluster/ 디렉터리를 watch하는 Kustomization 생성
```

### Bootstrap 후 디렉터리 구조

```
fleet-infra/
└── clusters/
    └── my-cluster/
        └── flux-system/
            ├── gotk-components.yaml      ← Flux 컴포넌트
            ├── gotk-sync.yaml            ← Self-watch 설정
            └── kustomization.yaml
```

### 애플리케이션 배포 — GitRepository + Kustomization

```bash
# 1. GitRepository 정의 (앱 매니페스트가 있는 저장소)
flux create source git podinfo \
  --url=https://github.com/stefanprodan/podinfo \
  --branch=master \
  --interval=1m \
  --export > clusters/my-cluster/podinfo-source.yaml

# 2. Kustomization 정의 (어떤 경로를 적용할지)
flux create kustomization podinfo \
  --target-namespace=default \
  --source=podinfo \
  --path="./kustomize" \
  --prune=true \
  --interval=5m \
  --export > clusters/my-cluster/podinfo-kustomization.yaml

# 3. Git push
git -C ~/fleet-infra add clusters/my-cluster/podinfo-*.yaml
git -C ~/fleet-infra commit -m "Add podinfo"
git -C ~/fleet-infra push

# 4. Flux가 변경 감지 → 자동 배포
flux get kustomizations --watch
```

### 생성된 매니페스트 예시

```yaml
# podinfo-source.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/stefanprodan/podinfo
  ref:
    branch: master
---
# podinfo-kustomization.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: podinfo
  namespace: flux-system
spec:
  interval: 5m
  path: "./kustomize"
  prune: true
  sourceRef:
    kind: GitRepository
    name: podinfo
  targetNamespace: default
```

### Helm Chart 배포

```yaml
# helm-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.bitnami.com/bitnami
---
# helm-release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: nginx
  namespace: default
spec:
  interval: 5m
  chart:
    spec:
      chart: nginx
      version: '18.x'
      sourceRef:
        kind: HelmRepository
        name: bitnami
        namespace: flux-system
  values:
    replicaCount: 3
    service:
      type: NodePort
```

### 이미지 자동 업데이트 (Image Automation)

```yaml
# 1. 레지스트리 모니터링
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: myapp
  namespace: flux-system
spec:
  image: harbor.example.com/myproject/myapp
  interval: 1m
---
# 2. 태그 선택 정책 (semver 1.x.x)
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: myapp
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: myapp
  policy:
    semver:
      range: '>=1.0.0'
---
# 3. Git 자동 커밋 설정
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcd@example.com
        name: fluxcd
      messageTemplate: 'Update image to {{range .Updated.Images}}{{println .}}{{end}}'
    push:
      branch: main
  update:
    path: ./apps/myapp
    strategy: Setters
```

```yaml
# apps/myapp/deployment.yaml — Setter 마커
spec:
  containers:
  - name: myapp
    image: harbor.example.com/myproject/myapp:1.0.0  # {"$imagepolicy": "flux-system:myapp"}
```

> 새 이미지 `myapp:1.0.5` 가 push되면 → Flux가 자동으로 위 매니페스트를 `1.0.5`로 변경하고 Git에 commit.

### Flux 운영 명령어

```bash
# 모든 리소스 상태 조회
flux get all

# Kustomization 즉시 동기화 (Reconcile 트리거)
flux reconcile kustomization podinfo --with-source

# HelmRelease 즉시 동기화
flux reconcile helmrelease nginx -n default

# 잠시 동기화 중지 / 재개
flux suspend kustomization podinfo
flux resume kustomization podinfo

# 이벤트 / 로그 확인
flux events
flux logs --all-namespaces --level=error

# 클러스터에서 완전 제거
flux uninstall --keep-namespace=false
```

---

## 11. ArgoCD vs FluxCD 비교

```
┌─────────────────────────────────────────────────────────────┐
│           ArgoCD vs FluxCD — 한눈에 보기                      │
│                                                             │
│  ArgoCD:                                                    │
│  ├── 강력한 Web UI (GitOps의 "콘솔" 역할)                     │
│  ├── 여러 클러스터를 하나의 ArgoCD에서 관리                     │
│  ├── App of Apps, ApplicationSet 등 강력한 추상화              │
│  ├── 진입 장벽 낮음 (UI 위주)                                  │
│  └── 단일 컨트롤러 → 운영 단순                                │
│                                                             │
│  FluxCD:                                                    │
│  ├── 모듈러 아키텍처 (필요한 컨트롤러만 설치)                   │
│  ├── K8s CRD/CLI 중심 (kubectl get gitrepository)            │
│  ├── 더 가볍고 자원 사용량 적음                                 │
│  ├── 멀티 테넌시: 클러스터마다 Flux 설치                        │
│  └── 이미지 자동 업데이트 내장                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 상세 비교표

| 항목 | ArgoCD | FluxCD |
|------|--------|--------|
| **CNCF 상태** | Graduated | Graduated |
| **시작** | Intuit (2018) | Weaveworks (2016) |
| **아키텍처** | 통합 컨트롤러 | 모듈러 (5+ 컨트롤러) |
| **UI** | ✅ 강력한 내장 UI | ❌ 별도 설치 (Weave GitOps, Capacitor) |
| **CLI** | argocd | flux |
| **Application 단위** | Application CRD | Kustomization / HelmRelease CRD |
| **멀티 클러스터** | 1 ArgoCD → N 클러스터 | 각 클러스터에 Flux 설치 (Hub-Spoke 가능) |
| **Helm 지원** | ✅ (Chart inflate) | ✅ (HelmRelease CRD) |
| **Kustomize 지원** | ✅ | ✅ |
| **이미지 자동 업데이트** | Image Updater (별도) | image-automation-controller (내장) |
| **Webhook** | ✅ | ✅ |
| **Self-Heal (Drift 자동 복원)** | ✅ syncPolicy.selfHeal | ✅ default |
| **Sync Wave** | ✅ Annotation | ✅ dependsOn |
| **알림** | argocd-notifications | notification-controller |
| **RBAC / Multi-Tenant** | Project | Namespace 기반 |
| **OCI 매니페스트** | ✅ | ✅ OCIRepository |
| **러닝 커브** | 낮음 (UI) | 중간 (CRD/CLI) |
| **자원 소비** | 중간 | 낮음 |

### 어떤 것을 선택해야 하나?

```
┌─────────────────────────────────────────────────────────────┐
│                      선택 가이드                              │
│                                                             │
│  ━━ ArgoCD를 선택하라 ━━                                     │
│  ✅ GitOps 입문이라 시각적 도구가 필요할 때                    │
│  ✅ 여러 팀/사람이 UI에서 배포 상태를 확인해야 할 때            │
│  ✅ 단일 ArgoCD로 여러 클러스터를 중앙 관리하고 싶을 때         │
│  ✅ 직관적인 Sync 버튼이 필요할 때                             │
│                                                             │
│  ━━ FluxCD를 선택하라 ━━                                     │
│  ✅ 완전한 K8s-Native 경험을 원할 때                           │
│  ✅ kubectl/CRD에 익숙한 SRE/Platform 팀                      │
│  ✅ 자원 효율(엣지/소형 클러스터) 중요할 때                     │
│  ✅ 이미지 자동화까지 일관된 도구로 처리하고 싶을 때            │
│  ✅ 클러스터마다 독립적으로 GitOps 운영하고 싶을 때             │
│                                                             │
│  ━━ 둘 다 사용하는 경우도 있다 ━━                              │
│  플랫폼 컴포넌트(Ingress/Cert/Monitoring)는 Flux,             │
│  애플리케이션은 ArgoCD UI로 관리 — 하이브리드 패턴             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 12. 통합 시나리오 — Jenkins + ArgoCD

### 전체 파이프라인 흐름

```
┌─────────────────────────────────────────────────────────────┐
│         End-to-End: Jenkins (CI) + ArgoCD (CD)              │
│                                                             │
│  [개발자]                                                    │
│      │ 1. git push (App Repo)                                │
│      ▼                                                      │
│  ┌──────────────┐                                            │
│  │ Jenkins      │ 2. Webhook 트리거                           │
│  │              │                                            │
│  │ Pipeline:    │                                            │
│  │ ├ Build      │ 3. mvn / npm build                         │
│  │ ├ Test       │ 4. unit test                               │
│  │ ├ Scan       │ 5. SonarQube + Trivy                       │
│  │ ├ Image      │ 6. docker build → Harbor push              │
│  │ └ Manifest   │ 7. yq/sed로 Manifest Repo의                 │
│  │   Update    │    image tag 변경 → git push                │
│  └──────┬───────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                            │
│  │ Manifest     │ 8. image: myapp:v1.2.3 commit              │
│  │ Repo (Git)   │                                            │
│  └──────┬───────┘                                            │
│         │ 9. Webhook 또는 Poll                                │
│         ▼                                                    │
│  ┌──────────────┐                                            │
│  │ ArgoCD       │ 10. Diff 감지                                │
│  │              │ 11. kubectl apply (Auto Sync)               │
│  └──────┬───────┘                                            │
│         │                                                    │
│         ▼                                                    │
│  ┌──────────────┐                                            │
│  │ K8s Cluster  │ 12. 새 Pod 롤아웃                            │
│  └──────────────┘                                            │
│                                                             │
│  ✅ Jenkins는 CI만 (빌드/테스트/이미지/매니페스트 갱신)         │
│  ✅ ArgoCD는 CD만 (Git → 클러스터 동기화)                      │
│  ✅ 모든 변경 이력은 Git에                                     │
│  ✅ 롤백 = git revert                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Jenkinsfile에서 Manifest Repo 업데이트

```groovy
stage('Update Manifest Repo (GitOps)') {
    steps {
        container('git') {
            withCredentials([sshUserPrivateKey(
                credentialsId: 'manifest-repo-ssh',
                keyFileVariable: 'SSH_KEY')]) {
                sh """
                  GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no" \
                    git clone git@github.com:myorg/manifests.git
                  cd manifests
                  yq -i '.spec.template.spec.containers[0].image = "${REGISTRY}/${IMAGE}:${TAG}"' \
                    apps/myapp/deployment.yaml
                  git config user.email "jenkins@example.com"
                  git config user.name "Jenkins"
                  git add apps/myapp/deployment.yaml
                  git commit -m "Update myapp to ${TAG}"
                  GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no" \
                    git push origin main
                """
            }
        }
    }
}
```

### 롤백 시나리오

```bash
# 잘못된 배포가 발생한 경우 — Git만 되돌리면 끝
cd manifests
git log --oneline           # 이전 커밋 확인
git revert HEAD             # 직전 커밋 되돌리기
git push origin main

# → ArgoCD가 변경 감지 → 자동으로 이전 버전으로 롤백
# → Pod 재배포 완료까지 보통 1–3분
```

---

## 13. 정리 및 핵심 요약

### 한 문장 요약

```
┌─────────────────────────────────────────────────────────────┐
│  CI/CD = 코드부터 배포까지의 자동화 파이프라인                  │
│                                                             │
│  Jenkins  : 가장 강력하고 유연한 CI 도구 (Push 방식)            │
│             → 빌드/테스트/이미지 생성에 최적                    │
│                                                             │
│  ArgoCD   : K8s GitOps의 대표 주자, UI 강점                    │
│             → 시각적 관리, 멀티 클러스터, App of Apps           │
│                                                             │
│  FluxCD   : K8s-Native, 모듈러, 가벼움                         │
│             → CRD/CLI 중심, 이미지 자동화 내장                  │
│                                                             │
│  현실적인 정답:                                                │
│  ┌─ Jenkins (CI) ─→ Harbor ─→ ArgoCD/Flux (CD) ─→ K8s ─┐    │
│  └─────────────── GitOps 파이프라인 ────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 학습 체크리스트

#### CI/CD 기본
- [ ] CI와 CD의 차이를 설명할 수 있다
- [ ] Continuous Delivery와 Continuous Deployment의 차이를 안다
- [ ] DORA 4대 지표를 알고 있다

#### Jenkins
- [ ] Jenkins Master / Agent 구조를 이해한다
- [ ] Jenkinsfile을 작성하여 Pipeline을 구성할 수 있다
- [ ] kubernetes plugin으로 Agent Pod를 동적 생성할 수 있다
- [ ] Credentials 플러그인으로 비밀 정보를 안전하게 사용할 수 있다

#### GitOps & ArgoCD
- [ ] GitOps 4대 원칙을 설명할 수 있다
- [ ] App Repo와 Manifest Repo를 분리하는 이유를 안다
- [ ] ArgoCD Application CRD를 작성할 수 있다
- [ ] Auto-Sync, Self-Heal, Prune의 차이를 안다
- [ ] ApplicationSet으로 멀티 클러스터에 배포할 수 있다

#### FluxCD
- [ ] Flux v2의 5개 컨트롤러 역할을 설명할 수 있다
- [ ] `flux bootstrap` 으로 초기 설정을 할 수 있다
- [ ] GitRepository + Kustomization으로 앱을 배포할 수 있다
- [ ] HelmRelease로 Helm 차트를 관리할 수 있다
- [ ] ImageUpdateAutomation으로 이미지 자동화를 구성할 수 있다

#### 통합
- [ ] Jenkins(CI) + ArgoCD(CD) 하이브리드 파이프라인을 구성할 수 있다
- [ ] `git revert`로 운영 환경을 롤백할 수 있다
- [ ] 자기 회사 환경에 맞는 CI/CD 도구를 선택할 수 있다

### 추가 학습 리소스

| 주제 | 자료 |
|------|------|
| Jenkins 공식 문서 | https://www.jenkins.io/doc/ |
| ArgoCD 공식 문서 | https://argo-cd.readthedocs.io/ |
| FluxCD 공식 문서 | https://fluxcd.io/flux/ |
| GitOps Working Group | https://opengitops.dev/ |
| OpenGitOps Principles | https://github.com/open-gitops/documents |
| CNCF Landscape (CI/CD) | https://landscape.cncf.io/category=continuous-integration-delivery |
| Argo Rollouts (Canary/Blue-Green) | https://argoproj.github.io/argo-rollouts/ |
| Flagger (Progressive Delivery) | https://flagger.app/ |

---

> **다음 단계 추천**:
> - **Argo Rollouts / Flagger** — Canary, Blue-Green 등 점진적 배포 전략
> - **Tekton** — K8s-Native CI/CD (CRD 기반 파이프라인)
> - **Crossplane** — GitOps로 인프라까지 관리 (IaC + GitOps)
> - **Backstage** — 개발자 포털과 GitOps의 결합
