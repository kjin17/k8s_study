# Kubernetes 클러스터 내부 DNS 장애 트러블슈팅

> Kubernetes 클러스터 안에서 **DNS가 동작하지 않을 때** 원인을 단계적으로 찾아가는 L1 트러블슈팅 가이드입니다.
> CoreDNS 상태 확인부터 CNI 플러그인 점검까지, 7단계 진단 절차와 흔한 근본 원인을 정리합니다.

---

## 목차

1. [Kubernetes에서 DNS란?](#1-kubernetes에서-dns란)
2. [흔한 증상](#2-흔한-증상)
3. [Step 1: CoreDNS Pod 확인](#3-step-1-coredns-pod-확인)
4. [Step 2: CoreDNS 로그 확인](#4-step-2-coredns-로그-확인)
5. [Step 3: CoreDNS 설정 확인](#5-step-3-coredns-설정-확인)
6. [Step 4: DNS 해석(Resolution) 검증](#6-step-4-dns-해석resolution-검증)
7. [Step 5: 네트워크 연결성 검증](#7-step-5-네트워크-연결성-검증)
8. [Step 6: NetworkPolicy 확인](#8-step-6-networkpolicy-확인)
9. [Step 7: CNI 플러그인 확인](#9-step-7-cni-플러그인-확인)
10. [흔한 근본 원인 정리](#10-흔한-근본-원인-정리)
11. [L1 트러블슈팅 플로우](#11-l1-트러블슈팅-플로우)
12. [면접 답변 예시](#12-면접-답변-예시)

---

## 1. Kubernetes에서 DNS란?

DNS는 Pod가 **IP 주소가 아닌 이름으로** Service와 통신할 수 있게 해줍니다.

```
frontend-pod  ──▶  backend-service
                   (default.svc.cluster.local)
```

- 클러스터 내부 도메인 형식: `<service>.<namespace>.svc.cluster.local`
- DNS가 없으면 클러스터 내부 애플리케이션은 서로를 **발견(discover)하거나 통신할 수 없습니다.**
- Kubernetes에서 DNS 해석은 **CoreDNS**(kube-system 네임스페이스)가 담당합니다.

---

## 2. 흔한 증상

DNS 장애가 의심되는 대표적인 신호들:

- 애플리케이션이 다른 Service에 접근하지 못함
- Pod 안에서 `nslookup` 실패
- `dig` 명령 실패
- Service 이름이 해석(resolve)되지 않음
- 간헐적인 연결 문제 (intermittent connection issues)
- **IP로는 통신되는데 Service 이름으로는 안 됨** ← DNS 문제의 결정적 단서

---

## 3. Step 1: CoreDNS Pod 확인

CoreDNS는 클러스터 내부 DNS 해석을 담당합니다. 가장 먼저 살아있는지 확인합니다.

```bash
kubectl get pods -n kube-system
```

**기대 결과:**

```
coredns-xxxxx   Running
```

CoreDNS가 Running이 아니라면:

```bash
kubectl describe pod <coredns-pod> -n kube-system
```

- 출력의 **Events 섹션**에서 CrashLoop, 스케줄링 실패, 이미지 풀 실패 등의 오류를 확인합니다.

---

## 4. Step 2: CoreDNS 로그 확인

DNS 요청이 CoreDNS까지 도달하고 있는지 검증합니다.

```bash
kubectl logs -n kube-system <coredns-pod>
```

**주의 깊게 볼 항목:**

- Crash 오류
- 설정(Configuration) 오류
- DNS 타임아웃 메시지
- 업스트림 DNS 실패 (upstream DNS failures)

---

## 5. Step 3: CoreDNS 설정 확인

CoreDNS 설정(Corefile)을 직접 확인합니다.

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

**검증 포인트:**

- forwarder(업스트림 DNS) 주소가 올바른가
- DNS zone 설정이 적절한가
- 문법(syntax) 오류가 없는가
- Corefile이 유효한가

---

## 6. Step 4: DNS 해석(Resolution) 검증

실제 Pod에 접속해서 DNS 질의를 직접 테스트합니다.

```bash
kubectl exec -it <pod-name> -- sh
```

Pod 안에서 실행:

```bash
nslookup kubernetes.default
# 또는
dig kubernetes.default
```

- **기대 결과:** DNS 서버가 Cluster IP를 반환
- **실패한다면:** DNS 서비스 자체가 비정상(unhealthy) 상태

---

## 7. Step 5: 네트워크 연결성 검증

Pod와 DNS 서비스 사이의 통신을 확인합니다.

```bash
kubectl exec -it <pod-name> -- ping kubernetes.default
```

추가 확인:

```bash
kubectl get svc -n kube-system
```

- `kube-dns` Service가 존재하는지 확인합니다. (CoreDNS의 Service 이름은 역사적 이유로 `kube-dns`)

---

## 8. Step 6: NetworkPolicy 확인

NetworkPolicy가 DNS 트래픽을 차단하고 있을 수 있습니다.

```bash
kubectl get networkpolicy -A
```

**DNS가 필요로 하는 포트 — UDP/TCP 53이 허용되어 있는지 확인:**

| 프로토콜 | 포트 |
|---------|------|
| UDP | 53 |
| TCP | 53 |

---

## 9. Step 7: CNI 플러그인 확인

CNI가 깨져 있으면 DNS 트래픽이 CoreDNS까지 도달하지 못할 수 있습니다.

**대표적인 CNI:**

- Calico
- Flannel
- Cilium
- Weave

```bash
kubectl get pods -n kube-system
```

- CNI 관련 Pod들이 모두 healthy(Running)인지 확인합니다.

> 💡 CNI별 비교는 [`cni-comparison/`](cni-comparison/) 자료를 참고하세요.

---

## 10. 흔한 근본 원인 정리

| # | 원인 |
|---|------|
| 1 | CoreDNS Pod 크래시 |
| 2 | 잘못된 CoreDNS 설정 (Corefile 오류) |
| 3 | kube-dns Service 누락 |
| 4 | NetworkPolicy가 DNS(53 포트) 차단 |
| 5 | CNI 플러그인 이슈 |
| 6 | 워커 노드 네트워킹 문제 |
| 7 | 방화벽이 53 포트 차단 |
| 8 | CoreDNS Pod 리소스 고갈 (resource starvation) |

---

## 11. L1 트러블슈팅 플로우

```
DNS Not Working (DNS 동작 안 함)
        │
        ▼
CoreDNS Pod 확인 (kubectl get pods -n kube-system)
        │
        ▼
CoreDNS 로그 확인 (kubectl logs)
        │
        ▼
CoreDNS 설정 확인 (configmap coredns)
        │
        ▼
Pod에서 nslookup / dig 실행
        │
        ▼
kube-dns Service 확인
        │
        ▼
NetworkPolicy 확인 (UDP/TCP 53)
        │
        ▼
CNI 플러그인 확인
        │
        ▼
해결 안 되면 L2 / L3 에스컬레이션
```

---

## 12. 면접 답변 예시

**Q: Kubernetes 클러스터 내부의 DNS 장애를 어떻게 트러블슈팅하시겠습니까?**

**A:** 먼저 kube-system 네임스페이스에서 **CoreDNS Pod가 정상 실행 중인지** 확인합니다. 다음으로 **CoreDNS 로그와 설정(Corefile)** 을 검토합니다. 그 후 임의의 Pod에 들어가 **nslookup이나 dig로 DNS 해석을 직접 테스트**합니다. 그래도 실패하면 **kube-dns Service 존재 여부, NetworkPolicy의 53 포트(UDP/TCP) 허용 여부, CNI 플러그인 상태**를 순서대로 검증합니다. 각 단계에서 발견한 내용을 바탕으로 원인을 좁혀가고, L1 수준에서 해결되지 않으면 근거 자료와 함께 L2/L3로 에스컬레이션합니다.

---

## 핵심 요약

- **IP는 되는데 이름이 안 되면 DNS 문제**다.
- 진단 순서: **CoreDNS Pod → 로그 → 설정 → nslookup/dig → Service → NetworkPolicy → CNI**
- DNS는 **UDP/TCP 53 포트**를 사용한다 — NetworkPolicy와 방화벽에서 반드시 허용 확인.
- CoreDNS의 Service 이름은 `kube-dns`다 (헷갈리지 말 것).
