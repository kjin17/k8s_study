# 06. 실습 예제

## 실습 환경: Kind 클러스터

```bash
# CNI 없는 Kind 클러스터 생성 (CNI 직접 설치용)
cat <<EOF > kind-no-cni.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true   # 기본 kindnet CNI 비활성화
  podSubnet: "10.244.0.0/16"
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

kind create cluster --name cni-test --config kind-no-cni.yaml
```

---

## 실습 1: Calico 설치 및 NetworkPolicy 테스트

### 1-1. Calico 설치

```bash
# Calico Operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

kubectl create -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - cidr: 10.244.0.0/16
        encapsulation: VXLAN
EOF

# 설치 완료 대기
kubectl wait --for=condition=Ready pod -l k8s-app=calico-node -n calico-system --timeout=120s
```

### 1-2. 테스트 앱 배포

```bash
kubectl create namespace policy-test

# frontend 파드
kubectl run frontend --image=nginx --labels="app=frontend" -n policy-test
# backend 파드
kubectl run backend --image=nginx --labels="app=backend" -n policy-test
# 외부 파드
kubectl run external --image=nginx --labels="app=external" -n policy-test

kubectl wait --for=condition=Ready pod --all -n policy-test
```

### 1-3. 기본 통신 확인 (정책 없음)

```bash
FRONTEND_IP=$(kubectl get pod frontend -n policy-test -o jsonpath='{.status.podIP}')
BACKEND_IP=$(kubectl get pod backend -n policy-test -o jsonpath='{.status.podIP}')

# 모든 Pod 간 통신 가능
kubectl exec -n policy-test frontend -- curl -s --max-time 3 $BACKEND_IP
# 200 OK

kubectl exec -n policy-test external -- curl -s --max-time 3 $BACKEND_IP
# 200 OK
```

### 1-4. NetworkPolicy 적용 — frontend만 backend 접근 허용

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend-only
  namespace: policy-test
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 80
EOF

# frontend → backend: 허용
kubectl exec -n policy-test frontend -- curl -s --max-time 3 $BACKEND_IP
# 200 OK

# external → backend: 차단
kubectl exec -n policy-test external -- curl -s --max-time 3 $BACKEND_IP
# 타임아웃 (차단됨)
```

### 1-5. Calico GlobalNetworkPolicy

```bash
# calicoctl로 전체 클러스터 기본 Deny 정책
calicoctl apply -f - <<EOF
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: default-deny-all
spec:
  selector: all()
  order: 9999
  types:
    - Ingress
    - Egress
  egress:
    - action: Allow
      destination:
        ports: [53]
EOF
```

---

## 실습 2: Cilium 설치 및 L7 정책 테스트

### 2-1. Cilium 설치

```bash
# 새 클러스터 생성
kind create cluster --name cilium-test --config kind-no-cni.yaml

# Cilium 설치
cilium install --version 1.15.0
cilium status --wait

# Hubble 활성화
cilium hubble enable
```

### 2-2. L7 HTTP 정책 테스트

```bash
kubectl create namespace l7-test

# httpbin 배포 (다양한 HTTP 응답 제공)
kubectl run httpbin --image=kennethreitz/httpbin --labels="app=httpbin" -n l7-test
kubectl expose pod httpbin --port=80 -n l7-test

# 클라이언트 파드
kubectl run client --image=curlimages/curl --labels="app=client" \
  -n l7-test --command -- sleep 3600

kubectl wait --for=condition=Ready pod --all -n l7-test

# 정책 없이 모든 메서드 가능
kubectl exec -n l7-test client -- curl -s http://httpbin/get     # 200 OK
kubectl exec -n l7-test client -- curl -s -X POST http://httpbin/post  # 200 OK
kubectl exec -n l7-test client -- curl -s http://httpbin/delete  # 200 OK
```

```bash
# L7 정책 — GET /get 만 허용
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-get-only
  namespace: l7-test
spec:
  endpointSelector:
    matchLabels:
      app: httpbin
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: client
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
          rules:
            http:
              - method: GET
                path: /get
EOF

# GET /get → 허용
kubectl exec -n l7-test client -- curl -s http://httpbin/get
# 200 OK

# POST → 차단
kubectl exec -n l7-test client -- curl -s -X POST http://httpbin/post
# 403 Forbidden

# GET /status → 차단 (경로 불일치)
kubectl exec -n l7-test client -- curl -s http://httpbin/status/200
# 403 Forbidden
```

### 2-3. Hubble로 트래픽 관찰

```bash
# 실시간 플로우 확인
hubble observe -n l7-test --follow

# 드롭된 패킷만 확인
hubble observe -n l7-test --verdict DROPPED

# 특정 파드 트래픽
hubble observe -n l7-test --pod client --follow

# Hubble UI (브라우저)
cilium hubble ui
# http://localhost:12000 자동 오픈
```

---

## 실습 3: Antrea 설치 및 ANP(Antrea NetworkPolicy) 테스트

```bash
# 새 클러스터 생성
kind create cluster --name antrea-test --config kind-no-cni.yaml

# Antrea 설치
kubectl apply -f https://github.com/antrea-io/antrea/releases/download/v1.15.0/antrea.yml
kubectl wait --for=condition=Ready pod -l app=antrea -n kube-system --timeout=120s

# antctl 설치
curl -Lo antctl https://github.com/antrea-io/antrea/releases/download/v1.15.0/antctl-linux-x86_64
chmod +x antctl && sudo mv antctl /usr/local/bin/
```

```bash
# Tier 기반 정책 테스트
kubectl apply -f - <<EOF
apiVersion: crd.antrea.io/v1alpha1
kind: ClusterNetworkPolicy
metadata:
  name: emergency-block
spec:
  priority: 1
  tier: emergency
  appliedTo:
    - podSelector:
        matchLabels:
          quarantine: "true"    # 격리 대상 레이블
  ingress:
    - action: Drop
      from:
        - namespaceSelector: {}
  egress:
    - action: Drop
      to:
        - namespaceSelector: {}
---
apiVersion: crd.antrea.io/v1alpha1
kind: NetworkPolicy
metadata:
  name: app-allow-web
  namespace: default
spec:
  priority: 5
  tier: application
  appliedTo:
    - podSelector:
        matchLabels:
          app: web
  ingress:
    - action: Allow
      from:
        - podSelector:
            matchLabels:
              role: frontend
      ports:
        - port: 80
    - action: Drop
EOF

# 정책 확인
antctl get networkpolicy -A
antctl get appliedtogroup
```

---

## 디버깅 명령어 모음

```bash
# === Calico ===
# 정책 확인
calicoctl get networkpolicy -A
calicoctl get globalnetworkpolicy

# Felix 디버그
kubectl exec -n calico-system ds/calico-node -- calico-node -show-status

# === Cilium ===
# 엔드포인트 확인
kubectl exec -n kube-system ds/cilium -- cilium endpoint list
# 정책 확인
kubectl exec -n kube-system ds/cilium -- cilium policy get
# 서비스 확인 (kube-proxy 대체)
kubectl exec -n kube-system ds/cilium -- cilium service list

# === Antrea ===
antctl get featuregates
antctl get networkpolicy -A
antctl get appliedtogroup
# OVS 플로우 확인
kubectl exec -n kube-system ds/antrea-agent -- ovs-ofctl dump-flows br-int
```
