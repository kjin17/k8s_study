# Kubernetes RBAC 교육 — 인증, 인가, ServiceAccount

> Kubernetes의 보안 모델 핵심인 **RBAC(Role-Based Access Control)**를 다룹니다.
> 누가(Subject) 무엇을(Resource) 어떻게(Verb) 할 수 있는지를 정의하는 4가지 핵심 리소스
> **Role / ClusterRole / RoleBinding / ClusterRoleBinding**과,
> Pod 내부에서 K8s API를 사용하는 **ServiceAccount**, 사용자 인증 메커니즘,
> 그리고 실무에서 자주 마주치는 RBAC 트러블슈팅까지 단계별로 학습합니다.

---

## 목차

1. [API 요청의 흐름 — 인증과 인가](#1-api-요청의-흐름--인증과-인가)
2. [인증(Authentication) 메커니즘](#2-인증authentication-메커니즘)
3. [인가(Authorization) 모드와 RBAC](#3-인가authorization-모드와-rbac)
4. [Subject — User, Group, ServiceAccount](#4-subject--user-group-serviceaccount)
5. [Role과 ClusterRole](#5-role과-clusterrole)
6. [RoleBinding과 ClusterRoleBinding](#6-rolebinding과-clusterrolebinding)
7. [ServiceAccount 심화](#7-serviceaccount-심화)
8. [Aggregated ClusterRole](#8-aggregated-clusterrole)
9. [실무 RBAC 패턴 모음](#9-실무-rbac-패턴-모음)
10. [RBAC 트러블슈팅](#10-rbac-트러블슈팅)
11. [실습 시나리오](#11-실습-시나리오)
12. [정리 및 핵심 요약](#12-정리-및-핵심-요약)

---

## 1. API 요청의 흐름 — 인증과 인가

### 한 문장 정의

> **RBAC**는 "**누가**(Subject) **어떤 리소스**(Resource)를 **어떻게**(Verb) 다룰 수 있는지"를
> Kubernetes 자체 리소스(Role, RoleBinding 등)로 선언적으로 관리하는 인가 메커니즘입니다.

### kubectl 명령 한 줄에 일어나는 일

```
┌─────────────────────────────────────────────────────────────┐
│      kubectl get pods 명령의 전체 처리 흐름                   │
│                                                             │
│   [사용자] kubectl get pods                                  │
│        │                                                    │
│        │ ① ~/.kube/config 의 인증 정보 첨부                  │
│        │   (token / cert / exec credential)                 │
│        ▼                                                    │
│   [kube-apiserver] (Master Node)                            │
│        │                                                    │
│        │ ② Authentication (인증)                             │
│        │   "당신이 누구인가?"                                  │
│        │   → User=alice, Groups=[dev]                       │
│        │                                                    │
│        │ ③ Authorization (인가) — RBAC, ABAC, Webhook 등     │
│        │   "당신이 이 작업을 할 권한이 있는가?"                  │
│        │   → Role/RoleBinding 검사                            │
│        │                                                    │
│        │ ④ Admission Control                                 │
│        │   "이 요청이 정책에 부합하는가?"                       │
│        │   → ResourceQuota, PodSecurity 등                   │
│        │                                                    │
│        │ ⑤ etcd 에 저장 / 조회                                │
│        ▼                                                    │
│   [응답] Pod 목록 반환                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

| 단계 | 누가 처리 | 핵심 질문 |
|------|-----------|-----------|
| ① 자격증명 첨부 | 클라이언트 | "내가 누구인지 어떻게 증명?" |
| ② 인증 | API Server | "이 요청자는 누구인가?" |
| ③ **인가 (RBAC)** | API Server | "이 작업을 할 권한이 있는가?" |
| ④ Admission | API Server | "이 요청이 정책을 따르는가?" |
| ⑤ 저장/조회 | etcd | 실제 작업 수행 |

> **인증(Authentication)** = "Who are you?"
> **인가(Authorization)** = "What can you do?"

---

## 2. 인증(Authentication) 메커니즘

Kubernetes는 자체 사용자 DB를 가지지 않습니다. 외부 인증 시스템 또는 인증서/토큰을 통해 사용자를 식별합니다.

### 인증 방식 종류

```
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes 인증 방식                             │
│                                                             │
│  사람(User) 인증:                                             │
│  ├── X.509 클라이언트 인증서   (kubeadm 기본)                  │
│  ├── Static Token File         (테스트용, 비추천)              │
│  ├── Bootstrap Token           (kubeadm join 용)             │
│  ├── OpenID Connect (OIDC)     ← 운영 환경 표준 (Keycloak,    │
│  │                                Dex, Okta, Google 등)       │
│  └── Authenticating Proxy      (LDAP, Active Directory 연동)  │
│                                                             │
│  Pod 내부 워크로드 인증:                                       │
│  └── ServiceAccount Token      (자동 마운트)                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### kubeconfig 구조

```yaml
# ~/.kube/config — 클러스터, 사용자, 컨텍스트 정의
apiVersion: v1
kind: Config

# 어떤 클러스터에 접속할 것인가
clusters:
- name: my-cluster
  cluster:
    server: https://10.0.0.1:6443
    certificate-authority-data: <CA Cert Base64>

# 어떤 사용자로 접속할 것인가 (인증 정보)
users:
- name: alice
  user:
    client-certificate-data: <Cert Base64>     # X.509 인증서 방식
    client-key-data: <Key Base64>
- name: bob
  user:
    token: eyJhbGciOiJSUzI1NiIs...               # 토큰 방식 (SA Token, OIDC 등)

# 어떤 클러스터에 어떤 사용자로 접속할지 + 기본 namespace
contexts:
- name: alice@my-cluster
  context:
    cluster: my-cluster
    user: alice
    namespace: dev

current-context: alice@my-cluster
```

### X.509 인증서로 사용자 만들기 (직접 실습용)

```bash
# 1. 사용자용 개인 키 생성
openssl genrsa -out alice.key 2048

# 2. CSR(Certificate Signing Request) 생성
#    CN=사용자명, O=그룹명
openssl req -new -key alice.key -out alice.csr \
  -subj "/CN=alice/O=dev-team"

# 3. K8s CSR 리소스로 제출
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: alice-csr
spec:
  request: $(cat alice.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400        # 1일
  usages:
  - client auth
EOF

# 4. 관리자가 승인
kubectl certificate approve alice-csr

# 5. 발급된 인증서 추출
kubectl get csr alice-csr -o jsonpath='{.status.certificate}' | base64 -d > alice.crt

# 6. kubeconfig에 등록
kubectl config set-credentials alice \
  --client-certificate=alice.crt \
  --client-key=alice.key \
  --embed-certs=true

kubectl config set-context alice@my-cluster \
  --cluster=my-cluster --user=alice --namespace=dev

# 7. 사용자로 전환
kubectl config use-context alice@my-cluster
kubectl auth whoami
# Username: alice
# Groups: [dev-team system:authenticated]
```

> **CN(Common Name) = 사용자명**, **O(Organization) = 그룹명**으로 인식됩니다.
> 같은 CN을 여러 O와 함께 발급하면 그 사용자는 여러 그룹에 속하게 됩니다.

### kubectl auth whoami — 내가 누구인지 확인

```bash
kubectl auth whoami

# 예시 출력:
# ATTRIBUTE   VALUE
# Username    alice
# Groups      [dev-team system:authenticated]
```

---

## 3. 인가(Authorization) 모드와 RBAC

### 인가 모드

Kubernetes는 여러 인가 모드를 동시에 사용할 수 있으며, **하나라도 허용하면 통과**합니다.

| 모드 | 설명 | 사용처 |
|------|------|--------|
| **Node** | kubelet의 권한 자동 관리 | 모든 클러스터 (필수) |
| **RBAC** | Role 기반 접근 제어 | **표준 방식** |
| **Webhook** | 외부 서비스에 인가 위임 | OPA, 외부 정책 엔진 |
| **ABAC** | 속성 기반 (JSON 정책) | Legacy, 비추천 |
| **AlwaysAllow** | 무조건 허용 | 테스트용 (운영 금지) |
| **AlwaysDeny** | 무조건 거부 | 디버깅용 |

```bash
# kube-apiserver의 인가 모드 확인 (kubeadm 기본 클러스터)
kubectl get pod -n kube-system kube-apiserver-<master> -o yaml | grep authorization-mode
# --authorization-mode=Node,RBAC
```

### RBAC의 4가지 핵심 리소스

```
┌─────────────────────────────────────────────────────────────┐
│                  RBAC 4대 핵심 리소스                          │
│                                                             │
│       ┌─────────────────────────────────────────────┐       │
│       │ Role                ClusterRole             │       │
│       │ (네임스페이스 범위)   (클러스터 전체)          │       │
│       │                                             │       │
│       │  → 권한의 정의 (무엇을 할 수 있는가)             │       │
│       └─────────────────────────────────────────────┘       │
│                          │                                  │
│                          │ 참조                              │
│                          ▼                                  │
│       ┌─────────────────────────────────────────────┐       │
│       │ RoleBinding         ClusterRoleBinding      │       │
│       │ (네임스페이스 범위)   (클러스터 전체)          │       │
│       │                                             │       │
│       │  → 권한을 누구에게 부여할지 (User/Group/SA)    │       │
│       └─────────────────────────────────────────────┘       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

| 리소스 | 범위 | 역할 |
|--------|------|------|
| **Role** | Namespace | 특정 네임스페이스 내의 권한 모음 |
| **ClusterRole** | Cluster | 클러스터 전체 또는 비-네임스페이스 리소스(노드, PV 등) 권한 |
| **RoleBinding** | Namespace | Role 또는 ClusterRole을 특정 네임스페이스에서 Subject에 부여 |
| **ClusterRoleBinding** | Cluster | ClusterRole을 클러스터 전역에서 Subject에 부여 |

### 조합 시나리오 — 4가지 매트릭스

```
┌─────────────────────────────────────────────────────────────┐
│            Role/ClusterRole × Binding 조합                   │
│                                                             │
│  ① Role + RoleBinding                                       │
│     → 특정 NS 안에서만 권한 부여                              │
│     → 가장 일반적                                              │
│                                                             │
│  ② ClusterRole + ClusterRoleBinding                         │
│     → 클러스터 전체에서 권한 부여                              │
│     → cluster-admin이 대표적                                 │
│                                                             │
│  ③ ClusterRole + RoleBinding ★ 매우 유용 ★                   │
│     → ClusterRole로 권한을 한 번만 정의                        │
│     → 여러 네임스페이스에서 같은 권한을 재활용                  │
│     → "view" ClusterRole을 dev/stage/prod 각각에 부여 등       │
│                                                             │
│  ④ Role + ClusterRoleBinding ❌ 불가능 ❌                    │
│     → 네임스페이스 한정 권한을 클러스터 전역에 부여 불가         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Subject — User, Group, ServiceAccount

RBAC에서 권한을 부여받는 대상(Subject)은 3가지입니다.

```yaml
subjects:
# ① 개별 사용자 (X.509 CN, OIDC sub 등)
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io

# ② 그룹 (X.509 O, OIDC groups 등)
- kind: Group
  name: dev-team
  apiGroup: rbac.authorization.k8s.io

# ③ ServiceAccount (Pod 내부 워크로드)
- kind: ServiceAccount
  name: jenkins
  namespace: ci         # SA는 namespace 필수
```

### 시스템 그룹

K8s가 자동으로 부여하는 특수 그룹:

| 그룹 | 의미 |
|------|------|
| `system:authenticated` | 인증된 모든 사용자 |
| `system:unauthenticated` | 익명 사용자 |
| `system:masters` | **클러스터 슈퍼유저 (cluster-admin과 동등)** |
| `system:nodes` | 모든 kubelet |
| `system:serviceaccounts` | 모든 ServiceAccount |
| `system:serviceaccounts:<ns>` | 특정 네임스페이스의 모든 SA |

> ⚠️ `system:masters` 그룹에 사용자를 추가하면 모든 RBAC를 우회하므로 **절대로 일반 사용자에게 부여하지 마세요**.

---

## 5. Role과 ClusterRole

### Role 예시 — 네임스페이스 내 Pod 읽기

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev                       # ← Role은 namespace 필수
  name: pod-reader
rules:
- apiGroups: [""]                      # "" = core API 그룹 (Pod, Service, ConfigMap 등)
  resources: ["pods", "pods/log"]      # 어떤 리소스를
  verbs: ["get", "list", "watch"]      # 어떻게 다룰 수 있는가
```

### ClusterRole 예시 — 노드 정보 읽기 (cluster-scoped)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader                    # ← ClusterRole은 namespace 없음
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/status"]
  verbs: ["get", "list", "watch"]
```

### rules의 핵심 필드

```yaml
rules:
- apiGroups: ["apps", "batch"]         # 여러 API 그룹
  resources:
    - "deployments"                    # 일반 리소스
    - "deployments/scale"              # 서브리소스 (스케일)
    - "deployments/status"             # 상태 서브리소스
  verbs:
    - "get"        # 단건 조회
    - "list"       # 목록 조회
    - "watch"      # 변경 감지
    - "create"     # 생성
    - "update"     # 전체 업데이트
    - "patch"      # 부분 업데이트
    - "delete"     # 삭제
    - "deletecollection"  # 일괄 삭제
  resourceNames: ["my-app"]            # 특정 이름의 리소스만 허용 (선택)
- nonResourceURLs: ["/healthz", "/metrics"]  # API가 아닌 URL (헬스체크 등)
  verbs: ["get"]
```

### 자주 쓰는 Verb 요약

| Verb | 대응 kubectl 명령 |
|------|-----------------|
| `get` | `kubectl get pod xxx` |
| `list` | `kubectl get pods` |
| `watch` | `kubectl get pods -w` |
| `create` | `kubectl create / kubectl apply` |
| `update` | `kubectl replace` |
| `patch` | `kubectl edit / kubectl patch` |
| `delete` | `kubectl delete pod xxx` |
| `deletecollection` | `kubectl delete pods --all` |

> **`*`** (와일드카드) 사용 가능하지만 운영에서는 명시적 권한 부여 권장.

### apiGroups 예시

| apiGroup | 포함 리소스 |
|----------|-------------|
| `""` (core) | pods, services, configmaps, secrets, namespaces, nodes, pv, pvc 등 |
| `apps` | deployments, statefulsets, daemonsets, replicasets |
| `batch` | jobs, cronjobs |
| `networking.k8s.io` | ingresses, networkpolicies |
| `rbac.authorization.k8s.io` | roles, rolebindings, clusterroles, clusterrolebindings |
| `storage.k8s.io` | storageclasses, csidrivers |
| `apiextensions.k8s.io` | customresourcedefinitions |

```bash
# 어떤 리소스가 어떤 apiGroup에 속하는지 확인
kubectl api-resources

# 특정 apiGroup의 리소스만
kubectl api-resources --api-group=apps
```

### 기본 제공 ClusterRole (Default ClusterRoles)

K8s가 미리 만들어 둔 ClusterRole 4종:

| 이름 | 권한 |
|------|------|
| `cluster-admin` | 모든 권한 (`*` × `*` × `*`) — 슈퍼유저 |
| `admin` | 네임스페이스 내 모든 권한 (RoleBinding으로 부여 시) |
| `edit` | 대부분 리소스 읽기/쓰기 (RBAC 자체는 제외) |
| `view` | 대부분 리소스 읽기만 (Secret 제외) |

```bash
# 기본 ClusterRole 확인
kubectl get clusterrole | grep -E '^(cluster-admin|admin|edit|view)'

# 권한 상세
kubectl describe clusterrole view
```

> 일반적으로 **사용자에게는 `view` / `edit` / `admin`을 RoleBinding으로 부여**하면 충분합니다.

---

## 6. RoleBinding과 ClusterRoleBinding

### RoleBinding — Role 또는 ClusterRole을 NS 내에서 Subject에 부여

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: dev                       # ← 어느 namespace에서 적용할지
  name: alice-pod-reader
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role                           # 또는 ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### ClusterRoleBinding — ClusterRole을 클러스터 전역에서 Subject에 부여

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ops-cluster-admin
subjects:
- kind: Group
  name: ops-team                       # OIDC 그룹 등
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

### ★ 패턴 ③ — ClusterRole + RoleBinding 활용

같은 권한을 여러 네임스페이스에서 재사용할 때 매우 유용:

```yaml
# 1. ClusterRole 한 번만 정의 (전역에 보관)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: app-developer                  # 네임스페이스 없음 (cluster-scoped)
rules:
- apiGroups: ["", "apps"]
  resources: ["pods", "deployments", "services", "configmaps"]
  verbs: ["*"]
---
# 2. dev 네임스페이스에서 alice에게 부여
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: dev
  name: alice-developer
subjects:
- kind: User
  name: alice
roleRef:
  kind: ClusterRole                    # ★ ClusterRole을 참조
  name: app-developer                  # 정의는 한 번만
  apiGroup: rbac.authorization.k8s.io
---
# 3. test 네임스페이스에서 alice에게도 부여
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: test
  name: alice-developer
subjects:
- kind: User
  name: alice
roleRef:
  kind: ClusterRole
  name: app-developer
  apiGroup: rbac.authorization.k8s.io
```

> alice는 `dev`, `test` 두 네임스페이스에서만 `app-developer` 권한을 가집니다. (`prod`는 X)

### 권한 변경 불가 — roleRef는 immutable

기존 RoleBinding의 `roleRef`는 변경할 수 없습니다. 다른 Role을 참조하려면 **삭제 후 재생성** 필요.

```bash
# 잘못된 시도
kubectl edit rolebinding alice-developer -n dev   # → roleRef 변경 시 에러

# 올바른 방법
kubectl delete rolebinding alice-developer -n dev
kubectl apply -f new-binding.yaml
```

---

## 7. ServiceAccount 심화

### ServiceAccount란?

> **ServiceAccount(SA)**는 **Pod 내부에서 동작하는 워크로드**가 K8s API를 호출할 때 사용하는 identity입니다.
> 사람(User)이 아닌 **프로세스/Pod의 신원**을 의미합니다.

### 자동 마운트 메커니즘

```
┌─────────────────────────────────────────────────────────────┐
│        ServiceAccount Token Auto-Mount                      │
│                                                             │
│   1. Pod 생성 시 .spec.serviceAccountName 지정 (없으면 default)│
│                                                             │
│   2. kubelet이 토큰을 Pod에 자동 마운트:                      │
│      /var/run/secrets/kubernetes.io/serviceaccount/         │
│      ├── token       ← JWT 토큰 (자동 갱신, K8s 1.24+)        │
│      ├── ca.crt      ← API Server CA                         │
│      └── namespace   ← Pod의 namespace                       │
│                                                             │
│   3. Pod 내부 클라이언트(예: kubectl, client-go)는            │
│      위 경로의 token을 자동으로 사용                          │
│                                                             │
│   4. API Server는 토큰으로 SA를 식별 → RBAC 적용              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### ServiceAccount 만들기

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: ci
```

```bash
kubectl create serviceaccount jenkins -n ci
kubectl get serviceaccount jenkins -n ci
```

### Pod에서 ServiceAccount 사용

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: jenkins-agent
  namespace: ci
spec:
  serviceAccountName: jenkins             # ★ 지정
  automountServiceAccountToken: true      # 기본값 true
  containers:
  - name: agent
    image: jenkins/inbound-agent:latest
```

### SA에 권한 부여 (RoleBinding)

```yaml
# jenkins SA가 ci 네임스페이스에서 모든 작업 가능
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: ci
  name: jenkins-admin
subjects:
- kind: ServiceAccount
  name: jenkins
  namespace: ci                           # ← SA의 namespace
roleRef:
  kind: ClusterRole
  name: admin                             # 기본 제공 admin ClusterRole
  apiGroup: rbac.authorization.k8s.io
```

### Token 직접 발급 (외부 도구용)

```bash
# K8s 1.24+ — kubectl로 임시 토큰 발급
kubectl create token jenkins -n ci --duration=24h

# K8s 1.23 이하 — Secret 자동 생성됨
kubectl get secret -n ci | grep jenkins
kubectl get secret jenkins-token-xxxx -n ci -o jsonpath='{.data.token}' | base64 -d
```

### TokenRequest API — Projected Volume

K8s 1.21+ 부터는 **시간 제한이 있는 토큰**이 자동 갱신됩니다 (BoundServiceAccountTokenVolume).

```yaml
spec:
  serviceAccountName: jenkins
  volumes:
  - name: api-token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600         # 1시간마다 갱신
          audience: jenkins
  containers:
  - name: app
    volumeMounts:
    - name: api-token
      mountPath: /var/run/secrets/tokens
      readOnly: true
```

### default ServiceAccount 보안 강화

기본적으로 모든 namespace에 `default` SA가 자동 생성되며, 명시하지 않으면 Pod에 자동 마운트됩니다.
운영 환경에서는 **자동 마운트를 비활성화**하는 것이 권장됩니다.

```yaml
# default SA의 자동 마운트 비활성화 (NS 단위)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: dev
automountServiceAccountToken: false
```

또는 Pod 단위로:

```yaml
apiVersion: v1
kind: Pod
spec:
  automountServiceAccountToken: false     # API 호출이 필요 없는 워크로드
```

---

## 8. Aggregated ClusterRole

여러 ClusterRole을 **레이블로 자동 묶는** 메커니즘. CRD가 도입되었을 때 기본 `view`/`edit`/`admin` 역할에 자동 권한 추가에 자주 사용됩니다.

```yaml
# 1. Aggregated ClusterRole — 빈 rules + aggregationRule
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-view
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.example.com/aggregate-to-monitoring-view: "true"
rules: []                                  # 컨트롤러가 자동으로 채움

---
# 2. 라벨이 붙은 일반 ClusterRole이 자동으로 위에 합쳐짐
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-rules-view
  labels:
    rbac.example.com/aggregate-to-monitoring-view: "true"
rules:
- apiGroups: ["monitoring.coreos.com"]
  resources: ["prometheusrules", "servicemonitors"]
  verbs: ["get", "list", "watch"]
```

> 새 모니터링 도구가 추가되어도 `aggregate-to-monitoring-view: true` 라벨만 붙이면 자동으로 권한이 통합됩니다.

기본 `view`/`edit`/`admin` ClusterRole도 모두 Aggregated 방식으로 동작합니다:

```bash
kubectl get clusterrole view -o yaml | grep -A5 aggregationRule
# aggregationRule:
#   clusterRoleSelectors:
#   - matchLabels:
#       rbac.authorization.k8s.io/aggregate-to-view: "true"
```

---

## 9. 실무 RBAC 패턴 모음

### 패턴 1 — 네임스페이스 단위 개발팀 권한

```yaml
# dev-team 그룹은 dev 네임스페이스에서 admin
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: dev
  name: dev-team-admin
subjects:
- kind: Group
  name: dev-team
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
```

### 패턴 2 — 읽기 전용 운영자 (전 클러스터)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: readonly-cluster
subjects:
- kind: Group
  name: support-team
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
```

### 패턴 3 — Secret 접근 차단 + 일반 리소스 편집

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev
  name: developer-no-secrets
rules:
- apiGroups: ["", "apps", "networking.k8s.io"]
  resources: ["pods", "services", "deployments", "ingresses", "configmaps"]
  verbs: ["*"]
# Secret은 명시적으로 제외 (rules에 없음 = 권한 없음)
```

### 패턴 4 — 특정 리소스 이름만 허용

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: prod
  name: edit-myapp-only
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: ["myapp", "myapp-worker"]   # ← 이 두 개만 허용
  verbs: ["get", "patch", "update"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["list"]                            # list는 resourceNames와 함께 못 씀
```

> **주의**: `list`/`watch`/`deletecollection`은 `resourceNames`와 함께 사용 불가.

### 패턴 5 — Pod exec 권한만 부여 (디버깅용)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: prod
  name: pod-debugger
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/exec", "pods/portforward", "pods/log"]
  verbs: ["create", "get"]
```

### 패턴 6 — CI/CD ServiceAccount (제한적 배포 권한)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitops-deployer
  namespace: argocd
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gitops-deployer
rules:
- apiGroups: ["", "apps", "networking.k8s.io"]
  resources: ["deployments", "services", "configmaps", "ingresses", "pods"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list"]                     # 생성/삭제는 불가
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gitops-deployer
subjects:
- kind: ServiceAccount
  name: gitops-deployer
  namespace: argocd
roleRef:
  kind: ClusterRole
  name: gitops-deployer
  apiGroup: rbac.authorization.k8s.io
```

### 패턴 7 — 모든 namespace의 Pod 읽기

```yaml
# ClusterRole + ClusterRoleBinding 조합 (모든 NS)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-reader-all
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: monitoring-pod-reader
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: pod-reader-all
  apiGroup: rbac.authorization.k8s.io
```

---

## 10. RBAC 트러블슈팅

### `kubectl auth can-i` — 권한 확인의 황금 명령어

```bash
# 내가 dev 네임스페이스에서 Pod를 생성할 수 있는가?
kubectl auth can-i create pods -n dev
# yes / no

# 다른 사용자(impersonation) 권한 확인 — 관리자 전용
kubectl auth can-i list secrets -n prod --as=alice
kubectl auth can-i '*' '*' --as=alice          # 모든 권한 확인

# 그룹 입장에서 확인
kubectl auth can-i delete deployments -n dev --as=alice --as-group=dev-team

# ServiceAccount 권한 확인
kubectl auth can-i get pods -n ci \
  --as=system:serviceaccount:ci:jenkins

# 내 모든 권한 한 번에 출력
kubectl auth can-i --list -n dev
```

### Forbidden 에러 메시지 해석

```
Error from server (Forbidden): pods is forbidden:
User "alice" cannot list resource "pods" in API group "" in the namespace "prod"
```

| 에러 정보 | 의미 |
|-----------|------|
| `User "alice"` | 인증된 사용자 (또는 SA) |
| `cannot list resource "pods"` | 부족한 권한 (verb + resource) |
| `in API group ""` | core API 그룹 |
| `in the namespace "prod"` | 적용 네임스페이스 |

→ 위 정보를 그대로 Role의 rules에 매칭하여 추가하면 됨.

### 디버깅 단계별 체크리스트

```
┌─────────────────────────────────────────────────────────────┐
│         "Forbidden" 에러를 만났을 때 체크리스트                  │
│                                                             │
│  1️⃣ 누구로 요청했는가?                                       │
│     kubectl auth whoami                                     │
│     kubectl config current-context                          │
│                                                             │
│  2️⃣ 어떤 권한이 필요한가?                                     │
│     에러 메시지에서 verb + resource + apiGroup 추출            │
│                                                             │
│  3️⃣ 권한이 있는지 확인                                       │
│     kubectl auth can-i <verb> <resource> -n <ns>             │
│                                                             │
│  4️⃣ 어떤 RoleBinding이 적용 중인지 확인                      │
│     kubectl get rolebinding,clusterrolebinding -A           │
│       -o json | jq '.items[] |                              │
│       select(.subjects[]?.name=="alice")'                   │
│                                                             │
│  5️⃣ Role/ClusterRole 내용 확인                              │
│     kubectl describe role <name> -n <ns>                    │
│     kubectl describe clusterrole <name>                     │
│                                                             │
│  6️⃣ RoleBinding 추가 또는 수정                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 사용자/SA에 묶인 모든 RoleBinding 찾기

```bash
# alice 사용자의 모든 RoleBinding (네임스페이스별)
kubectl get rolebinding -A -o json | \
  jq '.items[] | select(.subjects[]?.name=="alice") |
       {ns: .metadata.namespace, name: .metadata.name, role: .roleRef.name}'

# alice의 모든 ClusterRoleBinding
kubectl get clusterrolebinding -o json | \
  jq '.items[] | select(.subjects[]?.name=="alice") |
       {name: .metadata.name, role: .roleRef.name}'

# ServiceAccount jenkins에 묶인 권한
kubectl get rolebinding,clusterrolebinding -A -o json | \
  jq '.items[] | select(.subjects[]? |
       .kind=="ServiceAccount" and .name=="jenkins") |
       {kind: .kind, ns: .metadata.namespace, name: .metadata.name, role: .roleRef.name}'
```

### audit 로그로 누가 무엇을 했는지 추적

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]
- level: RequestResponse
  resources:
  - group: "rbac.authorization.k8s.io"
    resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
```

### 흔한 함정

| 증상 | 원인 | 해결 |
|------|------|------|
| ClusterRole이 적용되지 않음 | RoleBinding의 `roleRef.kind` 불일치 | `Role` ↔ `ClusterRole` 확인 |
| 같은 권한인데 NS별로 다르게 동작 | RoleBinding 누락 | 각 NS에 RoleBinding 필요 |
| `list` 권한이 안 먹음 | `resourceNames` 와 함께 사용 | `list`는 별도 rule로 분리 |
| Pod이 갑자기 SA token 사용 못 함 | K8s 1.24+ 토큰 자동 만료 | TokenRequest 또는 `kubectl create token` |
| `system:masters` 그룹으로 들어옴 | X.509 O 필드가 잘못됨 | CSR 재발급, 절대 `system:` prefix 금지 |

---

## 11. 실습 시나리오

### 실습 1 — alice 사용자에게 dev 네임스페이스 view 권한 부여

```bash
# 1. dev 네임스페이스 생성
kubectl create namespace dev

# 2. alice 인증서 생성 (인증)
openssl genrsa -out alice.key 2048
openssl req -new -key alice.key -out alice.csr -subj "/CN=alice/O=dev-team"

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: alice-csr
spec:
  request: $(cat alice.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
EOF

kubectl certificate approve alice-csr
kubectl get csr alice-csr -o jsonpath='{.status.certificate}' | base64 -d > alice.crt

# 3. RoleBinding 생성 (인가)
kubectl create rolebinding alice-view \
  --clusterrole=view \
  --user=alice \
  --namespace=dev

# 4. 확인
kubectl auth can-i get pods --as=alice -n dev          # yes
kubectl auth can-i delete pods --as=alice -n dev       # no
kubectl auth can-i get pods --as=alice -n default      # no
```

### 실습 2 — Jenkins ServiceAccount에 ci 네임스페이스 admin 권한

```bash
# 1. ci 네임스페이스 + SA
kubectl create namespace ci
kubectl create serviceaccount jenkins -n ci

# 2. RoleBinding (admin ClusterRole 재사용)
kubectl create rolebinding jenkins-admin \
  --clusterrole=admin \
  --serviceaccount=ci:jenkins \
  --namespace=ci

# 3. 토큰 발급 (외부 Jenkins 서버에 등록용)
TOKEN=$(kubectl create token jenkins -n ci --duration=720h)
echo "$TOKEN"

# 4. 권한 확인
kubectl auth can-i create deployments \
  --as=system:serviceaccount:ci:jenkins -n ci          # yes

kubectl auth can-i create deployments \
  --as=system:serviceaccount:ci:jenkins -n prod        # no
```

### 실습 3 — 일반 사용자에게 일부 Deployment만 재시작 허용

```yaml
# rolling-restarter.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: prod
  name: rolling-restarter
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: ["frontend", "backend"]
  verbs: ["get", "patch"]                  # patch로 rollout restart 트리거
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: prod
  name: oncall-restarter
subjects:
- kind: User
  name: bob
roleRef:
  kind: Role
  name: rolling-restarter
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f rolling-restarter.yaml

# bob은 frontend/backend만 재시작 가능
kubectl auth can-i patch deployment/frontend --as=bob -n prod    # yes
kubectl auth can-i patch deployment/database --as=bob -n prod    # no
```

---

## 12. 정리 및 핵심 요약

### 한 문장 요약

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  RBAC 한 줄 요약:                                             │
│  "누가(Subject) → 어떤 권한(Role)을 → 부여받는다(Binding)"     │
│                                                             │
│  Subject  : User / Group / ServiceAccount                   │
│  Role     : 권한의 정의 (apiGroups + resources + verbs)      │
│  Binding  : Subject ↔ Role 연결                              │
│                                                             │
│  범위:                                                       │
│  ├── Role + RoleBinding              → Namespace 한정         │
│  ├── ClusterRole + ClusterRoleBinding → 클러스터 전역          │
│  └── ClusterRole + RoleBinding        → 권한 재사용 패턴 ⭐    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### RBAC 모범 사례

```
✅ 최소 권한 원칙 (Principle of Least Privilege)
   필요한 권한만, 필요한 시간만 부여

✅ 그룹 기반 권한 관리
   개별 사용자 대신 OIDC/X.509 그룹에 RoleBinding

✅ 네임스페이스로 격리
   팀별/환경별 namespace + RoleBinding

✅ ServiceAccount는 Pod별로 분리
   default SA를 그대로 쓰지 말고 워크로드별 SA 생성

✅ default SA의 자동 마운트 비활성화
   automountServiceAccountToken: false

✅ Secret 접근은 별도로 검토
   view ClusterRole도 Secret은 제외되어 있음

✅ 변경 이력 보존
   RBAC 변경은 Git으로 관리 + audit log 활성화

❌ system:masters 그룹 함부로 부여 금지
   → 모든 RBAC 우회

❌ wildcard(*) 남발 금지
   → cluster-admin 외에는 명시적 권한 사용

❌ ClusterRoleBinding을 일반 사용자에게 함부로 X
   → 가능한 RoleBinding으로 범위 제한
```

### 학습 체크리스트

#### 기본
- [ ] 인증과 인가의 차이를 설명할 수 있다
- [ ] kubeconfig의 cluster/user/context 구조를 안다
- [ ] `kubectl auth whoami` / `can-i` 명령을 사용할 수 있다

#### Role / Binding
- [ ] Role과 ClusterRole의 차이를 안다
- [ ] RoleBinding과 ClusterRoleBinding의 차이를 안다
- [ ] ClusterRole + RoleBinding 패턴의 장점을 설명할 수 있다
- [ ] apiGroups, resources, verbs를 직접 작성할 수 있다
- [ ] 기본 ClusterRole(view/edit/admin/cluster-admin)의 차이를 안다

#### ServiceAccount
- [ ] Pod에 ServiceAccount를 지정할 수 있다
- [ ] SA Token이 어떻게 Pod에 마운트되는지 설명할 수 있다
- [ ] `kubectl create token`으로 SA 토큰을 발급할 수 있다
- [ ] default SA의 자동 마운트를 비활성화할 수 있다

#### 트러블슈팅
- [ ] Forbidden 에러 메시지에서 필요한 정보를 추출할 수 있다
- [ ] 특정 사용자/SA의 모든 RoleBinding을 찾을 수 있다
- [ ] `--as` / `--as-group` 으로 impersonation 테스트를 할 수 있다

#### 실무
- [ ] OIDC와 K8s RBAC를 연동하는 흐름을 안다
- [ ] CI/CD 도구를 위한 ServiceAccount + RBAC를 설계할 수 있다
- [ ] Aggregated ClusterRole이 무엇이고 왜 쓰는지 안다

### 추가 학습 리소스

| 주제 | 자료 |
|------|------|
| 공식 RBAC 문서 | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| 인증 메커니즘 | https://kubernetes.io/docs/reference/access-authn-authz/authentication/ |
| Audit Logging | https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/ |
| OIDC 연동 (Dex) | https://github.com/dexidp/dex |
| RBAC Lookup CLI | https://github.com/FairwindsOps/rbac-lookup |
| RBAC Manager | https://github.com/FairwindsOps/rbac-manager |
| Kyverno (RBAC 정책 검증) | https://kyverno.io/ |
| OPA Gatekeeper | https://open-policy-agent.github.io/gatekeeper/ |

---

> **다음 단계 추천**:
> - **NetworkPolicy** — Pod 간 네트워크 격리(인가의 네트워크 계층)
> - **PodSecurity Admission** — Pod 보안 정책(SecurityContext, capabilities)
> - **OPA Gatekeeper / Kyverno** — 정책 기반 인가 (Webhook 모드)
> - **OIDC + Dex** — 엔터프라이즈 SSO 연동
> - **HashiCorp Vault Injector** — Secret 관리와 SA 통합
