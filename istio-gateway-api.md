# Istio & Gateway API 교육 — Helm 설치, Helm Controller, 운영 튜닝

> Istio Service Mesh를 **Helm 기반으로 설치**하고, Ingress의 후속 표준인 **Kubernetes Gateway API**로 트래픽을 노출하며, **Flux Helm Controller**로 선언적으로 관리하는 방법을 다룹니다.
> 마지막에는 **운영 환경을 위한 튜닝(Tuned Configuration)** 방법까지 정리합니다.
> Helm 기초는 [`helm.md`](helm.md), FluxCD/GitOps 개념은 [`k8s-cicd.md`](k8s-cicd.md)를 먼저 참고하세요.

---

## 목차

1. [Istio 개요 및 아키텍처](#1-istio-개요-및-아키텍처)
2. [Gateway API 개요 — Ingress와 무엇이 다른가](#2-gateway-api-개요--ingress와-무엇이-다른가)
3. [사전 준비: Gateway API CRD 설치](#3-사전-준비-gateway-api-crd-설치)
4. [Helm 기반 Istio 설치](#4-helm-기반-istio-설치)
5. [실습: Gateway API로 서비스 노출](#5-실습-gateway-api로-서비스-노출)
6. [운영 환경 튜닝 (Tuned Configuration)](#6-운영-환경-튜닝-tuned-configuration)
7. [Helm Controller를 통한 선언적 관리 (GitOps)](#7-helm-controller를-통한-선언적-관리-gitops)
8. [검증 및 트러블슈팅](#8-검증-및-트러블슈팅)
9. [정리 및 핵심 요약](#9-정리-및-핵심-요약)

---

## 1. Istio 개요 및 아키텍처

### 한 문장 정의

> **Istio**는 마이크로서비스 간 트래픽 관리(라우팅/카나리), 보안(mTLS), 관측성(메트릭/트레이싱)을 애플리케이션 코드 수정 없이 제공하는 **Service Mesh**입니다.

### 아키텍처

```
┌───────────────────────────────────────────────────────────────┐
│                        Istio 아키텍처                           │
│                                                               │
│   Control Plane (istio-system)                                │
│   ┌─────────────────────────────────────────────┐             │
│   │                istiod                        │             │
│   │  ├── Pilot   : xDS로 프록시에 라우팅 설정 푸시  │             │
│   │  ├── Citadel : 인증서 발급/교체 (mTLS)         │             │
│   │  └── Galley  : 구성 검증                      │             │
│   └──────────────────┬──────────────────────────┘             │
│                      │ xDS (설정 푸시)                          │
│   Data Plane         ▼                                        │
│   ┌────────────────────────┐  ┌────────────────────────┐      │
│   │  Pod A                 │  │  Pod B                 │      │
│   │  ┌─────┐ ┌──────────┐  │  │  ┌─────┐ ┌──────────┐  │      │
│   │  │ App │◀▶│ Envoy    │◀─┼──┼─▶│Envoy │◀▶│ App     │  │      │
│   │  └─────┘ │(sidecar) │  │  │  └──────────┘ └─────┘  │      │
│   │          └──────────┘  │  │   mTLS 암호화 통신       │      │
│   └────────────────────────┘  └────────────────────────┘      │
│                                                               │
│   Ingress: Gateway (Envoy) ── 외부 트래픽 진입점                 │
└───────────────────────────────────────────────────────────────┘
```

- 모든 Pod에 **Envoy 프록시가 사이드카**로 주입되어 트래픽을 가로챔
- **istiod**가 xDS 프로토콜로 모든 프록시에 설정을 실시간 푸시
- Helm 차트는 `base`(CRD) / `istiod`(Control Plane) / `gateway`(Ingress) 3개로 구성

---

## 2. Gateway API 개요 — Ingress와 무엇이 다른가

### 한 문장 정의

> **Gateway API**는 Ingress의 한계를 극복하기 위해 만들어진 **차세대 표준 트래픽 관리 API**로, 역할 분리(GatewayClass/Gateway/Route)와 고급 라우팅(가중치, 헤더 매칭)을 표준 스펙으로 제공합니다.

### Ingress vs Gateway API

| 항목 | Ingress | Gateway API |
|---|---|---|
| 리소스 | Ingress 1개 | GatewayClass / Gateway / HTTPRoute 등 역할별 분리 |
| 역할 분리 | 없음 (한 리소스에 혼재) | 인프라 관리자(Gateway) / 개발자(Route) 분리 |
| 고급 라우팅 | 어노테이션 의존 (구현체마다 상이) | 가중치, 헤더/메서드 매칭 등 **표준 스펙** |
| 프로토콜 | HTTP(S) 중심 | HTTP / gRPC / TCP / TLS (Route 타입별) |
| 구현체 | nginx, contour 등 | Istio, Envoy Gateway, Contour, Cilium 등 |

```
┌────────────────────────────────────────────────────────┐
│              Gateway API 역할 분리 모델                   │
│                                                        │
│  [인프라 제공자]  GatewayClass  "istio"                  │
│        │                                               │
│  [클러스터 운영자] Gateway      리스너(포트/TLS) 정의      │
│        │                                               │
│  [개발자]        HTTPRoute    호스트/경로 → Service 연결 │
└────────────────────────────────────────────────────────┘
```

---

## 3. 사전 준비: Gateway API CRD 설치

Gateway API는 CRD로 제공되므로 먼저 설치해야 합니다. (CRD 개념은 [`k8s-crd-clusterapi.md`](k8s-crd-clusterapi.md) 참조)

```bash
# Gateway API v1.2.1 Standard Channel CRD 설치
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml

# 설치 확인
kubectl get crd | grep gateway
# gatewayclasses.gateway.networking.k8s.io
# gateways.gateway.networking.k8s.io
# grpcroutes.gateway.networking.k8s.io
# httproutes.gateway.networking.k8s.io
# referencegrants.gateway.networking.k8s.io
```

> 💡 TLSRoute, TCPRoute 등 실험적 기능이 필요하면 `experimental-install.yaml`을 사용합니다.

---

## 4. Helm 기반 Istio 설치

### 4.1 Helm Repository 등록

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm search repo istio       # 사용 가능한 차트/버전 확인
```

### 4.2 istio-base 설치 (CRD)

```bash
kubectl create namespace istio-system

helm install istio-base istio/base \
  -n istio-system \
  --version 1.24.2 \
  --set defaultRevision=default
```

### 4.3 istiod 설치 (Control Plane)

6장의 튜닝 values(`istiod-values.yaml`)를 적용하여 설치합니다.

```bash
helm install istiod istio/istiod \
  -n istio-system \
  --version 1.24.2 \
  -f istiod-values.yaml \
  --wait

kubectl get pods -n istio-system
# NAME                      READY   STATUS    RESTARTS   AGE
# istiod-6d9f7c5b8d-x2k4p   1/1     Running   0          1m
```

### 4.4 Ingress Gateway

**Gateway API를 사용하는 경우 별도 gateway 차트가 필요 없습니다.**
`Gateway` 리소스를 만들면 Istio가 Deployment/Service를 자동 배포합니다(Automated Deployment).
전통적인 Istio Gateway + VirtualService 방식을 쓸 때만 아래를 설치합니다.

```bash
# (선택) 전통적인 istio-ingressgateway 방식
kubectl create namespace istio-ingress
helm install istio-ingress istio/gateway \
  -n istio-ingress --version 1.24.2 -f gateway-values.yaml --wait
```

### 4.5 Sidecar Injection 활성화

```bash
kubectl create namespace demo
kubectl label namespace demo istio-injection=enabled

kubectl get namespace -L istio-injection
# NAME           STATUS   AGE   ISTIO-INJECTION
# demo           Active   1m    enabled
```

---

## 5. 실습: Gateway API로 서비스 노출

### 실습 1: 테스트 애플리케이션 배포

```bash
kubectl apply -n demo -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/httpbin/httpbin.yaml
```

### 실습 2: Gateway 생성

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: demo-gateway
  namespace: demo
spec:
  gatewayClassName: istio       # Istio가 제공하는 GatewayClass
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Same
```

### 실습 3: HTTPRoute 생성

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin-route
  namespace: demo
spec:
  parentRefs:
  - name: demo-gateway
  hostnames:
  - "httpbin.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: httpbin
      port: 8000
```

### 실습 4: 확인 및 테스트

```bash
kubectl apply -f gateway.yaml -f httproute.yaml

# Gateway 상태 및 External IP 확인 (LoadBalancer 자동 생성)
kubectl get gateway -n demo
# NAME           CLASS   ADDRESS          PROGRAMMED   AGE
# demo-gateway   istio   192.168.70.100   True         1m

# 라우팅 테스트
curl -s -H "Host: httpbin.example.com" http://192.168.70.100/get
```

### 실습 5: 가중치 기반 트래픽 분할 (Canary)

```yaml
    backendRefs:
    - name: httpbin-v1
      port: 8000
      weight: 90          # 90% 트래픽
    - name: httpbin-v2
      port: 8000
      weight: 10          # 10% 트래픽 (카나리)
```

---

## 6. 운영 환경 튜닝 (Tuned Configuration)

### 6.1 Control Plane (istiod) 튜닝 — istiod-values.yaml

```yaml
pilot:
  replicaCount: 2                  # Control Plane 고가용성 (기본 1)
  autoscaleEnabled: true
  autoscaleMin: 2
  autoscaleMax: 5
  cpu:
    targetAverageUtilization: 80
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: "2"
      memory: 4Gi
  podDisruptionBudget:
    minAvailable: 1                # 노드 드레인 시 최소 1개 유지

global:
  proxy:
    resources:                     # 사이드카 리소스 제한 (OOM 방지)
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: "2"
        memory: 1Gi
    holdApplicationUntilProxyStarts: true   # 사이드카 준비 전 앱 시작 방지

meshConfig:
  accessLogFile: /dev/stdout
  defaultConfig:
    concurrency: 2                 # Envoy worker thread 제한 (기본: CPU 코어 수)
    tracing:
      sampling: 1.0                # 트레이싱 샘플링 1% (기본 100%)
    terminationDrainDuration: 30s
  outboundTrafficPolicy:
    mode: ALLOW_ANY                # 엄격 제어 시 REGISTRY_ONLY
```

| 튜닝 항목 | 기본값 | 튜닝값 | 목적 |
|---|---|---|---|
| pilot.replicaCount | 1 | 2 + HPA(2~5) | Control Plane 고가용성 |
| proxy.concurrency | CPU 코어 수 | 2 | Envoy 스레드/메모리 과다 사용 방지 |
| holdApplicationUntilProxyStarts | false | true | 초기 요청 실패 방지 |
| tracing.sampling | 100 | 1.0 | 트레이싱 오버헤드 절감 |

### 6.2 Sidecar 리소스로 xDS 스코프 제한 (대규모 클러스터 핵심 튜닝)

기본적으로 모든 사이드카는 **메시 전체의 서비스 정보**를 수신하여 메모리를 낭비합니다.
네임스페이스 단위 `Sidecar` 리소스로 푸시 범위를 제한합니다.

```yaml
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata:
  name: default
  namespace: demo
spec:
  egress:
  - hosts:
    - "./*"              # 같은 네임스페이스의 서비스만
    - "istio-system/*"   # Control Plane
```

> 💡 사이드카 메모리 사용량과 istiod xDS 푸시 부하를 크게 줄이는 **가장 효과적인 튜닝**입니다.

### 6.3 Gateway (Data Plane) 튜닝 — gateway-values.yaml

```yaml
replicaCount: 2
autoscaling:
  enabled: true
  minReplicas: 2                   # 단일 장애점 제거
  maxReplicas: 5
  targetCPUUtilizationPercentage: 80
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: "2"
    memory: 1Gi
podDisruptionBudget:
  minAvailable: 1
service:
  type: LoadBalancer
  externalTrafficPolicy: Local     # 클라이언트 소스 IP 보존
affinity:                          # Gateway Pod를 서로 다른 노드에 분산
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: istio-ingress
        topologyKey: kubernetes.io/hostname
```

### 6.4 mTLS 강제 (보안 튜닝)

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system    # 루트 네임스페이스에 생성 시 메시 전체 적용
spec:
  mtls:
    mode: STRICT             # 사이드카 미주입 워크로드와의 평문 통신 차단됨에 주의
```

---

## 7. Helm Controller를 통한 선언적 관리 (GitOps)

Flux의 `source-controller` + `helm-controller`를 사용하면 4장의 수동 `helm install/upgrade` 없이
`HelmRepository` / `HelmRelease` CR로 릴리스를 선언적으로 관리할 수 있습니다.
컨트롤러가 상태를 지속적으로 조정하므로 **drift가 자동 복구**됩니다. (GitOps 개념: [`k8s-cicd.md`](k8s-cicd.md))

### 7.1 Helm Controller 설치

```bash
# Flux CLI 설치
curl -s https://fluxcd.io/install.sh | bash

# 전체 GitOps 스택이 필요 없으면 두 컨트롤러만 설치
flux install --components=source-controller,helm-controller

kubectl get pods -n flux-system
# helm-controller-xxx     1/1   Running
# source-controller-xxx   1/1   Running
```

### 7.2 HelmRepository — 차트 소스 정의

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: istio
  namespace: flux-system
spec:
  interval: 1h
  url: https://istio-release.storage.googleapis.com/charts
```

### 7.3 HelmRelease — 릴리스 정의 (버전 고정 + 자동 복구)

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: istiod
  namespace: istio-system
spec:
  interval: 10m
  dependsOn:
  - name: istio-base           # base 차트 HelmRelease 선행
  chart:
    spec:
      chart: istiod
      version: "1.24.2"        # 버전 고정 (의도치 않은 업그레이드 방지)
      sourceRef:
        kind: HelmRepository
        name: istio
        namespace: flux-system
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
  values:                      # 6장의 튜닝 values를 여기에 선언
    pilot:
      replicaCount: 2
```

```bash
kubectl get helmrelease -n istio-system
# NAME         AGE   READY   STATUS
# istio-base   2m    True    Helm install succeeded
# istiod       1m    True    Helm install succeeded

# 강제 reconcile / 릴리스 히스토리 (helm CLI와 호환)
flux reconcile helmrelease istiod -n istio-system
helm history istiod -n istio-system
```

> 💡 **VKS/Tanzu 참고**: VKS 3.7부터 `helm-controller`가 **기본 애드온**으로 도입되어
> Carvel 기반과 동일한 선언적 애드온 API로 Helm 차트를 배포/관리할 수 있습니다.
> Carvel/kapp-controller 방식은 [`carvel-kapp.md`](carvel-kapp.md) 참조.

---

## 8. 검증 및 트러블슈팅

```bash
# istioctl 설치
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.24.2 sh -
sudo install istio-1.24.2/bin/istioctl /usr/local/bin/istioctl

istioctl analyze -A          # 메시 전체 구성 검증
istioctl proxy-status        # 프록시 xDS 동기화 상태
istioctl x describe pod <pod-name> -n demo   # 특정 Pod의 mTLS/라우팅 설정
```

| 증상 | 확인 포인트 |
|---|---|
| Gateway PROGRAMMED=False | GatewayClass `istio` 존재 여부, istiod 로그 |
| HTTPRoute 미동작 | `kubectl get httproute -o yaml`의 status.conditions (Accepted/ResolvedRefs) |
| 503 응답 | 사이드카 주입 여부, STRICT mTLS 상태에서 미주입 워크로드 통신 차단 |
| 사이드카 OOMKilled | Sidecar 리소스로 xDS 스코프 제한(6.2), proxy memory limit 상향 |
| HelmRelease Ready=False | `kubectl describe helmrelease`, source-controller의 HelmRepository 상태 |

---

## 9. 정리 및 핵심 요약

```
┌──────────────────────────────────────────────────────────────┐
│                      한눈에 보는 구성 흐름                       │
│                                                              │
│  Gateway API CRD 설치                                        │
│    → Helm으로 istio-base + istiod 설치 (튜닝 values 적용)      │
│    → 네임스페이스에 istio-injection=enabled                    │
│    → Gateway + HTTPRoute 생성 (Istio가 LB 자동 배포)           │
│    → 운영 튜닝 (HA/HPA/PDB, Sidecar 스코프, STRICT mTLS)       │
│    → HelmRepository/HelmRelease로 GitOps 전환                 │
└──────────────────────────────────────────────────────────────┘
```

### 핵심 포인트 7가지

1. Istio는 `base`/`istiod`/`gateway` 3개 Helm 차트로 설치하며, Gateway API 사용 시 gateway 차트는 불필요 (Automated Deployment)
2. Gateway API는 **역할 분리**(GatewayClass/Gateway/Route)와 **표준 고급 라우팅**이 Ingress와의 핵심 차이
3. HTTPRoute의 `backendRefs.weight`로 어노테이션 없이 카나리 배포 가능
4. 운영 튜닝의 기본: istiod/Gateway **replica 2 + HPA + PDB**, 사이드카 **리소스 limit + concurrency 제한**
5. 대규모 클러스터 최우선 튜닝은 **Sidecar 리소스로 xDS 푸시 스코프 제한**
6. 트레이싱 샘플링은 운영에서 1% 수준으로 낮춰 오버헤드 절감
7. Flux **helm-controller**의 HelmRelease로 버전 고정 + 자동 remediation + drift 복구 — VKS 3.7부터는 기본 애드온
